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
