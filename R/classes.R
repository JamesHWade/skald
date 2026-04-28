#' PyLate-backed ColBERT model
#'
#' S7 class for a late-interaction model. Users normally create instances with
#' [skald_model()].
#'
#' @param py Opaque Python model object, or `NULL` for a model specification that
#'   can be rehydrated.
#' @param model_name_or_path Hugging Face model id or local path.
#' @param backend Backend name.
#' @param device Optional torch device string.
#' @param query_length Optional query token length.
#' @param document_length Optional document token length.
#' @param query_prefix Optional query prefix token.
#' @param document_prefix Optional document prefix token.
#' @param trust_remote_code Whether model loading may execute remote code.
#' @param revision Optional model revision.
#' @param local_files_only Whether model loading should avoid downloads.
#' @param created_at Creation timestamp.
#' @param metadata Additional R-side metadata.
#' @export
SkaldModel <- S7::new_class(
  "SkaldModel",
  package = "skald",
  properties = list(
    py = S7::new_property(S7::class_any, default = NULL),
    model_name_or_path = S7::class_character,
    backend = S7::new_property(S7::class_character, default = "pylate"),
    device = S7::new_property(S7::class_any, default = NULL),
    query_length = S7::new_property(S7::class_any, default = NULL),
    document_length = S7::new_property(S7::class_any, default = NULL),
    query_prefix = S7::new_property(S7::class_any, default = NULL),
    document_prefix = S7::new_property(S7::class_any, default = NULL),
    trust_remote_code = S7::new_property(S7::class_logical, default = FALSE),
    revision = S7::new_property(S7::class_any, default = NULL),
    local_files_only = S7::new_property(S7::class_logical, default = FALSE),
    created_at = S7::new_property(S7::class_any, default = NULL),
    metadata = S7::new_property(S7::class_list, default = list())
  )
)

#' Opaque late-interaction embeddings
#'
#' S7 class for query or document token embeddings returned by
#' [skald_encode_queries()] and [skald_encode_documents()].
#'
#' @param py Opaque Python embedding object.
#' @param kind Embedding kind, either `"query"` or `"document"`.
#' @param n Number of encoded inputs.
#' @param model_id Model label associated with the embeddings.
#' @param backend Backend name.
#' @param metadata Additional R-side metadata.
#' @export
SkaldEmbeddings <- S7::new_class(
  "SkaldEmbeddings",
  package = "skald",
  properties = list(
    py = S7::new_property(S7::class_any, default = NULL),
    kind = S7::class_character,
    n = S7::class_integer,
    model_id = S7::new_property(S7::class_any, default = NULL),
    backend = S7::new_property(S7::class_character, default = "pylate"),
    metadata = S7::new_property(S7::class_list, default = list())
  )
)

#' PLAID index handle
#'
#' S7 class for a PyLate PLAID index created with [skald_index_create()].
#'
#' @param py Opaque Python index object, or `NULL` when the index will be
#'   reconnected lazily.
#' @param index_folder Directory containing index files.
#' @param index_name Index name within `index_folder`.
#' @param backend Backend name.
#' @param use_fast Whether the fast PLAID backend is requested.
#' @param nbits Number of bits used for product quantization.
#' @param n_ivf_probe Number of IVF cells to probe during retrieval.
#' @param n_full_scores Number of candidates to fully score.
#' @param metadata_path Path to JSON metadata for indexed rows.
#' @param created_at Creation timestamp.
#' @export
SkaldIndex <- S7::new_class(
  "SkaldIndex",
  package = "skald",
  properties = list(
    py = S7::new_property(S7::class_any, default = NULL),
    index_folder = S7::class_character,
    index_name = S7::class_character,
    backend = S7::new_property(S7::class_character, default = "pylate"),
    use_fast = S7::new_property(S7::class_logical, default = TRUE),
    nbits = S7::new_property(S7::class_integer, default = 4L),
    n_ivf_probe = S7::new_property(S7::class_integer, default = 8L),
    n_full_scores = S7::new_property(S7::class_integer, default = 8192L),
    metadata_path = S7::new_property(S7::class_any, default = NULL),
    created_at = S7::new_property(S7::class_any, default = NULL)
  )
)

