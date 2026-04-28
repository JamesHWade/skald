.skald_store_schema <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS skald_metadata (
      key TEXT PRIMARY KEY,
      value_json TEXT,
      value_blob BLOB
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS documents (
      document_uid TEXT PRIMARY KEY,
      origin TEXT,
      hash TEXT,
      text TEXT,
      inserted_at TIMESTAMP,
      updated_at TIMESTAMP
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS chunks (
      chunk_uid TEXT PRIMARY KEY,
      document_uid TEXT,
      origin TEXT,
      doc_id TEXT,
      chunk_id INTEGER,
      start INTEGER,
      \"end\" INTEGER,
      hash TEXT,
      context TEXT,
      text TEXT,
      embedding_text TEXT,
      indexed BOOLEAN,
      indexed_at TIMESTAMP,
      deleted BOOLEAN DEFAULT FALSE,
      deleted_at TIMESTAMP,
      model_id TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS index_events (
      event_id TEXT PRIMARY KEY,
      chunk_uid TEXT,
      action TEXT,
      status TEXT,
      created_at TIMESTAMP,
      completed_at TIMESTAMP,
      error TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS chunk_metadata (
      chunk_uid TEXT,
      key TEXT,
      value_json TEXT,
      PRIMARY KEY (chunk_uid, key)
    )
  ")

  invisible(TRUE)
}

.skald_store_connect_db <- function(store, read_only = store@read_only) {
  DBI::dbConnect(duckdb::duckdb(dbdir = store@metadata_db, read_only = isTRUE(read_only)))
}

.skald_store_disconnect_db <- function(con) {
  DBI::dbDisconnect(con, shutdown = TRUE)
}

skald_store_create <- function(
  location = "docs.skald",
  model,
  overwrite = FALSE,
  extra_cols = NULL,
  name = NULL,
  title = NULL,
  index_name = "colbert",
  text_template = "{context}\n\n{text}",
  ...
) {
  if (dir.exists(location) && !isTRUE(overwrite)) {
    cli::cli_abort(c(
      "Store location {.path {location}} already exists.",
      "i" = "Use {.code overwrite = TRUE} to replace it."
    ))
  }

  if (dir.exists(location) && isTRUE(overwrite)) {
    unlink(location, recursive = TRUE, force = TRUE)
  }

  fs::dir_create(location)
  index_folder <- file.path(location, "plaid")
  fs::dir_create(index_folder)

  store <- new_skald_store(
    location = location,
    metadata_db = file.path(location, "metadata.duckdb"),
    index_folder = index_folder,
    index_name = index_name,
    model_spec = .skald_model_spec(model),
    read_only = FALSE,
    name = name,
    title = title,
    text_template = text_template
  )

  con <- .skald_store_connect_db(store, read_only = FALSE)
  on.exit(.skald_store_disconnect_db(con), add = TRUE)
  .skald_store_schema(con)

  manifest <- list(
    schema_version = 1L,
    package = "skald",
    backend = "pylate",
    index_backend = "plaid",
    index_name = index_name,
    model = .skald_model_spec(model),
    text_template = text_template,
    name = name,
    title = title
  )

  jsonlite::write_json(
    manifest,
    file.path(location, "manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )

  store
}

skald_store_connect <- function(location, model = NULL, read_only = TRUE) {
  manifest_path <- file.path(location, "manifest.json")

  if (!file.exists(manifest_path)) {
    cli::cli_abort("No skald manifest found at {.path {manifest_path}}.")
  }

  manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)

  new_skald_store(
    location = location,
    metadata_db = file.path(location, "metadata.duckdb"),
    index_folder = file.path(location, "plaid"),
    index_name = manifest$index_name %||% "colbert",
    model_spec = if (!is.null(model)) .skald_model_spec(model) else manifest$model,
    backend = manifest$backend %||% "pylate",
    read_only = read_only,
    name = manifest$name,
    title = manifest$title,
    text_template = manifest$text_template %||% "{context}\n\n{text}"
  )
}

skald_store_insert <- function(
  store,
  chunks,
  ...,
  text = text,
  context = context,
  origin = origin,
  batch = TRUE
) {
  .skald_check_store(store)

  if (isTRUE(store@read_only)) {
    cli::cli_abort("Cannot insert into a read-only {.cls SkaldStore}.")
  }

  normalized <- .skald_normalize_chunks(
    chunks = chunks,
    text_quo = rlang::enquo(text),
    context_quo = rlang::enquo(context),
    origin_quo = rlang::enquo(origin),
    text_template = store@text_template,
    model_id = .skald_model_label(store@model_spec)
  )

  con <- .skald_store_connect_db(store, read_only = FALSE)
  on.exit(.skald_store_disconnect_db(con), add = TRUE)
  .skald_store_schema(con)

  .skald_store_replace_rows(con, normalized$chunks, normalized$documents, normalized$metadata)

  invisible(store)
}

.skald_normalize_chunks <- function(chunks, text_quo, context_quo, origin_quo, text_template, model_id) {
  raw_chunks <- chunks
  data <- .skald_as_tibble(chunks)

  text_col <- .skald_select_optional(text_quo, data)
  if (is.null(text_col)) {
    char_cols <- names(data)[vapply(data, is.character, logical(1))]
    if (!length(char_cols)) {
      cli::cli_abort("Could not identify a text column in {.arg chunks}.")
    }
    text_col <- char_cols[[1]]
  }

  context_col <- .skald_select_optional(context_quo, data)
  origin_col <- .skald_select_optional(origin_quo, data)

  text <- as.character(data[[text_col]])
  context <- if (!is.null(context_col)) as.character(data[[context_col]]) else rep(NA_character_, nrow(data))
  origin <- if (!is.null(origin_col)) {
    as.character(data[[origin_col]])
  } else {
    rep(.skald_extract_ragnar_origin(raw_chunks) %||% NA_character_, nrow(data))
  }

  start <- if ("start" %in% names(data)) as.integer(data$start) else rep(NA_integer_, nrow(data))
  end <- if ("end" %in% names(data)) as.integer(data$end) else rep(NA_integer_, nrow(data))
  doc_id <- if ("doc_id" %in% names(data)) as.character(data$doc_id) else rep(NA_character_, nrow(data))
  chunk_id <- if ("chunk_id" %in% names(data)) as.integer(data$chunk_id) else seq_len(nrow(data))

  document_uid <- ifelse(
    !is.na(origin) & nzchar(origin),
    paste0("d-", vapply(origin, .skald_short_hash, character(1), n = 16)),
    paste0("d-", vapply(text, .skald_short_hash, character(1), n = 16))
  )

  chunk_uid <- if ("chunk_uid" %in% names(data)) {
    as.character(data$chunk_uid)
  } else if (all(!is.na(origin)) && all(!is.na(start)) && all(!is.na(end))) {
    paste(vapply(origin, .skald_short_hash, character(1), n = 8), start, end, sep = "::")
  } else {
    paste0("c-", vapply(text, .skald_short_hash, character(1), n = 16))
  }

  hash <- vapply(text, .skald_short_hash, character(1), n = 40)
  now <- .skald_now()

  chunks_tbl <- tibble::tibble(
    chunk_uid = chunk_uid,
    document_uid = document_uid,
    origin = origin,
    doc_id = doc_id,
    chunk_id = chunk_id,
    start = start,
    end = end,
    hash = hash,
    context = context,
    text = text,
    embedding_text = .skald_template_text(text, context, text_template),
    indexed = FALSE,
    indexed_at = as.POSIXct(NA),
    deleted = FALSE,
    deleted_at = as.POSIXct(NA),
    model_id = model_id
  )

  documents_tbl <- tibble::tibble(
    document_uid = document_uid,
    origin = origin,
    hash = vapply(paste(origin, document_uid), .skald_short_hash, character(1), n = 40),
    text = NA_character_,
    inserted_at = now,
    updated_at = now
  )
  documents_tbl <- dplyr::distinct(documents_tbl, .data$document_uid, .keep_all = TRUE)

  known <- c(
    "chunk_uid", "document_uid", "origin", "doc_id", "chunk_id", "start", "end",
    "hash", "context", "text", "embedding_text", "indexed", "indexed_at",
    "deleted", "deleted_at", "model_id", text_col, context_col, origin_col
  )
  extra_cols <- setdiff(names(data), unique(stats::na.omit(known)))

  metadata_tbl <- .skald_chunk_metadata(data, chunk_uid, extra_cols)

  list(chunks = chunks_tbl, documents = documents_tbl, metadata = metadata_tbl)
}

.skald_select_optional <- function(quo, data) {
  if (rlang::quo_is_null(quo) || rlang::quo_is_missing(quo)) {
    return(NULL)
  }

  tryCatch(
    {
      cols <- names(tidyselect::eval_select(quo, data))
      if (length(cols)) cols[[1]] else NULL
    },
    error = function(e) NULL
  )
}

.skald_extract_ragnar_origin <- function(chunks) {
  tryCatch({
    doc <- chunks@document
    path <- tryCatch(doc@path, error = function(e) NULL)
    url <- tryCatch(doc@url, error = function(e) NULL)
    path %||% url
  }, error = function(e) NULL)
}

.skald_chunk_metadata <- function(data, chunk_uid, extra_cols) {
  if (!length(extra_cols)) {
    return(tibble::tibble(chunk_uid = character(), key = character(), value_json = character()))
  }

  rows <- lapply(extra_cols, function(col) {
    tibble::tibble(
      chunk_uid = chunk_uid,
      key = col,
      value_json = vapply(data[[col]], .skald_as_json, character(1), auto_unbox = TRUE)
    )
  })

  dplyr::bind_rows(rows)
}

.skald_store_replace_rows <- function(con, chunks, documents, metadata) {
  for (id in chunks$chunk_uid) {
    DBI::dbExecute(con, "DELETE FROM chunks WHERE chunk_uid = ?", params = list(id))
    DBI::dbExecute(con, "DELETE FROM chunk_metadata WHERE chunk_uid = ?", params = list(id))
  }

  for (id in documents$document_uid) {
    DBI::dbExecute(con, "DELETE FROM documents WHERE document_uid = ?", params = list(id))
  }

  DBI::dbAppendTable(con, "documents", documents)
  DBI::dbAppendTable(con, "chunks", chunks)

  if (nrow(metadata)) {
    DBI::dbAppendTable(con, "chunk_metadata", metadata)
  }

  invisible(TRUE)
}

skald_store_build_index <- function(store, batch_size = 32, force = FALSE, ...) {
  .skald_check_store(store)

  if (isTRUE(store@read_only)) {
    cli::cli_abort("Cannot build an index for a read-only {.cls SkaldStore}.")
  }

  con <- .skald_store_connect_db(store, read_only = FALSE)
  on.exit(.skald_store_disconnect_db(con), add = TRUE)

  sql <- if (isTRUE(force)) {
    "SELECT * FROM chunks WHERE deleted = FALSE"
  } else {
    "SELECT * FROM chunks WHERE deleted = FALSE AND indexed = FALSE"
  }
  pending <- tibble::as_tibble(DBI::dbGetQuery(con, sql))

  if (!nrow(pending)) {
    return(invisible(store))
  }

  model <- .skald_restore_model(store@model_spec)
  index <- skald_index_create(
    index_folder = store@index_folder,
    index_name = store@index_name,
    overwrite = isTRUE(force)
  )

  index <- skald_index_add(
    index,
    model,
    pending,
    id = chunk_uid,
    text = embedding_text,
    batch_size = batch_size,
    text_template = "{text}",
    ...
  )

  now <- .skald_now()
  for (id in pending$chunk_uid) {
    DBI::dbExecute(
      con,
      "UPDATE chunks SET indexed = TRUE, indexed_at = ? WHERE chunk_uid = ?",
      params = list(now, id)
    )
  }

  invisible(store)
}

skald_retrieve <- function(
  store,
  query,
  top_k = 5,
  ...,
  filter,
  deoverlap = TRUE,
  include_text = TRUE
) {
  .skald_check_store(store)

  filter_quo <- rlang::enquo(filter)
  subset <- NULL

  if (!rlang::quo_is_missing(filter_quo)) {
    subset <- .skald_store_filter_uids(store, filter_quo)
  }

  model <- .skald_restore_model(store@model_spec)
  index <- skald_index_create(
    index_folder = store@index_folder,
    index_name = store@index_name,
    overwrite = FALSE
  )

  out <- skald_index_retrieve(
    index,
    model,
    query = query,
    top_k = top_k,
    subset = subset,
    include_text = FALSE,
    ...
  )

  chunks <- .skald_store_fetch_chunks(store, include_deleted = FALSE)
  names(out)[names(out) == "id"] <- "chunk_uid"
  out <- dplyr::left_join(out, chunks, by = "chunk_uid")

  if (!isTRUE(include_text)) {
    out <- dplyr::select(out, -dplyr::any_of(c("context", "text", "embedding_text")))
  }

  out
}

.skald_store_filter_uids <- function(store, filter_quo) {
  chunks <- .skald_store_fetch_chunks(store, include_deleted = FALSE)
  filtered <- dplyr::filter(chunks, !!filter_quo)
  as.character(filtered$chunk_uid)
}

.skald_store_fetch_chunks <- function(store, include_deleted = FALSE) {
  con <- .skald_store_connect_db(store, read_only = TRUE)
  on.exit(.skald_store_disconnect_db(con), add = TRUE)

  sql <- if (isTRUE(include_deleted)) {
    "SELECT * FROM chunks"
  } else {
    "SELECT * FROM chunks WHERE deleted = FALSE"
  }

  chunks <- tibble::as_tibble(DBI::dbGetQuery(con, sql))
  metadata <- tibble::as_tibble(DBI::dbGetQuery(con, "SELECT * FROM chunk_metadata"))

  if (!nrow(metadata)) {
    return(chunks)
  }

  metadata$value <- lapply(metadata$value_json, .skald_from_json)
  wide <- tidyr::pivot_wider(
    metadata,
    id_cols = "chunk_uid",
    names_from = "key",
    values_from = "value"
  )

  dplyr::left_join(chunks, wide, by = "chunk_uid")
}

skald_store_update <- function(store, chunks, ...) {
  skald_store_insert(store, chunks, ...)
}

skald_store_remove <- function(store, filter) {
  .skald_check_store(store)

  if (isTRUE(store@read_only)) {
    cli::cli_abort("Cannot remove from a read-only {.cls SkaldStore}.")
  }

  filter_quo <- rlang::enquo(filter)
  if (rlang::quo_is_missing(filter_quo)) {
    cli::cli_abort("{.arg filter} is required.")
  }

  ids <- .skald_store_filter_uids(store, filter_quo)
  con <- .skald_store_connect_db(store, read_only = FALSE)
  on.exit(.skald_store_disconnect_db(con), add = TRUE)

  now <- .skald_now()
  for (id in ids) {
    DBI::dbExecute(
      con,
      "UPDATE chunks SET deleted = TRUE, deleted_at = ? WHERE chunk_uid = ?",
      params = list(now, id)
    )
  }

  invisible(store)
}
