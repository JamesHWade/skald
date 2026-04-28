\name{skald-api}
\alias{SkaldEmbeddings}
\alias{SkaldIndex}
\alias{SkaldModel}
\alias{SkaldRetriever}
\alias{SkaldStore}
\alias{skald_as_dsprrr_module}
\alias{skald_check_install}
\alias{skald_configure}
\alias{skald_diagnostics}
\alias{skald_encode_col}
\alias{skald_encode_documents}
\alias{skald_encode_queries}
\alias{skald_fuse_ranks}
\alias{skald_index_add}
\alias{skald_index_create}
\alias{skald_index_retrieve}
\alias{skald_index_status}
\alias{skald_model}
\alias{skald_python_config}
\alias{skald_register_tool_retrieve}
\alias{skald_rerank}
\alias{skald_retrieve}
\alias{skald_retrieve_ragnar}
\alias{skald_retriever}
\alias{skald_score_matrix}
\alias{skald_score_pairwise}
\alias{skald_store_build_index}
\alias{skald_store_connect}
\alias{skald_store_create}
\alias{skald_store_insert}
\alias{skald_store_remove}
\alias{skald_store_update}
\alias{skald_torch_devices}
\title{Skald API}
\description{
Public constructors, retrieval helpers, diagnostics, and adapters for
late-interaction retrieval through Python PyLate.
}
\details{
The v0.1 API wraps PyLate model, embedding, index, and retrieval objects while
keeping Python objects opaque in R. Data-frame helpers accept tidy-selection
columns and return tibbles.
}
\keyword{internal}
