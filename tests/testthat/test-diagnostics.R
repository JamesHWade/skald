test_that("Python config values are scalar strings", {
  numpy <- list(
    path = "/tmp/python/site-packages/numpy",
    version = numeric_version("1.26.3")
  )

  expect_equal(
    skald:::.skald_python_config_value(numpy),
    "1.26.3 (/tmp/python/site-packages/numpy)"
  )

  expect_equal(
    skald:::.skald_python_config_value(c("a", "b")),
    "a, b"
  )
})
