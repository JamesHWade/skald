test_that("SkaldStore creates schema and inserts chunks", {
  location <- tempfile("skald-store-")
  model <- skald:::new_skald_model(py = NULL, model_name_or_path = "mock")
  store <- skald_store_create(location, model)

  chunks <- tibble::tibble(
    origin = "doc.md",
    start = c(1L, 10L),
    end = c(5L, 20L),
    context = c(NA_character_, "Heading"),
    text = c("alpha", "beta"),
    section = c("intro", "body")
  )

  skald_store_insert(store, chunks)

  status <- skald_index_status(store)
  expect_equal(status$chunks, 2L)
  expect_equal(status$indexed, 0L)

  stored <- skald:::.skald_store_fetch_chunks(store)
  expect_equal(stored$chunk_uid, c("89a19398::1::5", "89a19398::10::20"))
  expect_equal(stored$embedding_text[[1]], "alpha")
  expect_equal(stored$embedding_text[[2]], "Heading\n\nbeta")
  expect_true("section" %in% names(stored))
})

test_that("SkaldStore supports logical removal", {
  location <- tempfile("skald-store-")
  model <- skald:::new_skald_model(py = NULL, model_name_or_path = "mock")
  store <- skald_store_create(location, model)

  chunks <- tibble::tibble(
    origin = "doc.md",
    start = c(1L, 10L),
    end = c(5L, 20L),
    text = c("alpha", "beta")
  )

  skald_store_insert(store, chunks)
  skald_store_remove(store, text == "alpha")

  stored <- skald:::.skald_store_fetch_chunks(store)
  expect_equal(stored$text, "beta")
})
