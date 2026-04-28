test_that("token relevance scores document tokens by best query token", {
  query_tokens <- tibble::tibble(
    text_id = "query",
    text = "alpha beta",
    token_type = "query",
    token_index = 1:2,
    embedding_index = 1:2,
    token_id = 1:2,
    token = c("alpha", "beta"),
    token_start = c(1L, 7L),
    token_end = c(5L, 10L),
    attention = TRUE,
    scored = TRUE,
    role = "content",
    is_special = FALSE,
    is_expansion = FALSE
  )
  document_tokens <- list(tibble::tibble(
    text_id = "doc-1",
    text = "alpha gamma",
    token_type = "document",
    token_index = 1:2,
    embedding_index = 1:2,
    token_id = 3:4,
    token = c("alpha", "gamma"),
    token_start = c(1L, 7L),
    token_end = c(5L, 11L),
    attention = TRUE,
    scored = TRUE,
    role = "content",
    is_special = FALSE,
    is_expansion = FALSE
  ))

  out <- skald:::.skald_token_relevance_from_matrices(
    query_matrix = matrix(c(1, 0, 0, 1), ncol = 2, byrow = TRUE),
    document_matrices = list(matrix(c(1, 0, 0.5, 0.5), ncol = 2, byrow = TRUE)),
    query_tokens = query_tokens,
    document_tokens = document_tokens,
    documents = "alpha gamma",
    document_id = "doc-1"
  )

  expect_equal(out$token, c("alpha", "gamma"))
  expect_equal(out$score, c(1, 0.5))
  expect_equal(out$score_scaled, c(1, 0))
  expect_equal(out$best_query_token, c("alpha", "alpha"))
  expect_equal(out$selected_by_query, c(TRUE, TRUE))
  expect_equal(out$selected_query_tokens[[1]], "alpha")
  expect_equal(out$selected_query_tokens[[2]], "beta")
  expect_equal(unique(out$document_score), 1.5)
})

test_that("token highlights escape document text and add spans", {
  testthat::skip_if_not_installed("htmltools")

  relevance <- tibble::tibble(
    document_id = "doc-1",
    document = "alpha <beta>",
    token_start = c(1L, 7L),
    token_end = c(5L, 12L),
    score = c(1, 0),
    score_scaled = c(1, 0),
    best_query_token = c("alpha", "beta")
  )

  html <- as.character(skald_token_highlight(relevance))

  expect_match(html, "<span", fixed = TRUE)
  expect_match(html, "alpha", fixed = TRUE)
  expect_match(html, "&lt;beta&gt;", fixed = TRUE)
})

test_that("token relevance requires unique document ids", {
  model <- skald:::new_skald_model(py = NULL, model_name_or_path = "mock")

  expect_error(
    skald_token_relevance(
      model,
      query = "alpha",
      documents = c("alpha", "beta"),
      document_id = c("doc", "doc")
    ),
    "document_id"
  )
})
