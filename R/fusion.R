skald_fuse_ranks <- function(
  .data,
  ...,
  method = c("rrf", "weighted_sum"),
  k = 60,
  weights = NULL,
  rank_col = "fused_rank",
  score_col = "fused_score"
) {
  method <- rlang::arg_match(method)
  data <- tibble::as_tibble(.data)
  dots <- rlang::enquos(...)
  cols <- names(tidyselect::eval_select(rlang::expr(c(!!!dots)), data))

  if (!length(cols)) {
    cli::cli_abort("At least one rank or score column must be selected.")
  }

  .skald_column_exists_abort(data, rank_col, "rank_col")
  .skald_column_exists_abort(data, score_col, "score_col")

  weights <- weights %||% rep(1, length(cols))
  if (length(weights) != length(cols)) {
    cli::cli_abort("{.arg weights} must have the same length as selected columns.")
  }

  ranks <- lapply(cols, function(col) .skald_signal_rank(data[[col]], col))
  ranks <- as.data.frame(ranks)

  if (identical(method, "rrf")) {
    fused <- Reduce(`+`, Map(function(rank, weight) weight * (1 / (k + rank)), ranks, weights))
  } else {
    scores <- lapply(cols, function(col) .skald_signal_score(data[[col]], col))
    fused <- Reduce(`+`, Map(function(score, weight) weight * score, scores, weights))
  }

  data[[score_col]] <- as.numeric(fused)
  data <- dplyr::arrange(data, dplyr::desc(.data[[score_col]]))
  data[[rank_col]] <- seq_len(nrow(data))
  data
}

.skald_signal_rank <- function(x, name) {
  lower_better <- grepl("distance|dist|rank", name, ignore.case = TRUE)
  if (lower_better) {
    rank(x, ties.method = "first", na.last = "keep")
  } else {
    rank(-x, ties.method = "first", na.last = "keep")
  }
}

.skald_signal_score <- function(x, name) {
  lower_better <- grepl("distance|dist|rank", name, ignore.case = TRUE)
  if (lower_better) {
    x <- -x
  }

  rng <- range(x, na.rm = TRUE)
  if (!is.finite(rng[[1]]) || identical(rng[[1]], rng[[2]])) {
    return(rep(0, length(x)))
  }

  (x - rng[[1]]) / (rng[[2]] - rng[[1]])
}
