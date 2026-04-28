test_that("skald_fuse_ranks combines score and distance signals", {
  hits <- tibble::tibble(
    doc_id = 1:3,
    bm25 = c(3, 2, 1),
    cosine_distance = c(0.2, 0.1, 0.3),
    late_score = c(5, 8, 1)
  )

  out <- skald_fuse_ranks(hits, bm25, cosine_distance, late_score)

  expect_named(out, c("doc_id", "bm25", "cosine_distance", "late_score", "fused_score", "fused_rank"))
  expect_equal(sort(out$fused_rank), 1:3)
  expect_true(all(diff(out$fused_score) <= 0))
})
