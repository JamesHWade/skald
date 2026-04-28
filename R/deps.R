.local <- new.env(parent = emptyenv())
.local$bridge <- NULL

.onLoad <- function(libname, pkgname) {
  .skald_register_print_methods()

  tryCatch(
    reticulate::py_require(
      packages = "pylate>=1.4.0,<1.5",
      python_version = ">=3.10"
    ),
    error = function(e) {
      assign("py_require_error", conditionMessage(e), envir = .local)
    }
  )

  invisible()
}

skald_configure <- function(
  version_spec = ">=1.4.0,<1.5",
  extras = character(),
  python_version = ">=3.10",
  exclude_newer = NULL,
  action = "add"
) {
  action <- rlang::arg_match(action, c("add", "remove", "set"))

  pkg <- if (length(extras)) {
    sprintf("pylate[%s]%s", paste(extras, collapse = ","), version_spec)
  } else {
    sprintf("pylate%s", version_spec)
  }

  reticulate::py_require(
    packages = pkg,
    python_version = python_version,
    exclude_newer = exclude_newer,
    action = action
  )

  invisible(pkg)
}

skald_setup <- function(
  version_spec = ">=1.4.0,<1.5",
  extras = character(),
  python_version = ">=3.10",
  exclude_newer = NULL,
  action = "set",
  check = TRUE
) {
  action <- rlang::arg_match(action, c("add", "remove", "set"))
  python_initialized <- reticulate::py_available(initialize = FALSE)

  pkg <- skald_configure(
    version_spec = version_spec,
    extras = extras,
    python_version = python_version,
    exclude_newer = exclude_newer,
    action = action
  )

  cli::cli_h1("skald setup")
  cli::cli_bullets(c(
    "v" = "Requested Python package {.pkg {pkg}}.",
    "v" = "Requested Python version {.val {python_version}}."
  ))

  if (isTRUE(python_initialized)) {
    cli::cli_warn(c(
      "Python is already initialized in this R session.",
      "i" = "New reticulate requirements may not affect the active Python environment.",
      "i" = "Restart R before calling {.fun skald_setup} if you need reticulate to resolve a different environment."
    ))
  }

  if (!isTRUE(check)) {
    cli::cli_inform(c(
      "i" = "Skipping import checks because {.code check = FALSE}.",
      "i" = "Run {.fun skald_sitrep} to inspect the active environment."
    ))
    return(invisible(pkg))
  }

  diagnostics <- skald_sitrep()
  pylate <- diagnostics$install[diagnostics$install$package == "pylate", , drop = FALSE]

  if (nrow(pylate) && isTRUE(pylate$available[[1]])) {
    cli::cli_bullets(c("v" = "Python package {.pkg pylate} is available."))
  } else {
    cli::cli_warn(c(
      "Python package {.pkg pylate} is not available in the active environment.",
      "i" = "If Python was already initialized, restart R and run {.fun skald_setup} before loading other Python-backed packages.",
      "i" = "Run {.fun skald_sitrep} to inspect the active Python environment."
    ))
  }

  invisible(diagnostics)
}

skald_py_mod <- function(name = NULL) {
  key <- if (is.null(name)) "pylate" else paste0("pylate.", name)

  if (!exists(key, envir = .local, inherits = FALSE)) {
    mod <- tryCatch(
      reticulate::import(key, convert = FALSE),
      error = function(e) {
        cli::cli_abort(c(
          "Could not import Python package {.pkg {key}}.",
          "i" = "Run {.code skald_sitrep()} to inspect the active Python environment.",
          "i" = "Run {.code skald_setup()} in a fresh R session to configure and check requirements.",
          "i" = "For CPU-only PyTorch wheels, set {.env UV_INDEX} before loading skald."
        ), parent = e)
      }
    )

    assign(key, mod, envir = .local)
  }

  get(key, envir = .local, inherits = FALSE)
}

skald_ensure_pylate <- function() {
  skald_py_mod(NULL)
}

skald_bridge <- function() {
  if (is.null(.local$bridge)) {
    bridge_path <- system.file("python", package = "skald")

    .local$bridge <- reticulate::import_from_path(
      "bridge",
      path = bridge_path,
      convert = FALSE
    )
  }

  .local$bridge
}

.skald_python_version <- function(package) {
  tryCatch(
    {
      metadata <- reticulate::import("importlib.metadata", convert = TRUE)
      metadata$version(package)
    },
    error = function(e) NA_character_
  )
}

