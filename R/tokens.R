skald_token_relevance <- function(
  model,
  query,
  documents,
  document_id = NULL,
  batch_size = 32,
  show_progress = interactive(),
  scale = c("document", "corpus", "none"),
  include_special = FALSE,
  ...
) {
  .skald_check_model(model)
  scale <- rlang::arg_match(scale)

  query <- as.character(query)
  if (length(query) != 1) {
    cli::cli_abort("{.arg query} must be a single string.")
  }

  documents <- as.character(documents)
  document_id <- document_id %||% seq_along(documents)
  document_id <- as.character(document_id)

  if (length(document_id) != length(documents)) {
    cli::cli_abort("{.arg document_id} must have the same length as {.arg documents}.")
  }
  if (anyDuplicated(document_id)) {
    cli::cli_abort("{.arg document_id} must uniquely identify each document.")
  }

  if (!length(documents)) {
    return(.skald_empty_token_relevance())
  }

  py_model <- .skald_model_py(model)
  bridge <- skald_bridge()

  query_embeddings <- skald_encode_queries(
    model = model,
    queries = query,
    batch_size = batch_size,
    show_progress = show_progress,
    convert_to_numpy = TRUE,
    ...
  )
  document_embeddings <- skald_encode_documents(
    model = model,
    documents = documents,
    batch_size = batch_size,
    show_progress = show_progress,
    convert_to_numpy = TRUE,
    ...
  )

  raw_query_tokens <- bridge$colbert_tokens(py_model, as.list(query), is_query = TRUE)
  raw_document_tokens <- bridge$colbert_tokens(
    py_model,
    as.list(documents),
    is_query = FALSE
  )

  query_tokens <- .skald_token_tbl(
    raw_query_tokens[[1]],
    text = query,
    text_id = "query",
    token_type = "query"
  )
  document_tokens <- lapply(seq_along(documents), function(i) {
    .skald_token_tbl(
      raw_document_tokens[[i]],
      text = documents[[i]],
      text_id = document_id[[i]],
      token_type = "document"
    )
  })

  query_matrix <- .skald_embedding_matrix(.skald_embedding_items(query_embeddings)[[1]])
  document_matrices <- lapply(
    .skald_embedding_items(document_embeddings),
    .skald_embedding_matrix
  )

  out <- .skald_token_relevance_from_matrices(
    query_matrix = query_matrix,
    document_matrices = document_matrices,
    query_tokens = query_tokens,
    document_tokens = document_tokens,
    documents = documents,
    document_id = document_id,
    scale = scale
  )

  if (!isTRUE(include_special)) {
    out <- dplyr::filter(out, !.data$is_special)
    out$score_scaled <- .skald_scale_scores(out, scale)
  }

  out
}

skald_token_highlight <- function(
  relevance,
  color = "#f59f00",
  min_alpha = 0.08,
  max_alpha = 0.72
) {
  .skald_check_installed(
    "htmltools",
    "Install htmltools to render token highlights."
  )

  relevance <- tibble::as_tibble(relevance)
  .skald_check_token_relevance(relevance)

  if (!nrow(relevance)) {
    return(htmltools::HTML(""))
  }

  rgb <- .skald_hex_rgb(color)
  min_alpha <- .skald_alpha(min_alpha, "min_alpha")
  max_alpha <- .skald_alpha(max_alpha, "max_alpha")
  if (min_alpha > max_alpha) {
    cli::cli_abort("{.arg min_alpha} must be less than or equal to {.arg max_alpha}.")
  }

  pieces <- lapply(split(relevance, relevance$document_id), function(document) {
    htmltools::HTML(.skald_highlight_document(document, rgb, min_alpha, max_alpha))
  })

  if (length(pieces) == 1) {
    return(pieces[[1]])
  }

  htmltools::tagList(lapply(names(pieces), function(id) {
    htmltools::tags$div(
      class = "skald-token-highlight",
      `data-document-id` = id,
      pieces[[id]]
    )
  }))
}