#' Local skald store
#'
#' S7 class for a DuckDB metadata store paired with a PyLate PLAID index.
#'
#' @param location Store directory.
#' @param metadata_db DuckDB metadata database path.
#' @param index_folder Directory containing PLAID index files.
#' @param index_name Index name within `index_folder`.
#' @param model_spec Stored model specification.
#' @param backend Backend name.
#' @param read_only Whether the store connection is read-only.
#' @param name Optional short store name.
#' @param title Optional human-readable store title.
#' @param text_template Glue template used to construct embedding text.
#' @param created_at Creation timestamp.
#' @export
SkaldStore <- S7::new_class(
  "SkaldStore",
  package = "skald",
  properties = list(
    location = S7::class_character,
    metadata_db = S7::class_character,
    index_folder = S7::class_character,
    index_name = S7::class_character,
    model_spec = S7::new_property(S7::class_any, default = NULL),
    backend = S7::new_property(S7::class_character, default = "pylate"),
    read_only = S7::new_property(S7::class_logical, default = FALSE),
    name = S7::new_property(S7::class_any, default = NULL),
    title = S7::new_property(S7::class_any, default = NULL),
    text_template = S7::new_property(S7::class_character, default = "{context}\n\n{text}"),
    created_at = S7::new_property(S7::class_any, default = NULL)
  )
)

#' Retriever configuration
#'
#' S7 class attached to retriever closures created by [skald_retriever()].
#'
#' @param store Store or first-stage retriever backing the closure.
#' @param model Optional [SkaldModel] used for reranking first-stage results.
#' @param top_k Number of final results to return.
#' @param candidate_k Number of first-stage candidates to rerank.
#' @param format Output format.
#' @param metadata Additional R-side metadata.
#' @export
SkaldRetriever <- S7::new_class(
  "SkaldRetriever",
  package = "skald",
  properties = list(
    store = S7::new_property(S7::class_any, default = NULL),
    model = S7::new_property(S7::class_any, default = NULL),
    top_k = S7::class_integer,
    candidate_k = S7::new_property(S7::class_any, default = NULL),
    format = S7::class_character,
    metadata = S7::new_property(S7::class_list, default = list())
  )
)

new_skald_model <- function(
  py = NULL,
  model_name_or_path,
  backend = "pylate",
  device = NULL,
  query_length = NULL,
  document_length = NULL,
  query_prefix = NULL,
  document_prefix = NULL,
  trust_remote_code = FALSE,
  revision = NULL,
  local_files_only = FALSE,
  created_at = .skald_now(),
  metadata = list()
) {
  SkaldModel(
    py = py,
    model_name_or_path = as.character(model_name_or_path),
    backend = as.character(backend),
    device = device,
    query_length = query_length,
    document_length = document_length,
    query_prefix = query_prefix,
    document_prefix = document_prefix,
    trust_remote_code = isTRUE(trust_remote_code),
    revision = revision,
    local_files_only = isTRUE(local_files_only),
    created_at = created_at,
    metadata = metadata
  )
}

new_skald_embeddings <- function(py, kind, n, model = NULL, backend = "pylate", metadata = list()) {
  kind <- rlang::arg_match(kind, c("query", "document"))

  SkaldEmbeddings(
    py = py,
    kind = kind,
    n = as.integer(n),
    model_id = if (!is.null(model)) .skald_model_label(model) else NULL,
    backend = backend,
    metadata = metadata
  )
}

new_skald_index <- function(
  py = NULL,
  index_folder,
  index_name = "colbert",
  backend = "pylate",
  use_fast = TRUE,
  nbits = 4L,
  n_ivf_probe = 8L,
  n_full_scores = 8192L,
  metadata_path = NULL,
  created_at = .skald_now()
) {
  SkaldIndex(
    py = py,
    index_folder = normalizePath(index_folder, mustWork = FALSE),
    index_name = as.character(index_name),
    backend = as.character(backend),
    use_fast = isTRUE(use_fast),
    nbits = as.integer(nbits),
    n_ivf_probe = as.integer(n_ivf_probe),
    n_full_scores = as.integer(n_full_scores),
    metadata_path = metadata_path,
    created_at = created_at
  )
}

new_skald_store <- function(
  location,
  metadata_db,
  index_folder,
  index_name = "colbert",
  model_spec = NULL,
  backend = "pylate",
  read_only = FALSE,
  name = NULL,
  title = NULL,
  text_template = "{context}\n\n{text}",
  created_at = .skald_now()
) {
  SkaldStore(
    location = normalizePath(location, mustWork = FALSE),
    metadata_db = normalizePath(metadata_db, mustWork = FALSE),
    index_folder = normalizePath(index_folder, mustWork = FALSE),
    index_name = as.character(index_name),
    model_spec = model_spec,
    backend = as.character(backend),
    read_only = isTRUE(read_only),
    name = name,
    title = title,
    text_template = as.character(text_template),
    created_at = created_at
  )
}

new_skald_retriever_config <- function(
  store,
  model = NULL,
  top_k = 5L,
  candidate_k = NULL,
  format = "tibble",
  metadata = list()
) {
  format <- rlang::arg_match(format, c("tibble", "markdown", "context"))

  SkaldRetriever(
    store = store,
    model = model,
    top_k = as.integer(top_k),
    candidate_k = candidate_k,
    format = format,
    metadata = metadata
  )
}

