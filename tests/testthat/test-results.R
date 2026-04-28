test_that("skald_results_to_tibble flattens PyLate-shaped results", {
  results <- list(
    list(list(id = "d1", score = 2), list(id = "d2", score = 1)),
    list(list(id = "d3", score = 4))
  )

  out <- skald:::skald_results_to_tibble(results, query_id = c("q1", "q2"), query = c("one", "two"))

  expect_equal(out$query_id, c("q1", "q1", "q2"))
  expect_equal(out$rank, c(1L, 2L, 1L))
  expect_equal(out$id, c("d1", "d2", "d3"))
  expect_equal(out$late_score, c(2, 1, 4))
  expect_equal(out$metric_name, rep("maxsim", 3))
})