.skald_token_tbl <- function(tokens, text, text_id, token_type) {
  tokens <- reticulate::py_to_r(tokens)
  out <- tibble::as_tibble(dplyr::bind_rows(tokens))

  if (!nrow(out)) {
    return(tibble::tibble(
      text_id = character(),
      text = character(),
      token_type = character(),
      token_index = integer(),
      embedding_index = integer(),
      token_id = integer(),
      token = character(),
      token_start = integer(),
      token_end = integer(),
      attention = logical(),
      scored = logical(),
      role = character(),
      is_special = logical(),
      is_expansion = logical()
    ))
  }

  out$embedding_index <- .skald_nullable_integer(out$embedding_index)
  out$token_start <- .skald_offsets_start(out$offset_start)
  out$token_end <- .skald_offsets_end(out$offset_end)
  out$offset_start <- NULL
  out$offset_end <- NULL

  dplyr::mutate(
    out,
    text_id = text_id,
    text = text,
    token_type = token_type,
    .before = 1
  )
}

.skald_token_relevance_from_matrices <- function(
  query_matrix,
  document_matrices,
  query_tokens,
  document_tokens,
  documents,
  document_id,
  scale = "document"
) {
  query_scored <- dplyr::filter(query_tokens, !is.na(.data$embedding_index))
  if (nrow(query_scored) != nrow(query_matrix)) {
    cli::cli_abort("Query token metadata and embeddings must have the same length.")
  }

  out <- lapply(seq_along(document_matrices), function(i) {
    document_matrix <- document_matrices[[i]]
    tokens <- document_tokens[[i]]
    document_scored <- dplyr::filter(tokens, !is.na(.data$embedding_index))

    if (!nrow(document_scored) || !nrow(query_scored)) {
      return(.skald_empty_token_relevance())
    }
    if (nrow(document_scored) != nrow(document_matrix)) {
      cli::cli_abort("Document token metadata and embeddings must have the same length.")
    }

    sim <- query_matrix %*% t(document_matrix)
    doc_best_query_index <- max.col(t(sim), ties.method = "first")
    doc_scores <- apply(sim, 2, max)
    query_best_doc_index <- max.col(sim, ties.method = "first")
    query_scores <- apply(sim, 1, max)

    selected <- split(seq_along(query_best_doc_index), query_best_doc_index)
    selected_tokens <- lapply(seq_along(doc_scores), function(j) {
      query_hits <- selected[[as.character(j)]] %||% integer()
      query_scored$token[query_hits]
    })

    token_scores <- tibble::tibble(
      embedding_index = seq_along(doc_scores),
      score = as.double(doc_scores),
      best_query_embedding_index = as.integer(doc_best_query_index),
      best_query_token = query_scored$token[doc_best_query_index],
      selected_by_query = seq_along(doc_scores) %in% query_best_doc_index,
      selected_query_tokens = selected_tokens,
      document_score = sum(query_scores)
    )

    out <- dplyr::left_join(tokens, token_scores, by = "embedding_index")
    unscored <- is.na(out$selected_by_query)
    out$selected_by_query[unscored] <- FALSE
    out$selected_query_tokens[unscored] <- rep(list(character()), sum(unscored))
    out$document_id <- document_id[[i]]
    out$document <- documents[[i]]
    out
  })

  out <- dplyr::bind_rows(out)
  if (!nrow(out)) {
    return(out)
  }

  out <- dplyr::select(
    out,
    "document_id",
    "document",
    "token_index",
    "embedding_index",
    "token",
    "token_id",
    "token_start",
    "token_end",
    "score",
    "best_query_embedding_index",
    "best_query_token",
    "selected_by_query",
    "selected_query_tokens",
    "document_score",
    "attention",
    "scored",
    "role",
    "is_special",
    "is_expansion"
  )

  out$score_scaled <- .skald_scale_scores(out, scale)
  dplyr::relocate(out, "score_scaled", .after = "score")
}

.skald_scale_scores <- function(x, scale) {
  if (identical(scale, "none")) {
    return(x$score)
  }

  if (identical(scale, "corpus")) {
    return(.skald_rescale01(x$score))
  }

  pieces <- split(seq_len(nrow(x)), x$document_id)
  out <- rep(NA_real_, nrow(x))
  for (idx in pieces) {
    out[idx] <- .skald_rescale01(x$score[idx])
  }
  out
}

.skald_rescale01 <- function(x) {
  out <- rep(NA_real_, length(x))
  ok <- !is.na(x)
  if (!any(ok)) {
    return(out)
  }

  rng <- range(x[ok])
  if (isTRUE(all.equal(rng[[1]], rng[[2]]))) {
    out[ok] <- 1
  } else {
    out[ok] <- (x[ok] - rng[[1]]) / (rng[[2]] - rng[[1]])
  }
  out
}

