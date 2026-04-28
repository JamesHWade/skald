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
