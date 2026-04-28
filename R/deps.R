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

skald_py_mod <- function(name = NULL) {
  key <- if (is.null(name)) "pylate" else paste0("pylate.", name)

  if (!exists(key, envir = .local, inherits = FALSE)) {
    mod <- tryCatch(
      reticulate::import(key, convert = FALSE),
      error = function(e) {
        cli::cli_abort(c(
          "Could not import Python package {.pkg {key}}.",
          "i" = "Run {.code skald_diagnostics()} to inspect the active Python environment.",
          "i" = "Run {.code skald_configure()} before Python is initialized to change requirements.",
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
      cfg$python %||% NA_character_,
      cfg$version %||% NA_character_,
      cfg$numpy %||% NA_character_,
      cfg$required_module %||% NA_character_,
      as.character(isTRUE(cfg$available))
    )
  )
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
  reqs <- tryCatch(
    utils::capture.output(reticulate::py_require()),
    error = function(e) conditionMessage(e)
  )

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
      paste(reqs, collapse = "\n")
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
