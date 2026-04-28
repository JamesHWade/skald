skald_model <- function(
  model_name_or_path = "lightonai/GTE-ModernColBERT-v1",
  device = NULL,
  query_length = NULL,
  document_length = NULL,
  query_prefix = NULL,
  document_prefix = NULL,
  embedding_size = NULL,
  trust_remote_code = FALSE,
  local_files_only = FALSE,
  revision = NULL,
  token = NULL,
  ...
) {
  if (isTRUE(trust_remote_code)) {
    cli::cli_warn(c(
      "{.arg trust_remote_code} is TRUE.",
      "!" = "This can execute code from the model repository. Only use it for repositories you trust and have reviewed."
    ))
  }

  models <- skald_py_mod("models")

  args <- .skald_compact(list(
    model_name_or_path = model_name_or_path,
    device = device,
    query_length = query_length,
    document_length = document_length,
    query_prefix = query_prefix,
    document_prefix = document_prefix,
    embedding_size = embedding_size,
    trust_remote_code = trust_remote_code,
    local_files_only = local_files_only,
    revision = revision,
    token = token,
    ...
  ))

  py_model <- do.call(models$ColBERT, args)

  new_skald_model(
    py = py_model,
    model_name_or_path = model_name_or_path,
    backend = "pylate",
    device = device,
    query_length = query_length,
    document_length = document_length,
    query_prefix = query_prefix,
    document_prefix = document_prefix,
    trust_remote_code = trust_remote_code,
    revision = revision,
    local_files_only = local_files_only,
    metadata = list(extra_args = list(...))
  )
}

skald_model_rehydrate <- function(model) {
  .skald_check_model(model)

  if (!is.null(model@py)) {
    return(model)
  }

  model@py <- skald_model(
    model_name_or_path = model@model_name_or_path,
    device = model@device,
    query_length = model@query_length,
    document_length = model@document_length,
    query_prefix = model@query_prefix,
    document_prefix = model@document_prefix,
    trust_remote_code = model@trust_remote_code,
    local_files_only = model@local_files_only,
    revision = model@revision
  )@py

  model
}

.skald_model_py <- function(model) {
  model <- skald_model_rehydrate(model)
  model@py
}
