skald_score_matrix <- function(
  query_embeddings,
  document_embeddings,
  queries_mask = NULL,
  documents_mask = NULL
) {
  scores <- skald_py_mod("scores")

  q <- if (S7::S7_inherits(query_embeddings, SkaldEmbeddings)) query_embeddings@py else query_embeddings
  d <- if (S7::S7_inherits(document_embeddings, SkaldEmbeddings)) document_embeddings@py else document_embeddings

  out <- scores$colbert_scores(
    queries_embeddings = q,
    documents_embeddings = d,
    queries_mask = queries_mask,
    documents_mask = documents_mask
  )

  as.matrix(reticulate::py_to_r(out))
}

skald_score_pairwise <- function(query_embeddings, document_embeddings) {
  scores <- skald_py_mod("scores")

  q <- if (S7::S7_inherits(query_embeddings, SkaldEmbeddings)) query_embeddings@py else query_embeddings
  d <- if (S7::S7_inherits(document_embeddings, SkaldEmbeddings)) document_embeddings@py else document_embeddings

  out <- scores$colbert_scores_pairwise(
    queries_embeddings = q,
    documents_embeddings = d
  )

  as.numeric(reticulate::py_to_r(out))
}
