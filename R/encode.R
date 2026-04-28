#' Encode queries
#'
#' Encodes query strings into ColBERT token embeddings with the model's query
#' prefix and query-length behavior.
#'
#' @param model A [SkaldModel].
#' @param queries Character vector of query strings.
#' @param batch_size Encoding batch size.
#' @param show_progress Whether PyLate should show a progress bar.
#' @param precision Embedding precision passed to PyLate.
#' @param normalize_embeddings Whether to L2-normalize token embeddings.
#' @param convert_to_numpy Whether PyLate should return NumPy arrays instead of
#'   torch tensors.
#' @param ... Additional arguments passed to the PyLate `encode()` method.
#'
#' @returns A [SkaldEmbeddings] object with `kind = "query"`.
#' @export
#' @examplesIf interactive()
#' query_embeddings <- skald_encode_queries(model, "How do I filter rows?")
skald_encode_queries <- function(
  model,
  queries,
  batch_size = 32,
  show_progress = interactive(),
  precision = "float32",
  normalize_embeddings = TRUE,
  convert_to_numpy = TRUE,
  ...
) {
  .skald_check_model(model)
  queries <- as.character(queries)

  args <- .skald_compact(list(
    sentences = as.list(queries),
    batch_size = as.integer(batch_size),
    show_progress_bar = isTRUE(show_progress),
    precision = precision,
    normalize_embeddings = isTRUE(normalize_embeddings),
    convert_to_numpy = isTRUE(convert_to_numpy),
    is_query = TRUE,
    ...
  ))

  emb <- do.call(.skald_model_py(model)$encode, args)

  new_skald_embeddings(
    py = emb,
    kind = "query",
    n = length(queries),
    model = model,
    metadata = list(inputs = queries)
  )
}

#' Encode documents
#'
#' Encodes document strings into ColBERT token embeddings with the model's
#' document prefix, skiplist, and document-length behavior.
#'
#' @inheritParams skald_encode_queries
#' @param documents Character vector of document strings.
#'
#' @returns A [SkaldEmbeddings] object with `kind = "document"`.
#' @export
#' @examplesIf interactive()
#' document_embeddings <- skald_encode_documents(model, c("Use filter() to keep rows."))
skald_encode_documents <- function(
  model,
  documents,
  batch_size = 32,
  show_progress = interactive(),
  precision = "float32",
  normalize_embeddings = TRUE,
  convert_to_numpy = TRUE,
  ...
) {
  .skald_check_model(model)
  documents <- as.character(documents)

  args <- .skald_compact(list(
    sentences = as.list(documents),
    batch_size = as.integer(batch_size),
    show_progress_bar = isTRUE(show_progress),
    precision = precision,
    normalize_embeddings = isTRUE(normalize_embeddings),
    convert_to_numpy = isTRUE(convert_to_numpy),
    is_query = FALSE,
    ...
  ))

  emb <- do.call(.skald_model_py(model)$encode, args)

  new_skald_embeddings(
    py = emb,
    kind = "document",
    n = length(documents),
    model = model,
    metadata = list(inputs = documents)
  )
}

#' Encode a data-frame column
#'
#' Encodes one text column and either appends a list-column of opaque Python
#' embeddings or returns a [SkaldEmbeddings] object directly.
#'
#' @param .data A data frame or tibble.
#' @param model A [SkaldModel].
#' @param text <[`tidy-select`][tidyselect::language]> Column containing text to
#'   encode.
#' @param kind Embedding kind, either `"document"` or `"query"`.
#' @param name Name of the output list-column. Use `NULL` to return only the
#'   [SkaldEmbeddings] object.
#' @param batch_size Encoding batch size.
#' @param ... Additional arguments passed to [skald_encode_queries()] or
#'   [skald_encode_documents()].
#'
#' @returns A tibble with an embedding list-column, or a [SkaldEmbeddings] object
#'   when `name = NULL`.
#' @export
#' @examplesIf interactive()
#' docs <- tibble::tibble(text = "Use filter() to keep rows.")
#' skald_encode_col(docs, model, text)
skald_encode_col <- function(
  .data,
  model,
  text,
  kind = c("document", "query"),
  name = ".skald_embedding",
  batch_size = 32,
  ...
) {
  kind <- rlang::arg_match(kind)
  data <- tibble::as_tibble(.data)
  text_col <- .skald_eval_select_one({{ text }}, data, "text")
  values <- data[[text_col]]

  emb <- if (identical(kind, "query")) {
    skald_encode_queries(model, values, batch_size = batch_size, ...)
  } else {
    skald_encode_documents(model, values, batch_size = batch_size, ...)
  }

  if (is.null(name)) {
    return(emb)
  }

  .skald_column_exists_abort(data, name, "name")
  data[[name]] <- .skald_embedding_items(emb)
  data
}

.skald_embedding_items <- function(embeddings) {
  n <- embeddings@n

  lapply(seq_len(n), function(i) {
    tryCatch(
      embeddings@py[[i - 1L]],
      error = function(e) embeddings@py
    )
  })
}
