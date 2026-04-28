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

test_that("Python requirements are formatted without printing", {
  reqs <- list(
    python_version = ">=3.10",
    packages = c("numpy", "pylate>=1.4.0,<1.5"),
    exclude_newer = NULL
  )

  expect_equal(
    skald:::.skald_python_requirements_value(reqs),
    "numpy, pylate>=1.4.0,<1.5; python: >=3.10"
  )
})

test_that("PyLate package requirement strings include extras", {
  expect_equal(
    skald:::.skald_python_packages(),
    "pylate>=1.4.0,<1.5"
  )

  expect_equal(
    skald:::.skald_python_packages(extras = c("eval", "voyager")),
    "pylate[eval,voyager]>=1.4.0,<1.5"
  )
})
