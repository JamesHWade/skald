skald_results_to_tibble <- function(results, query_id, query) {
  converted <- reticulate::py_to_r(results)

  rows <- lapply(seq_along(converted), function(i) {
    items <- converted[[i]]

    if (!length(items)) {
      return(tibble::tibble(
        query_id = character(),
        query = character(),
        rank = integer(),
        id = character(),
        late_score = double(),
        metric_name = character(),
        metric_value = double()
      ))
    }

    ids <- vapply(items, function(x) as.character(x$id %||% x[["id"]]), character(1))
    scores <- vapply(items, function(x) as.double(x$score %||% x[["score"]]), numeric(1))

    tibble::tibble(
      query_id = as.character(query_id[[i]]),
      query = as.character(query[[i]]),
      rank = seq_along(ids),
      id = ids,
      late_score = scores,
      metric_name = "maxsim",
      metric_value = scores
    )
  })

  dplyr::bind_rows(rows)
}

.skald_read_index_metadata <- function(index) {
  if (is.null(index@metadata_path) || !file.exists(index@metadata_path)) {
    return(tibble::tibble(id = character()))
  }

  rows <- jsonlite::fromJSON(index@metadata_path, simplifyDataFrame = TRUE)
  tibble::as_tibble(rows)
}

.skald_write_index_metadata <- function(index, data) {
  if (is.null(index@metadata_path)) {
    return(invisible(index))
  }

  fs::dir_create(dirname(index@metadata_path))

  existing <- .skald_read_index_metadata(index)
  combined <- dplyr::bind_rows(existing, data)
  combined <- dplyr::distinct(combined, .data$id, .keep_all = TRUE)

  jsonlite::write_json(
    combined,
    path = index@metadata_path,
    dataframe = "rows",
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )

  invisible(index)
}

.skald_join_index_metadata <- function(out, index) {
  metadata <- .skald_read_index_metadata(index)

  if (!nrow(metadata) || !"id" %in% names(metadata)) {
    return(out)
  }

  dplyr::left_join(out, metadata, by = "id")
}
