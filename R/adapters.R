skald_retriever <- function(
  store,
  model = NULL,
  top_k = 5,
  candidate_k = NULL,
  format = c("tibble", "markdown", "context"),
  ...
) {
  format <- rlang::arg_match(format)
  config <- new_skald_retriever_config(
    store = store,
    model = model,
    top_k = as.integer(top_k),
    candidate_k = candidate_k,
    format = format,
    metadata = list(extra_args = list(...))
  )

  force(store)
  force(model)
  force(top_k)
  force(candidate_k)
  force(format)

  fn <- function(query) {
    results <- if (S7::S7_inherits(store, SkaldStore)) {
      skald_retrieve(store, query = query, top_k = top_k, ...)
    } else {
      if (is.null(model)) {
        cli::cli_abort("{.arg model} is required when retrieving from a RagnarStore.")
      }

      skald_retrieve_ragnar(
        store,
        model = model,
        query = query,
        top_k = top_k,
        candidate_k = candidate_k %||% max(30, top_k * 10),
        ...
      )
    }

    .skald_format_results(results, format)
  }

  attr(fn, "skald_retriever") <- config
  fn
}

skald_as_dsprrr_module <- function(retriever, signature = "question -> context", ...) {
  .skald_check_installed("dsprrr", "Install dsprrr to create dsprrr modules.")

  dsprrr::rag_module(
    signature = signature,
    retriever = retriever,
    ...
  )
}

skald_register_tool_retrieve <- function(
  chat,
  store,
  model = NULL,
  top_k = 8,
  candidate_k = 50,
  store_description = "the late-interaction knowledge store",
  name = NULL,
  title = NULL
) {
  .skald_check_installed("ellmer", "Install ellmer to register retrieval tools.")

  tool_name <- name %||% "skald_retrieve"
  tool_title <- title %||% "Retrieve relevant context"

  retrieve_fun <- function(query) {
    results <- if (S7::S7_inherits(store, SkaldStore)) {
      skald_retrieve(store, query = query, top_k = top_k)
    } else {
      if (is.null(model)) {
        cli::cli_abort("{.arg model} is required when registering a RagnarStore retrieval tool.")
      }

      skald_retrieve_ragnar(
        store,
        model = model,
        query = query,
        top_k = top_k,
        candidate_k = candidate_k
      )
    }

    .skald_format_results(results, "context")
  }

  tool <- ellmer::tool(
    retrieve_fun,
    name = tool_name,
    description = paste0(tool_title, " from ", store_description, "."),
    arguments = list(
      query = ellmer::type_string("The search query to retrieve relevant context for.")
    )
  )

  if (is.null(chat$register_tool) || !is.function(chat$register_tool)) {
    cli::cli_abort("{.arg chat} must be an ellmer chat object with a {.code register_tool()} method.")
  }

  chat$register_tool(tool)
  invisible(tool)
}

.skald_format_results <- function(results, format) {
  if (identical(format, "tibble")) {
    return(results)
  }

  if (!nrow(results)) {
    return("")
  }

  text <- if ("text" %in% names(results)) as.character(results$text) else rep("", nrow(results))
  context <- if ("context" %in% names(results)) as.character(results$context) else rep("", nrow(results))
  origin <- if ("origin" %in% names(results)) as.character(results$origin) else rep("", nrow(results))

  chunks <- mapply(
    function(i, ctx, txt, org) {
      header <- if (nzchar(ctx) && !is.na(ctx)) paste0("## ", ctx, "\n\n") else ""
      source <- if (nzchar(org) && !is.na(org)) paste0("\n\nSource: ", org) else ""
      paste0("[", i, "]\n", header, txt, source)
    },
    i = seq_len(nrow(results)),
    ctx = context,
    txt = text,
    org = origin,
    USE.NAMES = FALSE
  )

  paste(chunks, collapse = "\n\n")
}
