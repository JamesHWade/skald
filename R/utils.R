`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

utils::globalVariables(c(".data", "chunk_uid", "embedding_text"))

`%nin%` <- function(x, table) {
  !x %in% table
}

.skald_now <- function() {
  Sys.time()
}

.skald_hash <- function(x) {
  as.character(openssl::sha1(enc2utf8(paste0(x, collapse = "\r\n"))))
}

.skald_short_hash <- function(x, n = 8) {
  substr(.skald_hash(x), 1, n)
}

.skald_check_installed <- function(pkg, reason = NULL) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    msg <- c(
      sprintf("Package {.pkg %s} is required.", pkg),
      if (!is.null(reason)) c("i" = reason)
    )
    cli::cli_abort(msg)
  }

  invisible(TRUE)
}

.skald_check_model <- function(model) {
  if (!S7::S7_inherits(model, SkaldModel)) {
    cli::cli_abort("{.arg model} must be a {.cls SkaldModel}.")
  }

  invisible(model)
}

.skald_check_index <- function(index) {
  if (!S7::S7_inherits(index, SkaldIndex)) {
    cli::cli_abort("{.arg index} must be a {.cls SkaldIndex}.")
  }

  invisible(index)
}

.skald_check_store <- function(store) {
  if (!S7::S7_inherits(store, SkaldStore)) {
    cli::cli_abort("{.arg store} must be a {.cls SkaldStore}.")
  }

  invisible(store)
}

.skald_as_tibble <- function(x) {
  if (inherits(x, "data.frame")) {
    tibble::as_tibble(x)
  } else if (is.character(x)) {
    tibble::tibble(text = x)
  } else {
    cli::cli_abort("{.arg x} must be a data frame or character vector.")
  }
}

.skald_unique_non_missing <- function(x, what = "value") {
  x <- x[!is.na(x)]
  ux <- unique(x)

  if (length(ux) != 1) {
    cli::cli_abort("{.arg {what}} must resolve to exactly one non-missing value per group.")
  }

  ux[[1]]
}

.skald_eval_select <- function(expr, data, arg, allow_empty = FALSE) {
  expr <- rlang::enquo(expr)

  if (rlang::quo_is_null(expr)) {
    if (allow_empty) {
      return(integer())
    }
    cli::cli_abort("{.arg {arg}} must select at least one column.")
  }

  tidyselect::eval_select(expr, data)
}

.skald_eval_select_one <- function(expr, data, arg) {
  loc <- .skald_eval_select({{ expr }}, data, arg)

  if (length(loc) != 1) {
    cli::cli_abort("{.arg {arg}} must select exactly one column.")
  }

  names(loc)
}

.skald_column_exists_abort <- function(data, col, arg) {
  vctrs::vec_as_names(names(data), repair = "check_unique")

  if (col %in% names(data)) {
    cli::cli_abort(c(
      "Column {.field {col}} already exists.",
      "i" = "Set {.arg {arg}} to a different name."
    ))
  }
}

.skald_template_text <- function(text, context = NULL, text_template = "{context}\n\n{text}") {
  text <- as.character(text)
  context <- context %||% rep(NA_character_, length(text))
  context <- as.character(context)

  mapply(
    FUN = function(txt, ctx) {
      if (is.na(ctx) || !nzchar(trimws(ctx))) {
        txt
      } else {
        as.character(glue::glue_data(list(context = ctx, text = txt), text_template))
      }
    },
    txt = text,
    ctx = context,
    USE.NAMES = FALSE
  )
}

.skald_as_json <- function(x, auto_unbox = TRUE) {
  jsonlite::toJSON(x, auto_unbox = auto_unbox, null = "null", dataframe = "rows")
}

.skald_from_json <- function(x) {
  if (is.na(x) || !nzchar(x)) {
    return(NULL)
  }

  jsonlite::fromJSON(x, simplifyVector = FALSE)
}

.skald_py_to_r <- function(x) {
  reticulate::py_to_r(x)
}

.skald_py_scalar_chr <- function(x) {
  as.character(reticulate::py_to_r(x))
}

.skald_py_scalar_dbl <- function(x) {
  as.double(reticulate::py_to_r(x))
}

.skald_py_list <- function(x) {
  reticulate::r_to_py(x, convert = FALSE)
}

.skald_model_spec <- function(model) {
  if (S7::S7_inherits(model, SkaldModel)) {
    list(
      model_name_or_path = model@model_name_or_path,
      backend = model@backend,
      device = model@device,
      query_length = model@query_length,
      document_length = model@document_length,
      query_prefix = model@query_prefix,
      document_prefix = model@document_prefix,
      trust_remote_code = model@trust_remote_code,
      revision = model@revision,
      local_files_only = model@local_files_only,
      metadata = model@metadata
    )
  } else {
    model
  }
}

.skald_model_label <- function(model) {
  if (S7::S7_inherits(model, SkaldModel)) {
    model@model_name_or_path
  } else if (is.list(model) && !is.null(model$model_name_or_path)) {
    model$model_name_or_path
  } else {
    NA_character_
  }
}

.skald_restore_model <- function(spec) {
  if (S7::S7_inherits(spec, SkaldModel)) {
    return(spec)
  }

  if (!is.list(spec) || is.null(spec$model_name_or_path)) {
    cli::cli_abort("A {.cls SkaldModel} or model specification is required.")
  }

  new_skald_model(
    py = NULL,
    model_name_or_path = spec$model_name_or_path,
    backend = spec$backend %||% "pylate",
    device = spec$device,
    query_length = spec$query_length,
    document_length = spec$document_length,
    query_prefix = spec$query_prefix,
    document_prefix = spec$document_prefix,
    trust_remote_code = isTRUE(spec$trust_remote_code),
    revision = spec$revision,
    local_files_only = isTRUE(spec$local_files_only),
    metadata = spec$metadata %||% list()
  )
}

.skald_group_split <- function(data) {
  group_vars <- dplyr::group_vars(data)

  if (!length(group_vars)) {
    return(list(tibble::as_tibble(data)))
  }

  dplyr::group_split(data, .keep = TRUE)
}

.skald_group_keys <- function(data) {
  group_vars <- dplyr::group_vars(data)

  if (!length(group_vars)) {
    return(tibble::tibble(.skald_group = 1L))
  }

  dplyr::group_keys(data)
}

.skald_as_string_id <- function(x) {
  if (is.list(x)) {
    vapply(x, function(item) paste(unlist(item), collapse = "::"), character(1))
  } else {
    as.character(x)
  }
}

.skald_compact <- function(x) {
  x[!vapply(x, is.null, logical(1))]
}
