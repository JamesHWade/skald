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