skald_python_config <- function() {
  cfg <- tryCatch(reticulate::py_config(), error = identity)

  if (inherits(cfg, "error")) {
    return(tibble::tibble(
      field = "error",
      value = conditionMessage(cfg)
    ))
  }

  tibble::tibble(
    field = c("python", "version", "numpy", "required_module", "available"),
    value = c(
      .skald_python_config_value(cfg$python),
      .skald_python_config_value(cfg$version),
      .skald_python_config_value(cfg$numpy),
      .skald_python_config_value(cfg$required_module),
      as.character(isTRUE(cfg$available))
    )
  )
}

.skald_python_config_value <- function(x) {
  if (is.null(x)) {
    return(NA_character_)
  }

  if (inherits(x, c("numeric_version", "package_version"))) {
    return(as.character(x))
  }

  if (is.list(x)) {
    if (!is.null(x$version) && !is.null(x$path)) {
      return(sprintf(
        "%s (%s)",
        .skald_python_config_value(x$version),
        .skald_python_config_value(x$path)
      ))
    }

    parts <- vapply(x, .skald_python_config_value, character(1))
    return(paste(parts, collapse = "; "))
  }

  x <- as.character(x)
  if (length(x) == 0) {
    NA_character_
  } else if (length(x) == 1) {
    x
  } else {
    paste(x, collapse = ", ")
  }
}

skald_torch_devices <- function() {
  torch <- tryCatch(reticulate::import("torch", convert = TRUE), error = identity)

  if (inherits(torch, "error")) {
    return(tibble::tibble(
      device = c("cuda", "mps", "default"),
      available = c(FALSE, FALSE, FALSE),
      detail = c(conditionMessage(torch), conditionMessage(torch), "torch unavailable")
    ))
  }

  cuda_available <- tryCatch(isTRUE(torch$cuda$is_available()), error = function(e) FALSE)
  mps_available <- tryCatch(isTRUE(torch$backends$mps$is_available()), error = function(e) FALSE)
  default <- if (cuda_available) "cuda" else if (mps_available) "mps" else "cpu"

  tibble::tibble(
    device = c("cuda", "mps", "default"),
    available = c(cuda_available, mps_available, TRUE),
    detail = c(
      if (cuda_available) "available" else "unavailable",
      if (mps_available) "available" else "unavailable",
      default
    )
  )
}

skald_check_install <- function() {
  packages <- c("pylate", "torch", "sentence_transformers", "transformers")

  out <- lapply(packages, function(pkg) {
    ok <- TRUE
    err <- NA_character_

    tryCatch(
      reticulate::import(pkg, convert = FALSE),
      error = function(e) {
        ok <<- FALSE
        err <<- conditionMessage(e)
      }
    )

    tibble::tibble(
      package = pkg,
      available = ok,
      version = .skald_python_version(pkg),
      error = err
    )
  })

  dplyr::bind_rows(out)
}

skald_diagnostics <- function() {
  .skald_collect_diagnostics()
}

skald_sitrep <- function() {
  diagnostics <- .skald_collect_diagnostics()
  .skald_print_sitrep(diagnostics)
  invisible(diagnostics)
}

.skald_collect_diagnostics <- function() {
  reqs <- .skald_python_requirements()

  versions <- tibble::tibble(
    field = c(
      "R version",
      "skald version",
      "reticulate version",
      "pylate version",
      "torch version",
      "sentence_transformers version",
      "transformers version",
      "fast-plaid version",
      "active reticulate requirements"
    ),
    value = c(
      paste(R.version$major, R.version$minor, sep = "."),
      as.character(utils::packageVersion("skald")),
      as.character(utils::packageVersion("reticulate")),
      .skald_python_version("pylate"),
      .skald_python_version("torch"),
      .skald_python_version("sentence-transformers"),
      .skald_python_version("transformers"),
      .skald_python_version("fast-plaid"),
      .skald_python_requirements_value(reqs)
    )
  )

  py <- skald_python_config()
  devices <- skald_torch_devices()

  list(
    versions = versions,
    python = py,
    torch_devices = devices,
    install = skald_check_install()
  )
}

.skald_python_requirements <- function() {
  tryCatch(
    reticulate::py_require(),
    error = function(e) structure(
      list(error = conditionMessage(e)),
      class = "skald_python_requirements_error"
    )
  )
}

