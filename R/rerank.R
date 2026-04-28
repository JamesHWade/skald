#' Rerank candidate documents with a ColBERT model
#'
#' Reranks a data frame of first-stage candidate documents by late-interaction
#' MaxSim score.
#'
#' @param .data A data frame or tibble of candidate documents.
#' @param model A [SkaldModel].
#' @param query Query string, or a column that resolves to one query string per
#'   group.
#' @param text <[`tidy-select`][tidyselect::language]> Text column to rerank.
#' @param id Optional <[`tidy-select`][tidyselect::language]> column or columns
#'   that identify candidate rows.
#' @param query_id Optional <[`tidy-select`][tidyselect::language]> column or
#'   columns that identify query groups.
#' @param top_k Optional number of highest-ranked rows to keep per group.
#' @param batch_size Encoding batch size.
#' @param device Optional torch device string used during reranking.
#' @param score_col,rank_col Names for the output score and rank columns.
#' @param keep_all Whether to keep rows that are not returned by the reranker.
#' @param ... Additional arguments passed to the PyLate `encode()` method.
#'
#' @returns A tibble with the original columns plus late-interaction score and
#'   rank columns.
#' @export
#' @examplesIf interactive()
#' candidates <- tibble::tibble(doc_id = "a", text = "Use filter() to keep rows.")
#' skald_rerank(candidates, model, query = "filter rows", text = text, id = doc_id)
skald_rerank <- function(
  .data,
  model,
  query,
  text,
  id = NULL,
  query_id = NULL,
  top_k = NULL,
  batch_size = 32,
  device = NULL,
  score_col = "late_score",
  rank_col = "late_rank",
  keep_all = TRUE,
  ...
) {
  .skald_check_model(model)
  data <- tibble::as_tibble(.data)

  .skald_column_exists_abort(data, score_col, "score_col")
  .skald_column_exists_abort(data, rank_col, "rank_col")

  text_quo <- rlang::enquo(text)
  id_quo <- rlang::enquo(id)
  query_quo <- rlang::enquo(query)
  query_id_quo <- rlang::enquo(query_id)

  text_col <- names(tidyselect::eval_select(text_quo, data))
  if (length(text_col) != 1) {
    cli::cli_abort("{.arg text} must select exactly one column.")
  }

  id_cols <- if (rlang::quo_is_null(id_quo)) {
    character()
  } else {
    names(tidyselect::eval_select(id_quo, data))
  }

  query_id_cols <- if (rlang::quo_is_null(query_id_quo)) {
    character()
  } else {
    names(tidyselect::eval_select(query_id_quo, data))
  }

  group_cols <- unique(c(dplyr::group_vars(.data), query_id_cols))
  if (length(group_cols)) {
    data <- dplyr::group_by(data, dplyr::across(dplyr::all_of(group_cols)))
  }

  groups <- .skald_group_split(data)
  out <- lapply(groups, function(group) {
    .skald_rerank_group(
      group = group,
      model = model,
      query_quo = query_quo,
      text_col = text_col,
      id_cols = id_cols,
      top_k = top_k,
      batch_size = batch_size,
      device = device,
      score_col = score_col,
      rank_col = rank_col,
      keep_all = keep_all,
      ...
    )
  })

  dplyr::bind_rows(out)
}

.skald_rerank_group <- function(
  group,
  model,
  query_quo,
  text_col,
  id_cols,
  top_k,
  batch_size,
  device,
  score_col,
  rank_col,
  keep_all,
  ...
) {
  group <- tibble::as_tibble(group)
  n <- nrow(group)

  if (!n) {
    group[[score_col]] <- numeric()
    group[[rank_col]] <- integer()
    return(group)
  }

  query_value <- rlang::eval_tidy(query_quo, data = group)
  query_string <- if (length(query_value) == 1) {
    as.character(query_value)
  } else {
    .skald_unique_non_missing(as.character(query_value), "query")
  }

  group$.skald_input_order <- seq_len(n)
  group$.skald_internal_id <- .skald_candidate_ids(group, id_cols)

  scores <- .skald_rerank_scores(
    model = model,
    query = query_string,
    documents = group[[text_col]],
    ids = group$.skald_internal_id,
    batch_size = batch_size,
    device = device,
    ...
  )

  scores <- tibble::as_tibble(scores)
  names(scores) <- c(".skald_internal_id", score_col)
  scores[[score_col]] <- as.double(scores[[score_col]])

  joined <- if (isTRUE(keep_all)) {
    dplyr::left_join(group, scores, by = ".skald_internal_id")
  } else {
    dplyr::inner_join(group, scores, by = ".skald_internal_id")
  }

  joined <- dplyr::arrange(
    joined,
    dplyr::desc(.data[[score_col]]),
    .data$.skald_input_order
  )
  joined[[rank_col]] <- seq_len(nrow(joined))

  if (!is.null(top_k)) {
    joined <- dplyr::slice_head(joined, n = as.integer(top_k))
  }

  joined$.skald_input_order <- NULL
  joined$.skald_internal_id <- NULL
  joined
}

