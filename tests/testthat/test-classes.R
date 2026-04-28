test_that("S7 print methods are concise", {
  model <- skald:::new_skald_model(py = NULL, model_name_or_path = "mock", device = "cpu")

  out <- capture.output(print(model))

  expect_match(out[[1]], "<SkaldModel>", fixed = TRUE)
  expect_true(any(grepl("model: mock", out, fixed = TRUE)))
  expect_true(any(grepl("loaded: FALSE", out, fixed = TRUE)))
})