S7::method(print, SkaldModel) <- function(x, ...) {
  cat("<SkaldModel>\n")
  cat("  model: ", x@model_name_or_path, "\n", sep = "")
  cat("  device: ", x@device %||% "<auto>", "\n", sep = "")
  cat("  backend: ", x@backend, "\n", sep = "")
  cat("  loaded: ", if (!is.null(x@py)) "TRUE" else "FALSE", "\n", sep = "")
  invisible(x)
}

S7::method(print, SkaldEmbeddings) <- function(x, ...) {
  cat("<SkaldEmbeddings>\n")
  cat("  kind: ", x@kind, "\n", sep = "")
  cat("  n: ", x@n, "\n", sep = "")
  cat("  backend: ", x@backend, "\n", sep = "")
  cat("  opaque: ", if (!is.null(x@py)) "TRUE" else "FALSE", "\n", sep = "")
  invisible(x)
}

S7::method(print, SkaldIndex) <- function(x, ...) {
  cat("<SkaldIndex>\n")
  cat("  folder: ", x@index_folder, "\n", sep = "")
  cat("  name: ", x@index_name, "\n", sep = "")
  cat("  backend: ", x@backend, "\n", sep = "")
  cat("  loaded: ", if (!is.null(x@py)) "TRUE" else "FALSE", "\n", sep = "")
  invisible(x)
}

S7::method(print, SkaldStore) <- function(x, ...) {
  cat("<SkaldStore>\n")
  cat("  location: ", x@location, "\n", sep = "")
  cat("  index: ", file.path(x@index_folder, x@index_name), "\n", sep = "")
  cat("  model: ", .skald_model_label(x@model_spec) %||% "<unknown>", "\n", sep = "")
  cat("  read_only: ", if (isTRUE(x@read_only)) "TRUE" else "FALSE", "\n", sep = "")
  invisible(x)
}

S7::method(print, SkaldRetriever) <- function(x, ...) {
  cat("<SkaldRetriever>\n")
  cat("  top_k: ", x@top_k, "\n", sep = "")
  cat("  candidate_k: ", x@candidate_k %||% "<none>", "\n", sep = "")
  cat("  format: ", x@format, "\n", sep = "")
  invisible(x)
}

.skald_register_print_methods <- function() {
  S7::method(print, SkaldModel) <- function(x, ...) {
    cat("<SkaldModel>\n")
    cat("  model: ", x@model_name_or_path, "\n", sep = "")
    cat("  device: ", x@device %||% "<auto>", "\n", sep = "")
    cat("  backend: ", x@backend, "\n", sep = "")
    cat("  loaded: ", if (!is.null(x@py)) "TRUE" else "FALSE", "\n", sep = "")
    invisible(x)
  }

  S7::method(print, SkaldEmbeddings) <- function(x, ...) {
    cat("<SkaldEmbeddings>\n")
    cat("  kind: ", x@kind, "\n", sep = "")
    cat("  n: ", x@n, "\n", sep = "")
    cat("  backend: ", x@backend, "\n", sep = "")
    cat("  opaque: ", if (!is.null(x@py)) "TRUE" else "FALSE", "\n", sep = "")
    invisible(x)
  }

  S7::method(print, SkaldIndex) <- function(x, ...) {
    cat("<SkaldIndex>\n")
    cat("  folder: ", x@index_folder, "\n", sep = "")
    cat("  name: ", x@index_name, "\n", sep = "")
    cat("  backend: ", x@backend, "\n", sep = "")
    cat("  loaded: ", if (!is.null(x@py)) "TRUE" else "FALSE", "\n", sep = "")
    invisible(x)
  }

  S7::method(print, SkaldStore) <- function(x, ...) {
    cat("<SkaldStore>\n")
    cat("  location: ", x@location, "\n", sep = "")
    cat("  index: ", file.path(x@index_folder, x@index_name), "\n", sep = "")
    cat("  model: ", .skald_model_label(x@model_spec) %||% "<unknown>", "\n", sep = "")
    cat("  read_only: ", if (isTRUE(x@read_only)) "TRUE" else "FALSE", "\n", sep = "")
    invisible(x)
  }

  S7::method(print, SkaldRetriever) <- function(x, ...) {
    cat("<SkaldRetriever>\n")
    cat("  top_k: ", x@top_k, "\n", sep = "")
    cat("  candidate_k: ", x@candidate_k %||% "<none>", "\n", sep = "")
    cat("  format: ", x@format, "\n", sep = "")
    invisible(x)
  }

  invisible(TRUE)
}