.skald_candidate_ids <- function(group, id_cols) {
  if (!length(id_cols)) {
    return(as.character(seq_len(nrow(group))))
  }

  pieces <- lapply(id_cols, function(col) .skald_as_string_id(group[[col]]))
  ids <- do.call(paste, c(pieces, sep = "::"))

  if (anyDuplicated(ids)) {
    ids <- paste(ids, seq_len(nrow(group)), sep = "::")
  }

  ids
}

.skald_rerank_scores <- function(
  model,
  query,
  documents,
  ids,
  batch_size,
  device,
  ...
) {
  score_fun <- model@metadata$score_fun
  if (is.function(score_fun)) {
    values <- score_fun(query = query, documents = documents, ids = ids)
    return(tibble::tibble(id = ids, score = as.double(values)))
  }

  py_model <- .skald_model_py(model)

  q_args <- .skald_compact(list(
    sentences = list(query),
    batch_size = as.integer(batch_size),
    is_query = TRUE,
    show_progress_bar = FALSE,
    ...
  ))
  d_args <- .skald_compact(list(
    sentences = list(as.list(as.character(documents))),
    batch_size = as.integer(batch_size),
    is_query = FALSE,
    show_progress_bar = FALSE,
    ...
  ))

  queries_embeddings <- do.call(py_model$encode, q_args)
  documents_embeddings <- do.call(py_model$encode, d_args)

  rank_mod <- skald_py_mod("rank")
  raw <- rank_mod$rerank(
    documents_ids = list(as.list(ids)),
    queries_embeddings = queries_embeddings,
    documents_embeddings = documents_embeddings,
    device = device
  )

  converted <- reticulate::py_to_r(raw)
  results <- converted[[1]]

  tibble::tibble(
    id = vapply(results, function(x) as.character(x$id %||% x[["id"]]), character(1)),
    score = vapply(results, function(x) as.double(x$score %||% x[["score"]]), numeric(1))
  )
}

#' Retrieve from ragnar and rerank with skald
#'
#' Runs `ragnar::ragnar_retrieve()` as a first-stage retriever and reranks the
#' candidate chunks with a [SkaldModel].
#'
#' @param store A ragnar store object.
#' @param model A [SkaldModel].
#' @param query Query string.
#' @param top_k Number of reranked results to return.
#' @param candidate_k Number of first-stage ragnar candidates to retrieve.
#' @param ... Additional arguments passed to `ragnar::ragnar_retrieve()`.
#' @param deoverlap Whether to ask ragnar to deoverlap retrieved chunks.
#' @param filter Optional ragnar filter expression.
#' @param include_first_stage Whether to keep first-stage `rank` and `score`
#'   columns when present.
#'
#' @returns A tibble of ragnar results with `late_score` and `late_rank`
#'   columns.
#' @export
#' @examplesIf interactive()
#' skald_retrieve_ragnar(store, model, query = "How do I filter rows?")
skald_retrieve_ragnar <- function(
  store,
  model,
  query,
  top_k = 5,
  candidate_k = max(30, top_k * 10),
  ...,
  deoverlap = TRUE,
  filter,
  include_first_stage = TRUE
) {
  .skald_check_installed("ragnar", "Install ragnar to retrieve from RagnarStore objects.")

  dots <- rlang::dots_list(...)
  filter_quo <- rlang::enquo(filter)

  hits <- if (rlang::quo_is_missing(filter_quo)) {
    rlang::exec(
      ragnar::ragnar_retrieve,
      store,
      query,
      top_k = candidate_k,
      !!!dots,
      deoverlap = deoverlap
    )
  } else {
    rlang::inject(
      ragnar::ragnar_retrieve(
        store,
        query,
        top_k = !!candidate_k,
        !!!dots,
        deoverlap = !!deoverlap,
        filter = !!filter_quo
      )
    )
  }

  hits <- tibble::as_tibble(hits)

  if (!nrow(hits)) {
    hits$late_score <- numeric()
    hits$late_rank <- integer()
    return(hits)
  }

  text_col <- if ("text" %in% names(hits)) {
    "text"
  } else {
    char_cols <- names(hits)[vapply(hits, is.character, logical(1))]
    if (!length(char_cols)) {
      cli::cli_abort("Could not identify a candidate text column in ragnar results.")
    }
    char_cols[[1]]
  }

  id_cols <- intersect(c("origin", "doc_id", "chunk_id"), names(hits))

  out <- skald_rerank(
    hits,
    model = model,
    query = query,
    text = tidyselect::all_of(text_col),
    id = tidyselect::all_of(id_cols),
    top_k = top_k
  )

  if (!isTRUE(include_first_stage)) {
    first_stage_cols <- intersect(c("rank", "score"), names(out))
    out <- dplyr::select(out, -dplyr::all_of(first_stage_cols))
  }

  out
}
