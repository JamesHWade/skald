test_that("skald_rerank preserves rows and sorts by late score", {
  model <- skald:::new_skald_model(
    py = NULL,
    model_name_or_path = "mock",
    metadata = list(
      score_fun = function(query, documents, ids) c(1, 3, 3)
    )
  )

  candidates <- tibble::tibble(
    doc_id = 1:3,
    text = c("alpha", "beta", "gamma")
  )

  out <- skald_rerank(candidates, model, query = "letters", text = text, id = doc_id)

  expect_equal(out$doc_id, c(2L, 3L, 1L))
  expect_equal(out$late_score, c(3, 3, 1))
  expect_equal(out$late_rank, 1:3)
  expect_named(out, c("doc_id", "text", "late_score", "late_rank"))
})

test_that("skald_rerank reranks grouped data independently", {
  model <- skald:::new_skald_model(
    py = NULL,
    model_name_or_path = "mock",
    metadata = list(
      score_fun = function(query, documents, ids) seq_along(documents)
    )
  )

  candidates <- tibble::tibble(
    query_id = c("a", "a", "b", "b"),
    query = c("qa", "qa", "qb", "qb"),
    doc_id = c(1, 2, 1, 2),
    text = c("a1", "a2", "b1", "b2")
  )

  out <- candidates |>
    dplyr::group_by(query_id) |>
    skald_rerank(
      model,
      query = query,
      text = text,
      id = doc_id,
      top_k = 1
    )

  expect_equal(out$query_id, c("a", "b"))
  expect_equal(out$doc_id, c(2, 2))
  expect_equal(out$late_rank, c(1L, 1L))
})

test_that("skald_rerank reports score column conflicts", {
  model <- skald:::new_skald_model(
    py = NULL,
    model_name_or_path = "mock",
    metadata = list(score_fun = function(query, documents, ids) 1)
  )

  candidates <- tibble::tibble(text = "alpha", late_score = 1)

  expect_snapshot(error = TRUE, {
    skald_rerank(candidates, model, query = "q", text = text)
  })
})