.skald_empty_token_relevance <- function() {
  tibble::tibble(
    document_id = character(),
    document = character(),
    token_index = integer(),
    embedding_index = integer(),
    token = character(),
    token_id = integer(),
    token_start = integer(),
    token_end = integer(),
    score = numeric(),
    score_scaled = numeric(),
    best_query_embedding_index = integer(),
    best_query_token = character(),
    selected_by_query = logical(),
    selected_query_tokens = list(),
    document_score = numeric(),
    attention = logical(),
    scored = logical(),
    role = character(),
    is_special = logical(),
    is_expansion = logical()
  )
}

.skald_embedding_matrix <- function(x) {
  x <- reticulate::py_to_r(x)
  if (length(dim(x)) != 2) {
    cli::cli_abort("Expected token embeddings to be a two-dimensional matrix.")
  }

  storage.mode(x) <- "double"
  x
}

.skald_nullable_integer <- function(x) {
  out <- suppressWarnings(as.integer(x))
  out[is.na(x)] <- NA_integer_
  out
}

.skald_offsets_start <- function(x) {
  x <- suppressWarnings(as.integer(x))
  ifelse(is.na(x), NA_integer_, x + 1L)
}

.skald_offsets_end <- function(x) {
  suppressWarnings(as.integer(x))
}

.skald_check_token_relevance <- function(x) {
  needed <- c(
    "document_id", "document", "token_start", "token_end",
    "score", "score_scaled", "best_query_token"
  )
  missing <- setdiff(needed, names(x))
  if (length(missing)) {
    cli::cli_abort("{.arg relevance} is missing columns: {.field {missing}}.")
  }

  invisible(TRUE)
}

.skald_highlight_document <- function(document, rgb, min_alpha, max_alpha) {
  text <- document$document[[1]]
  tokens <- dplyr::filter(
    document,
    !is.na(.data$token_start),
    !is.na(.data$token_end),
    !is.na(.data$score_scaled)
  )
  tokens <- dplyr::arrange(tokens, .data$token_start, .data$token_end)

  if (!nrow(tokens)) {
    return(htmltools::htmlEscape(text))
  }

  pos <- 1L
  n <- nchar(text, type = "chars", allowNA = FALSE)
  pieces <- character()

  for (i in seq_len(nrow(tokens))) {
    start <- tokens$token_start[[i]]
    end <- tokens$token_end[[i]]
    if (is.na(start) || is.na(end) || start > n || end < pos) {
      next
    }

    start <- max(start, pos)
    end <- min(end, n)

    if (start > pos) {
      pieces <- c(pieces, htmltools::htmlEscape(substr(text, pos, start - 1L)))
    }

    scaled <- min(max(tokens$score_scaled[[i]], 0), 1)
    alpha <- min_alpha + scaled * (max_alpha - min_alpha)
    style <- sprintf(
      "background-color: rgba(%d, %d, %d, %.3f); border-radius: 3px;",
      rgb[[1]], rgb[[2]], rgb[[3]], alpha
    )
    title <- sprintf(
      "score: %.3f; best query token: %s",
      tokens$score[[i]],
      tokens$best_query_token[[i]] %||% "<unknown>"
    )
    piece <- htmltools::htmlEscape(substr(text, start, end))
    pieces <- c(
      pieces,
      sprintf(
        "<span style=\"%s\" title=\"%s\">%s</span>",
        htmltools::htmlEscape(style, attribute = TRUE),
        htmltools::htmlEscape(title, attribute = TRUE),
        piece
      )
    )
    pos <- end + 1L
  }

  if (pos <= n) {
    pieces <- c(pieces, htmltools::htmlEscape(substr(text, pos, n)))
  }

  paste0(pieces, collapse = "")
}

.skald_hex_rgb <- function(x) {
  if (!is.character(x) || length(x) != 1 || !grepl("^#[0-9A-Fa-f]{6}$", x)) {
    cli::cli_abort("{.arg color} must be a hex color like {.val #f59f00}.")
  }

  as.integer(strtoi(substring(x, c(2, 4, 6), c(3, 5, 7)), base = 16L))
}

.skald_alpha <- function(x, arg) {
  if (!is.numeric(x) || length(x) != 1 || is.na(x) || x < 0 || x > 1) {
    cli::cli_abort("{.arg {arg}} must be a number between 0 and 1.")
  }

  x
}