.skald_python_requirements_value <- function(reqs) {
  if (inherits(reqs, "skald_python_requirements_error")) {
    return(reqs$error %||% NA_character_)
  }

  packages <- reqs$packages %||% character()
  python_version <- reqs$python_version %||% NA_character_
  exclude_newer <- reqs$exclude_newer %||% NA_character_

  parts <- c(
    if (length(packages)) paste(packages, collapse = ", ") else "packages: <none>",
    if (!is.na(python_version)) paste0("python: ", python_version),
    if (!is.na(exclude_newer)) paste0("exclude_newer: ", exclude_newer)
  )

  paste(parts, collapse = "; ")
}

.skald_print_sitrep <- function(diagnostics) {
  cli::cli_h1("skald sitrep")

  cli::cli_h2("R")
  .skald_cli_field(diagnostics$versions, "R version")
  .skald_cli_field(diagnostics$versions, "skald version")
  .skald_cli_field(diagnostics$versions, "reticulate version")

  cli::cli_h2("Python")
  .skald_cli_field(diagnostics$python, "python")
  .skald_cli_field(diagnostics$python, "version")
  .skald_cli_field(diagnostics$python, "numpy")
  .skald_cli_field(diagnostics$versions, "active reticulate requirements")

  cli::cli_h2("Python packages")
  package_lines <- character(nrow(diagnostics$install))
  for (i in seq_len(nrow(diagnostics$install))) {
    row <- diagnostics$install[i, , drop = FALSE]
    status <- if (isTRUE(row$available[[1]])) "v" else "x"
    version <- row$version[[1]]
    error <- row$error[[1]]
    detail <- if (!is.na(version)) {
      version
    } else if (!is.na(error)) {
      .skald_one_line(error)
    } else {
      "not found"
    }

    package_lines[[i]] <- sprintf("{.pkg %s}: %s", row$package[[1]], detail)
    names(package_lines)[[i]] <- status
  }
  cli::cli_bullets(package_lines)

  cli::cli_h2("Devices")
  device_lines <- character(nrow(diagnostics$torch_devices))
  for (i in seq_len(nrow(diagnostics$torch_devices))) {
    row <- diagnostics$torch_devices[i, , drop = FALSE]
    status <- if (isTRUE(row$available[[1]])) "v" else "x"
    device_lines[[i]] <- sprintf("%s: %s", row$device[[1]], row$detail[[1]])
    names(device_lines)[[i]] <- status
  }
  cli::cli_bullets(device_lines)

  invisible(diagnostics)
}

.skald_cli_field <- function(data, field) {
  value <- data$value[data$field == field]
  if (!length(value)) {
    value <- NA_character_
  }

  value <- .skald_one_line(value[[1]])
  cli::cli_bullets(c("*" = "{.field {field}}: {.val {value}}"))
}

.skald_one_line <- function(x) {
  if (is.null(x) || is.na(x)) {
    return("<unknown>")
  }

  gsub("\\s+", " ", as.character(x))
}

skald_index_status <- function(x) {
  if (S7::S7_inherits(x, SkaldStore)) {
    con <- .skald_store_connect_db(x, read_only = TRUE)
    on.exit(.skald_store_disconnect_db(con), add = TRUE)

    stats <- DBI::dbGetQuery(
      con,
      "SELECT COUNT(*) AS n, SUM(CASE WHEN indexed THEN 1 ELSE 0 END) AS indexed, SUM(CASE WHEN deleted THEN 1 ELSE 0 END) AS deleted FROM chunks"
    )

    return(tibble::tibble(
      type = "store",
      location = x@location,
      index_folder = x@index_folder,
      index_name = x@index_name,
      chunks = as.integer(stats$n %||% 0L),
      indexed = as.integer(stats$indexed %||% 0L),
      deleted = as.integer(stats$deleted %||% 0L)
    ))
  }

  if (S7::S7_inherits(x, SkaldIndex)) {
    return(tibble::tibble(
      type = "index",
      location = x@index_folder,
      index_folder = x@index_folder,
      index_name = x@index_name,
      exists = dir.exists(file.path(x@index_folder, x@index_name))
    ))
  }

  cli::cli_abort("{.arg x} must be a {.cls SkaldStore} or {.cls SkaldIndex}.")
}
