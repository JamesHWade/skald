#' Create a PLAID index
#'
#' Creates or connects to a PyLate PLAID index for late-interaction retrieval.
#'
#' @param index_folder Directory where index files are stored.
#' @param index_name Name of the index within `index_folder`.
#' @param overwrite Whether to overwrite an existing index.
#' @param use_fast Whether to use PyLate's fast PLAID backend.
#' @param nbits Number of bits used for product quantization.
#' @param kmeans_niters Number of k-means iterations used when building the
#'   index.
#' @param n_ivf_probe Number of IVF cells to probe at query time.
#' @param n_full_scores Number of candidates to fully score.
#' @param device Optional torch device string.
#' @param show_progress Whether PyLate should show progress output.
#' @param ... Additional arguments passed to `pylate.indexes.PLAID`.
#'
#' @returns A [SkaldIndex] object.
#' @export
#' @examplesIf interactive()
#' index <- skald_index_create("demo-index", overwrite = TRUE)
skald_index_create <- function(
  index_folder = "skald-index",
  index_name = "colbert",
  overwrite = FALSE,
  use_fast = TRUE,
  nbits = 4,
  kmeans_niters = 4,
  n_ivf_probe = 8,
  n_full_scores = 8192,
  device = NULL,
  show_progress = interactive(),
  ...
) {
  indexes <- skald_py_mod("indexes")
  fs::dir_create(index_folder)

  args <- .skald_compact(list(
    index_folder = index_folder,
    index_name = index_name,
    override = isTRUE(overwrite),
    use_fast = isTRUE(use_fast),
    nbits = as.integer(nbits),
    kmeans_niters = as.integer(kmeans_niters),
    n_ivf_probe = as.integer(n_ivf_probe),
    n_full_scores = as.integer(n_full_scores),
    device = device,
    show_progress = isTRUE(show_progress),
    ...
  ))

  py_index <- do.call(indexes$PLAID, args)

  new_skald_index(
    py = py_index,
    index_folder = index_folder,
    index_name = index_name,
    use_fast = use_fast,
    nbits = nbits,
    n_ivf_probe = n_ivf_probe,
    n_full_scores = n_full_scores,
    metadata_path = file.path(index_folder, paste0(index_name, "-metadata.json"))
  )
}

#' Add documents to a PLAID index
#'
#' Encodes document text and adds the resulting embeddings to a [SkaldIndex].
#'
#' @param index A [SkaldIndex].
#' @param model A [SkaldModel].
#' @param .data A data frame or tibble of documents.
#' @param id <[`tidy-select`][tidyselect::language]> Column containing document
#'   identifiers.
#' @param text <[`tidy-select`][tidyselect::language]> Column containing document
#'   text.
#' @param context Optional <[`tidy-select`][tidyselect::language]> context column
#'   included in embedding text.
#' @param batch_size Encoding batch size.
#' @param text_template Glue template used to combine `context` and `text`.
#' @param ... Additional arguments passed to [skald_encode_documents()].
#'
#' @returns The updated [SkaldIndex].
#' @export
#' @examplesIf interactive()
#' docs <- tibble::tibble(id = "a", text = "Use filter() to keep rows.")
#' skald_index_add(index, model, docs, id = id, text = text)
skald_index_add <- function(
  index,
  model,
  .data,
  id,
  text,
  context = NULL,
  batch_size = 32,
  text_template = "{context}\n\n{text}",
  ...
) {
  .skald_check_index(index)
  .skald_check_model(model)

  data <- tibble::as_tibble(.data)
  id_col <- .skald_eval_select_one({{ id }}, data, "id")
  text_col <- .skald_eval_select_one({{ text }}, data, "text")

  context_quo <- rlang::enquo(context)
  context_col <- if (rlang::quo_is_null(context_quo)) {
    NULL
  } else {
    .skald_eval_select_one({{ context }}, data, "context")
  }

  ids <- as.character(data[[id_col]])
  embedding_text <- .skald_template_text(
    text = data[[text_col]],
    context = if (!is.null(context_col)) data[[context_col]] else NULL,
    text_template = text_template
  )

  emb <- skald_encode_documents(
    model,
    embedding_text,
    batch_size = batch_size,
    ...
  )

  py_index <- index@py
  if (is.null(py_index)) {
    py_index <- skald_index_create(
      index_folder = index@index_folder,
      index_name = index@index_name,
      overwrite = FALSE,
      use_fast = index@use_fast,
      nbits = index@nbits,
      n_ivf_probe = index@n_ivf_probe,
      n_full_scores = index@n_full_scores
    )@py
  }

  added <- py_index$add_documents(
    documents_ids = as.list(ids),
    documents_embeddings = emb@py
  )

  if (!is.null(added)) {
    index@py <- added
  } else {
    index@py <- py_index
  }

  metadata <- data
  metadata$id <- ids
  metadata$embedding_text <- embedding_text
  .skald_write_index_metadata(index, metadata)

  index
}

#' Retrieve from a PLAID index
#'
#' Encodes one or more queries and retrieves matching document ids from a
#' [SkaldIndex].
#'
#' @param index A [SkaldIndex].
#' @param model A [SkaldModel].
#' @param query Character vector of query strings.
#' @param top_k Number of results per query.
#' @param query_id Optional query identifiers. Defaults to generated ids.
#' @param batch_size Encoding and retrieval batch size.
#' @param k_token Number of token-level candidates requested from PyLate.
#' @param device Optional torch device string.
#' @param subset Optional character vector of document ids to restrict retrieval.
#' @param include_text Whether to join stored index metadata when available.
#' @param ... Additional arguments passed to the PyLate retriever.
#'
#' @returns A tibble with query ids, ranks, document ids, and scores.
#' @export
#' @examplesIf interactive()
#' skald_index_retrieve(index, model, query = "How do I filter rows?")
skald_index_retrieve <- function(
  index,
  model,
  query,
  top_k = 10,
  query_id = NULL,
  batch_size = 32,
  k_token = 100,
  device = NULL,
  subset = NULL,
  include_text = TRUE,
  ...
) {
  .skald_check_index(index)
  .skald_check_model(model)

  query <- as.character(query)
  query_id <- query_id %||% paste0("q", seq_along(query))
  query_id <- as.character(query_id)

  q_emb <- skald_encode_queries(
    model,
    query,
    batch_size = batch_size
  )

  retrieve_mod <- skald_py_mod("retrieve")
  retriever <- retrieve_mod$ColBERT(index = index@py)

  args <- .skald_compact(list(
    queries_embeddings = q_emb@py,
    k = as.integer(top_k),
    k_token = as.integer(k_token),
    batch_size = as.integer(batch_size),
    device = device,
    subset = subset,
    ...
  ))

  results <- do.call(retriever$retrieve, args)
  out <- skald_results_to_tibble(results, query_id = query_id, query = query)

  if (isTRUE(include_text)) {
    out <- .skald_join_index_metadata(out, index)
  }

  out
}
