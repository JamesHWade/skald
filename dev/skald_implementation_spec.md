# `skald`: Late-Interaction Retrieval and Reranking for R

## Complete implementation specification

**Working package name:** `skald`  
**Package title:** Late-Interaction Retrieval and Reranking for R  
**Primary backend:** Python PyLate via `reticulate`  
**Primary integrations:** tidyverse, ragnar, ellmer, dsprrr  
**Target first release:** retrieval and reranking, not training-first

---

## 1. Executive summary

`skald` should be an idiomatic R package for ColBERT-style late-interaction retrieval, reranking, scoring, and indexing. Its first implementation should wrap the Python `pylate` package through `reticulate`, while presenting a tidyverse-native R interface that works naturally with tibbles, bare-column selection, grouped data frames, ragnar stores, ellmer tools, and dsprrr-style RAG pipelines.

The package should not be merely a thin Python wrapper. Its value should come from translating PyLate’s late-interaction model/index APIs into inspectable R retrieval workflows.

The recommended product boundary is:

```text
ragnar = ingest, chunk, store, first-stage retrieve, LLM tool integration
skald  = late-interaction encode, index, retrieve, rerank, score, explain
dsprrr = declarative RAG/program pipeline, optimization, tracing/evaluation
```

The MVP should focus on three practical workflows:

1. Rerank `ragnar_retrieve()` results with a late-interaction model.
2. Build a late-interaction index from `ragnar::markdown_chunk()` output.
3. Use a standalone PyLate-backed index from R.

Training, evaluation, Rust backends, and NextPlaid support should come later.

---

## 2. Package name

Recommended name: **`skald`**.

A skald was a Norse poet or reciter, which fits naturally with ragnar’s existing Norse naming frame. In package terms, ragnar prepares and searches a knowledge store; `skald` retrieves, reranks, and scores the passages worth reciting.

Advantages:

- Short, lowercase, memorable.
- Fits the ragnar ecosystem without being limited to ragnar.
- Broad enough to support PyLate today, pylate-rs or NextPlaid later, and other late-interaction engines in the future.
- Avoids ambiguous or overloaded names.

Names to avoid:

- `pylater`: too close to the existing R package `later`, and visually awkward.
- `colbertr`: too narrow; PyLate and the future package can support more than ColBERT.
- `ragnarok`: overfits ragnar and has a negative connotation.
- `pylate`: good for discoverability, but less distinctive and less future-proof.

Recommended package metadata:

```text
Package: skald
Title: Late-Interaction Retrieval and Reranking for R
Description: Tidy R interfaces to ColBERT-style late-interaction retrieval,
    reranking, scoring, and indexing, with first-class integration for
    ragnar knowledge stores.
```

---

## 3. Design principles

### 3.1 R-first, Python-backed

The first version should wrap Python PyLate via `reticulate`. Do not reimplement ColBERT, PLAID, MaxSim, Sentence Transformers, Hugging Face integration, or training infrastructure in native R for the MVP.

The R API should hide most Python details behind stable R objects and tidy outputs.

### 3.2 Tibbles in, tibbles out

Data-frame APIs should accept tibbles and return tibbles. Existing columns should be preserved unless explicitly dropped. Scores and ranks should be appended using predictable names.

### 3.3 Opaque embeddings by default

ColBERT-style embeddings are multi-vector, token-level, often ragged, and can be large. Do not eagerly convert them to R arrays or matrices. Keep Python objects opaque unless the user explicitly materializes or inspects them.

### 3.4 Do not misuse ragnar’s dense embedding slot

ragnar’s `embed` function is designed around dense single-vector embeddings represented as a matrix. Late-interaction models do not produce a simple one-row-per-document dense matrix in the same semantic sense. Do not try to plug PyLate directly into `ragnar_store_create(embed = ...)`.

Correct pattern:

```r
ragnar::ragnar_retrieve(store, query, top_k = 50) |>
  skald_rerank(model, query = query, text = text, top_k = 5)
```

Note: `ragnar_retrieve()`'s second parameter is named `text` in ragnar's
signature, not `query`. The variable named `query` above is passed positionally
and works correctly. Do not pass it as a named argument (`query = ...`) or the
call will error.

Incorrect pattern:

```r
ragnar_store_create(embed = skald_embed_colbert(...))
```

### 3.5 Late interaction belongs after candidate generation or in its own index

Use late interaction in two places:

1. Reranking candidates produced by ragnar, BM25, vector search, SQL filters, or another retriever.
2. Searching a dedicated PyLate/PLAID-backed index.

### 3.6 Stable public API, flexible Python escape hatches

Expose common arguments directly, but pass advanced PyLate options through `...`. This avoids chasing every PyLate and Sentence Transformers argument in the R API.

### 3.7 Installation diagnostics are a first-class feature

Python, PyTorch, GPU wheels, and Hugging Face model downloads are common failure points. `skald_diagnostics()` must be part of the MVP.

---

## 4. Core workflows

### 4.1 Rerank ragnar results

```r
library(ragnar)
library(skald)

model <- skald_model("lightonai/GTE-ModernColBERT-v1", device = "cpu")

query <- "How can I subset a dataframe with a logical vector?"

hits <- ragnar_retrieve(store, query, top_k = 50)

hits |>
  skald_rerank(
    model,
    query = query,
    text = text,
    id = c(origin, doc_id, chunk_id),
    top_k = 5
  )
```

Expected behavior:

- Preserve ragnar output columns.
- Add `late_score` and `late_rank`.
- Order by `late_score` descending.
- Keep first-stage ordering as tie-breaker.

### 4.2 One-call ragnar retrieval plus late reranking

```r
skald_retrieve_ragnar(
  store,
  model,
  query = "How do I use dplyr filter?",
  candidate_k = 40,
  top_k = 6,
  filter = area == "data-transform"
)
```

Expected behavior:

1. Call `ragnar::ragnar_retrieve(store, query, top_k = candidate_k, ...)`.
2. Pass filter expressions through to ragnar where applicable.
3. Rerank returned candidates with `skald_rerank()`.
4. Return top `top_k` rows.

### 4.3 Build a SkaldStore from ragnar chunks

```r
chunks <- "https://r4ds.hadley.nz/data-transform.html" |>
  ragnar::read_as_markdown() |>
  ragnar::markdown_chunk()

store <- skald_store_create(
  "r4ds.skald",
  model = model,
  name = "r4ds",
  title = "R for Data Science"
)

skald_store_insert(store, chunks)
skald_store_build_index(store)

skald_retrieve(store, "How do I filter rows?", top_k = 5)
```

### 4.4 Standalone PyLate index

```r
docs <- tibble::tibble(
  doc_id = c("1", "2", "3"),
  text = c(
    "ColBERT keeps token-level embeddings for fine-grained retrieval.",
    "PLAID compresses token vectors for scalable search.",
    "PyLate trains and retrieves with late-interaction models."
  )
)

model <- skald_model("lightonai/GTE-ModernColBERT-v1", device = "cpu")

index <- skald_index_create("demo-index", overwrite = TRUE)

index <- skald_index_add(
  index,
  model,
  docs,
  id = doc_id,
  text = text
)

skald_index_retrieve(
  index,
  model,
  query = "What library supports ColBERT retrieval?",
  top_k = 3
)
```

### 4.5 ellmer tool registration

```r
chat <- ellmer::chat_openai()

skald_register_tool_retrieve(
  chat,
  store,
  model = model,
  top_k = 8,
  candidate_k = 50,
  store_description = "R package documentation and examples"
)
```

### 4.6 dsprrr retriever adapter

```r
retriever <- skald_retriever(
  store = store,
  model = model,
  top_k = 5,
  format = "context"
)

retriever("How do I subset rows?")

skald_as_dsprrr_module(
  retriever,
  signature = "question -> context"
)
```

---

## 5. Object model

Use S7 for public classes to align with tidyverse design and ragnar’s current class style.

Each public S7 class must have a `print` method registered via
`S7::method(print, ClassName)`. The print method should show the class name,
key identifying fields (model name, index path, store location, etc.), and a
one-line summary of state. Without print methods, REPL output is an
unhelpful raw S7 dump.

Example minimum output for `SkaldModel`:

```text
<SkaldModel>
  model: lightonai/GTE-ModernColBERT-v1
  device: cpu
  backend: pylate
  loaded: TRUE
```

### 5.1 `SkaldModel`

Purpose: represent a PyLate ColBERT model and its R-side metadata.

Fields:

```text
py                 Python object, nullable/lazy
model_name_or_path character
backend            character, default "pylate"
device             character or NULL
query_length       integer or NULL
document_length    integer or NULL
query_prefix       character or NULL
document_prefix    character or NULL
trust_remote_code  logical
revision           character or NULL
local_files_only   logical
created_at         POSIXct
metadata           list
```

Notes:

- The Python object must be lazy or rehydratable.
- The R object should retain enough information to recreate the Python object after serialization.
- `trust_remote_code` should default to `FALSE`.

### 5.2 `SkaldEmbeddings`

Purpose: hold opaque query or document embeddings.

Fields:

```text
py          Python object
kind        "query" or "document"
n           integer
model_id    character or NULL
backend     character
metadata    list
```

Notes:

- Do not auto-convert to R arrays.
- Provide explicit inspection helpers later, such as `skald_embedding_dims()`.

### 5.3 `SkaldIndex`

Purpose: represent a low-level PyLate PLAID index.

Fields:

```text
py             Python object
index_folder   character
index_name     character
backend        "pylate"
use_fast       logical
nbits          integer
n_ivf_probe    integer
n_full_scores  integer
metadata_path  character or NULL
created_at     POSIXct
```

### 5.4 `SkaldStore`

Purpose: represent a higher-level R metadata store plus PyLate index.

Fields:

```text
location       character
metadata_db    character
index_folder   character
index_name     character
model_spec     SkaldModel or list
backend        character
read_only      logical
name           character or NULL
title          character or NULL
text_template  character
created_at     POSIXct
```

The `SkaldStore` is a sibling to `RagnarStore`, not initially a subclass.

### 5.5 `SkaldRetriever`

Purpose: represent a reusable retrieval function or tool adapter.

Fields:

```text
store          SkaldStore or RagnarStore
model          SkaldModel or NULL
top_k          integer
candidate_k    integer or NULL
format         "tibble", "markdown", or "context"
metadata       list
```

---

## 6. Public API

### 6.1 Configuration and diagnostics

```r
skald_configure(
  version_spec = ">=1.4.0,<1.5",
  extras = character(),
  python_version = ">=3.10",
  exclude_newer = NULL,
  action = "add"
)

skald_diagnostics()
skald_python_config()
skald_torch_devices()
skald_check_install()
skald_index_status(x)
```

`skald_diagnostics()` should report:

```text
R version
skald version
reticulate version
Python executable
Python version
pylate version
torch version
sentence_transformers version
transformers version
fast-plaid version           # separate PyPI package; check via importlib.metadata.version("fast-plaid")
CUDA availability
MPS availability
default torch device
active reticulate requirements
active model/index specs
```

Error style:

```text
Could not import Python package 'pylate'.

i Run skald_diagnostics() to inspect the active Python environment.
i Run skald_configure() before Python is initialized to change requirements.
i For CPU-only PyTorch wheels, set UV_INDEX before loading skald.
```

### 6.2 Model construction

```r
skald_model(
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
)
```

Returns: `SkaldModel`.

Implementation:

- Wrap `pylate.models.ColBERT`.
- Import Python modules with `convert = FALSE`.
- Warn clearly when `trust_remote_code = TRUE`.
- Store full R-side model spec.

### 6.3 Encoding

Vector APIs:

```r
skald_encode_queries(
  model,
  queries,
  batch_size = 32,
  show_progress = interactive(),
  precision = "float32",
  normalize_embeddings = TRUE,
  convert_to_numpy = TRUE,
  ...
)

skald_encode_documents(
  model,
  documents,
  batch_size = 32,
  show_progress = interactive(),
  precision = "float32",
  normalize_embeddings = TRUE,
  convert_to_numpy = TRUE,
  ...
)
```

Data-frame helper:

```r
skald_encode_col(
  .data,
  model,
  text,
  kind = c("document", "query"),
  name = ".skald_embedding",
  batch_size = 32,
  ...
)
```

Returns:

- Vector APIs return `SkaldEmbeddings`.
- Data-frame helper returns a tibble with a list-column only if explicitly requested.

### 6.4 Reranking

```r
skald_rerank(
  .data,
  model,
  query,
  text,
  id = NULL,
  query_id = NULL,
  top_k = NULL,
  batch_size = 32,
  device = NULL,
  score_col = "late_score",
  rank_col = "late_rank",
  keep_all = TRUE,
  ...
)
```

Inputs:

- `.data`: data frame/tibble of candidate documents or chunks.
- `model`: `SkaldModel`.
- `query`: scalar string or bare column.
- `text`: bare column containing candidate text.
- `id`: optional bare column or tidyselect expression identifying candidates.
- `query_id`: optional grouping/query id column.

Behavior:

- If `.data` is grouped, rerank independently within each group.
- If `query` is scalar, use same query for all rows/groups.
- If `query` is a column, use the unique query per group.
- If `top_k` is non-NULL, return only the top rows per group.
- Preserve existing columns.
- Add `score_col` and `rank_col`.
- Order descending by late score.
- Ties preserve original candidate order.

Implementation:

- Encode one query per group with `skald_encode_queries()`.
- Encode candidate text with `skald_encode_documents()`.
- Call `pylate.rank.rerank()`.
- Convert results to a tibble and join back to original rows by internal id.

### 6.5 ragnar retrieval plus reranking

```r
skald_retrieve_ragnar(
  store,
  model,
  query,
  top_k = 5,
  candidate_k = max(30, top_k * 10),
  ...,
  deoverlap = TRUE,
  filter,
  include_first_stage = TRUE
)
```

Behavior:

- Calls `ragnar::ragnar_retrieve()` with `top_k = candidate_k`.
- Passes `filter`, `deoverlap`, and additional arguments to ragnar where appropriate.
- Reranks candidates with `skald_rerank()`.
- Returns a ragnar-shaped tibble with `late_score` and `late_rank`.

### 6.6 Low-level index creation

```r
skald_index_create(
  index_folder = "skald-index",
  index_name = "colbert",
  overwrite = FALSE,
  use_fast = TRUE,
  nbits = 4,
  kmeans_niters = 4,
  n_ivf_probe = 8,
  n_full_scores = 8192,
  device = NULL,
  show_progress = interactive(),
  ...
)
```

Returns: `SkaldIndex`.

Implementation:

- Wrap `pylate.indexes.PLAID`.
- Map `overwrite` to PyLate’s `override` argument.
- Use FastPLAID by default when supported.

### 6.7 Add documents to index

```r
skald_index_add(
  index,
  model,
  .data,
  id,
  text,
  context = NULL,
  batch_size = 32,
  text_template = "{context}\n\n{text}",
  ...
)
```

Behavior:

- Accept data frame/tibble.
- Build `embedding_text` from `text` and optional `context`.
- Encode documents.
- Add document ids and embeddings to PyLate index.
- Optionally write metadata sidecar.
- Return updated `SkaldIndex`.

### 6.8 Retrieve from low-level index

```r
skald_index_retrieve(
  index,
  model,
  query,
  top_k = 10,
  query_id = NULL,
  batch_size = 32,
  k_token = 100,
  device = NULL,
  subset = NULL,
  include_text = TRUE,
  ...
)
```

Returns a tibble with:

```text
query_id
query
rank
id
late_score
text/context if metadata is available
```

### 6.9 SkaldStore creation and connection

```r
skald_store_create(
  location = "docs.skald",
  model,
  overwrite = FALSE,
  extra_cols = NULL,
  name = NULL,
  title = NULL,
  index_name = "colbert",
  text_template = "{context}\n\n{text}",
  ...
)

skald_store_connect(
  location,
  model = NULL,
  read_only = TRUE
)
```

### 6.10 Insert chunks into SkaldStore

```r
skald_store_insert(
  store,
  chunks,
  ...,
  text = text,
  context = context,
  origin = origin,
  batch = TRUE
)
```

Accepted `chunks` inputs:

```text
ragnar::MarkdownDocumentChunks
data.frame/tibble with text
character vector
```

Behavior:

- Normalize chunks to a tibble.
- Create stable `chunk_uid` values.
- Preserve ragnar columns where present.
- Store text and metadata in DuckDB.
- Mark rows as `indexed = FALSE` until `skald_store_build_index()` completes.

### 6.11 Build or update SkaldStore index

```r
skald_store_build_index(
  store,
  batch_size = 32,
  force = FALSE,
  ...
)
```

Behavior:

- Find chunks where `indexed = FALSE`, unless `force = TRUE`.
- Encode `embedding_text`.
- Add embeddings to PLAID index.
- Mark rows as indexed.
- Record index events.

### 6.12 Retrieve from SkaldStore

```r
skald_retrieve(
  store,
  query,
  top_k = 5,
  ...,
  filter,
  deoverlap = TRUE,
  include_text = TRUE
)
```

Behavior:

- Apply metadata prefilter in DuckDB when `filter` is supplied.
- Pass matching `chunk_uid` values as PyLate retriever subset when possible.
- Retrieve with PLAID.
- Join results to chunk metadata.
- Optionally deoverlap adjacent/overlapping chunks.
- Return a tibble.

### 6.13 Store update and removal

```r
skald_store_update(
  store,
  chunks,
  ...
)

skald_store_remove(
  store,
  filter
)
```

Initial support may be limited because PyLate index deletion/update semantics may not support efficient in-place removal. For MVP, support logical deletion in DuckDB and filter deleted chunks from results. Rebuild workflows can be added later.

### 6.14 ellmer tool registration

```r
skald_register_tool_retrieve(
  chat,
  store,
  model = NULL,
  top_k = 8,
  candidate_k = 50,
  store_description = "the late-interaction knowledge store",
  name = NULL,
  title = NULL
)
```

Behavior:

- If `store` is a `SkaldStore`, call `skald_retrieve()`.
- If `store` is a `RagnarStore`, call `skald_retrieve_ragnar()` and require `model`.
- Register an ellmer tool using a similar interface to ragnar’s retrieve tool.

### 6.15 Reusable retriever adapter

```r
skald_retriever(
  store,
  model = NULL,
  top_k = 5,
  candidate_k = NULL,
  format = c("tibble", "markdown", "context"),
  ...
)
```

Returns a plain R closure, not an S7 object. S7 objects are not callable in R;
wrapping in a closure is simpler and sufficient:

```r
skald_retriever <- function(store, model = NULL, top_k = 5, ...) {
  force(store); force(model); force(top_k)
  function(query) {
    skald_retrieve_ragnar(store, model, query = query, top_k = top_k, ...)
  }
}
```

`SkaldRetriever` (section 5.5) stores the configuration for introspection and
`skald_as_dsprrr_module()` but is separate from the callable itself. The closure
captures all parameters at creation time.

### 6.16 dsprrr adapter

```r
skald_as_dsprrr_module(
  retriever,
  signature = "question -> context",
  ...
)
```

`dsprrr` should be in `Suggests`, not `Imports`.

### 6.17 Scoring

```r
skald_score_matrix(
  query_embeddings,
  document_embeddings,
  queries_mask = NULL,
  documents_mask = NULL
)

skald_score_pairwise(
  query_embeddings,
  document_embeddings
)
```

Returns:

- Matrix for all-pairs scoring where feasible.
- Numeric vector for pairwise scores.

### 6.18 Rank fusion

```r
skald_fuse_ranks(
  .data,
  ...,
  method = c("rrf", "weighted_sum"),
  k = 60,
  weights = NULL,
  rank_col = "fused_rank",
  score_col = "fused_score"
)
```

`...` receives bare column references for the rank or score columns to fuse,
passed as tidyselect expressions. Example:

```r
hits |>
  skald_fuse_ranks(
    bm25, cosine_distance, late_score,
    method = "rrf",
    rank_col = "hybrid_rank"
  )
```

Each named column is treated as a rank or score signal. Column direction
(higher-is-better vs lower-is-better) must be documented per column: `bm25`
and `late_score` are higher-is-better; `cosine_distance` is lower-is-better.
Either document the convention or require callers to negate columns before
fusing.

Use cases:

- Combine `bm25`, `cosine_distance`, and `late_score`.
- Compare first-stage and late-stage ordering.
- Build hybrid retrieval workflows.

Do not make fusion the default. Default final order after reranking should be `late_score` descending.

---

## 7. Tidyverse integration specification

### 7.1 Data-frame APIs use tidy evaluation

Examples:

```r
skald_rerank(candidates, model, query = query, text = text, id = doc_id)

skald_index_add(index, model, docs, id = doc_id, text = text)

skald_store_insert(store, chunks, text = text, context = context)
```

### 7.2 Vector APIs accept vectors

Examples:

```r
skald_encode_queries(model, c("query 1", "query 2"))

skald_encode_documents(model, docs$text)
```

### 7.3 Grouped data frames define independent reranking groups

```r
candidates |>
  dplyr::group_by(query_id) |>
  skald_rerank(
    model,
    query = query,
    text = text,
    id = doc_id,
    top_k = 5
  )
```

### 7.4 Column preservation

Reranking should preserve all original columns and append only the requested score/rank columns.

### 7.5 Stable sorting

The package should preserve first-stage order as a tie-breaker. Before reranking, create `.skald_input_order`; after reranking, sort by:

```text
group columns
late_score descending
.skald_input_order ascending
```

Then remove `.skald_input_order` unless explicitly requested.

### 7.6 Name repair

If `late_score` or `late_rank` already exists, use vctrs name repair or require the user to set `score_col` and `rank_col`. Prefer a clear error:

```text
Column 'late_score' already exists.

i Set score_col to a different name, for example score_col = "colbert_score".
```

---

## 8. ragnar integration specification

### 8.1 Candidate reranking

This is the most important v0.1 ragnar integration.

```r
query <- "How can I join two tibbles?"

ragnar::ragnar_retrieve(store, query, top_k = 50) |>
  skald_rerank(
    model,
    query = query,
    text = text,
    id = c(origin, doc_id, chunk_id),
    top_k = 8
  )
```

No ragnar internals are required. This uses only public ragnar output and public PyLate reranking.

### 8.2 `skald_retrieve_ragnar()`

A convenience wrapper around first-stage ragnar retrieval followed by late reranking.

```r
skald_retrieve_ragnar(
  store,
  model,
  query,
  top_k = 5,
  candidate_k = max(30, top_k * 10),
  ...,
  deoverlap = TRUE,
  filter,
  include_first_stage = TRUE
)
```

Implementation details:

- Capture `filter` with tidy evaluation.
- Call `ragnar::ragnar_retrieve(store, query, top_k = candidate_k, ...)`.
  The second argument to `ragnar_retrieve()` is named `text` in ragnar's
  signature; pass the query string positionally.
- Pass `filter` and `deoverlap` through `...` to ragnar (both are accepted
  via `...` by `ragnar_retrieve()`).
- Identify the text column. Default to `text`.
- Identify candidate ids from available columns: `c(origin, doc_id, chunk_id)`
  as a composite key, falling back to row index. **ragnar does not produce a
  `chunk_uid` column.** The columns `origin` (character), `doc_id` (integer),
  and `chunk_id` (integer) are the actual identifiers in ragnar v2 output.
  Construct a synthetic internal id by pasting these together for PyLate.
- Call `skald_rerank()`.
- Return top `top_k` rows.

### 8.3 Build SkaldStore from ragnar chunks

`skald_store_insert()` should understand the shape returned by `ragnar::markdown_chunk()`.

`markdown_chunk()` returns a `MarkdownDocumentChunks` object — an S7 class
that also inherits from tibble. Its columns are:

```text
start    integer  character position of chunk start in the source document
end      integer  character position of chunk end in the source document
context  character  heading path (optional, present when context = TRUE)
text     character  chunk text (optional, present when text = TRUE)
```

The source URL or file path is stored in the `@document` S7 property of the
`MarkdownDocumentChunks` object, not as a column. `skald_store_insert()` must
extract `origin` from `chunks@document@path` (or `@url`).

There is no `origin`, `doc_id`, or `chunk_id` column in `markdown_chunk()`
output — those are ragnar store artifacts. `skald_store_insert()` must
generate its own `chunk_uid` values (see section 9.4) and assign a
`document_uid` per source document.

When receiving ragnar store retrieval output (e.g., for display or
`skald_store_from_ragnar()`), the columns to preserve when present are:

```text
origin    character  source document path or URL
doc_id    integer    ragnar auto-increment document id (store-specific, not stable)
chunk_id  integer    ragnar auto-increment chunk id (store-specific, not stable)
start     integer    character start position
end       integer    character end position
context   character  heading context
text      character  chunk text
```

Note: ragnar's `doc_id` and `chunk_id` are auto-increment integers. They are
not stable across store rebuilds and should not be used as durable identifiers
in skald's own storage (see section 9.4).

### 8.4 Convert or mirror a RagnarStore

Later, experimental:

```r
skald_store_from_ragnar(
  ragnar_store,
  location = "docs.skald",
  model,
  text_template = "{context}\n\n{text}",
  overwrite = FALSE
)
```

This should query chunks from the ragnar store and build a SkaldStore. It should be experimental because ragnar’s internal storage schema is not the public extension point to depend on.

### 8.5 ellmer registration parity

`skald_register_tool_retrieve()` should mimic ragnar’s tool registration style so users can switch between ragnar retrieval and skald retrieval with minimal code changes.

---

## 9. SkaldStore storage design

### 9.1 Directory layout

```text
docs.skald/
  metadata.duckdb
  plaid/
    colbert/
      ...
  manifest.json
```

### 9.2 DuckDB schema

```sql
CREATE TABLE skald_metadata (
  key TEXT PRIMARY KEY,
  value_json TEXT,
  value_blob BLOB
);

CREATE TABLE documents (
  document_uid TEXT PRIMARY KEY,
  origin TEXT,
  hash TEXT,
  text TEXT,
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE chunks (
  chunk_uid TEXT PRIMARY KEY,
  document_uid TEXT,
  origin TEXT,
  doc_id TEXT,    -- TEXT here, not INTEGER; ragnar uses INTEGER but skald generates its own stable ids
  chunk_id INTEGER,
  start INTEGER,
  "end" INTEGER,
  hash TEXT,
  context TEXT,
  text TEXT,
  embedding_text TEXT,
  indexed BOOLEAN,
  indexed_at TIMESTAMP,
  deleted BOOLEAN DEFAULT FALSE,
  deleted_at TIMESTAMP,
  model_id TEXT
);

CREATE TABLE index_events (
  event_id TEXT PRIMARY KEY,
  chunk_uid TEXT,
  action TEXT,
  status TEXT,
  created_at TIMESTAMP,
  completed_at TIMESTAMP,
  error TEXT
);
```

Extra metadata columns should either be added to `chunks` or stored in a separate `chunk_metadata` table:

```sql
CREATE TABLE chunk_metadata (
  chunk_uid TEXT,
  key TEXT,
  value_json TEXT,
  PRIMARY KEY (chunk_uid, key)
);
```

For MVP, storing extra columns directly in `chunks` is simpler.

### 9.3 Manifest

`manifest.json` should contain:

```json
{
  "schema_version": 1,
  "package": "skald",
  "backend": "pylate",
  "index_backend": "plaid",
  "index_name": "colbert",
  "model": {
    "model_name_or_path": "lightonai/GTE-ModernColBERT-v1",
    "device": null,
    "query_length": null,
    "document_length": null,
    "trust_remote_code": false
  },
  "text_template": "{context}\n\n{text}"
}
```

### 9.4 Stable chunk ids

The `chunk_uid` passed to PyLate must be stable and string-valued. Stable means
the same chunk produces the same uid if re-inserted from the same source, so
that incremental updates can detect duplicates without rebuilding the whole index.

**Do not include ragnar's auto-increment `doc_id` or `chunk_id` in the uid.**
Those integers change if the ragnar store is rebuilt or if chunks are inserted
in a different order. Base stability on content and position only.

Recommended construction from `markdown_chunk()` output:

```r
# origin_hash: first 8 hex chars of sha1(origin) to keep uid short
origin_hash <- substr(openssl::sha1(origin), 1, 8)
chunk_uid <- paste(origin_hash, start, end, sep = "::")
```

This is stable because `start` and `end` are character positions in the source
document, which do not change when the source content does not change.

For cases where position is not available (plain character vectors, arbitrary
data frames without `start`/`end`):

```r
chunk_uid <- paste0("c-", substr(openssl::sha1(text), 1, 16))
```

A content hash alone is sufficient for plain text inputs. If two chunks have
identical text, they share a uid; this is intentional (deduplication).

When receiving data that already has a user-supplied stable id column (e.g.,
`id = doc_id` in `skald_index_add()`), use that value directly after coercing
to character.

### 9.5 Text used for embedding

Use `text_template` to construct `embedding_text`.

Default:

```text
{context}\n\n{text}
```

`context` is frequently `NA` or `""` for chunks that have no heading hierarchy.
Do not pass the raw template through `glue::glue()` without guarding against
this: `glue` will produce the literal string `"NA\n\nchunk text"`, embedding
"NA" into every uncontexted document's embedding input.

Required handling before template interpolation:

```r
embedding_text <- if (is.na(context) || !nzchar(trimws(context))) {
  text
} else {
  glue::glue(text_template, .envir = list(context = context, text = text))
}
```

Apply this logic row-wise. Vectorize with `dplyr::if_else()` or
`mapply()`/`purrr::map2_chr()` when processing a full data frame column.

---

## 10. Retrieval output contract

### 10.1 `skald_retrieve()` output

Return a tibble with:

```text
query_id          character
query             character
rank              integer
chunk_uid         character
late_score        double
metric_name       character, usually "maxsim"
metric_value      double, same as late_score
origin            character
doc_id            character/integer/list-column depending source
chunk_id          integer/list-column
start             integer
end               integer
context           character
text              character
extra metadata    preserved
```

### 10.2 `skald_rerank()` output

Return the original input data with appended columns:

```text
late_score
late_rank
```

### 10.3 Score semantics

Document clearly:

```text
higher late_score = better
lower cosine_distance = better
higher bm25 = better
```

MaxSim/ColBERT scores should not be treated as probabilities. They are query-relative scores based on token-level maximum similarities and summed across query tokens. They are not bounded to `[0, 1]`, and universal thresholds are unreliable.

---

## 11. Python dependency management

### 11.1 reticulate requirements

In `.onLoad()`:

```r
.onLoad <- function(libname, pkgname) {
  reticulate::py_require(
    packages = "pylate>=1.4.0,<1.5",
    python_version = ">=3.10"
  )
}
```

### 11.2 User configuration helper

```r
skald_configure <- function(
  version_spec = ">=1.4.0,<1.5",
  extras = character(),
  python_version = ">=3.10",
  exclude_newer = NULL,
  action = "add"
) {
  pkg <- if (length(extras)) {
    sprintf("pylate[%s]%s", paste(extras, collapse = ","), version_spec)
  } else {
    sprintf("pylate%s", version_spec)
  }

  reticulate::py_require(
    packages = pkg,
    python_version = python_version,
    exclude_newer = exclude_newer,
    action = action
  )
}
```

Examples:

```r
skald_configure()
skald_configure(extras = "eval")
skald_configure(extras = "voyager")
```

### 11.3 Import cache

```r
.local <- new.env(parent = emptyenv())

skald_py_mod <- function(name) {
  key <- paste0("pylate.", name)

  if (!exists(key, envir = .local, inherits = FALSE)) {
    mod <- reticulate::import(key, convert = FALSE)
    assign(key, mod, envir = .local)
  }

  get(key, envir = .local, inherits = FALSE)
}
```

### 11.4 Installation failure handling

```r
skald_ensure_pylate <- function() {
  tryCatch(
    reticulate::import("pylate", convert = FALSE),
    error = function(e) {
      cli::cli_abort(c(
        "Could not import Python package {.pkg pylate}.",
        "i" = "Run {.code skald_diagnostics()} to inspect the Python environment.",
        "i" = "Run {.code skald_configure()} before Python is initialized to change requirements."
      ), parent = e)
    }
  )
}
```

---

## 12. Internal implementation layout

```text
skald/
  DESCRIPTION
  NAMESPACE
  R/
    deps.R                  # py_require, py import helpers, diagnostics
    class-model.R           # SkaldModel
    class-embeddings.R      # SkaldEmbeddings
    class-index.R           # SkaldIndex
    class-store.R           # SkaldStore
    class-retriever.R       # SkaldRetriever
    model.R                 # skald_model(), model rehydration
    encode.R                # encode vector + data-frame APIs
    index.R                 # PLAID index create/add/retrieve/remove
    store.R                 # DuckDB sidecar + SkaldStore APIs
    retrieve.R              # skald_retrieve(), skald_index_retrieve()
    rerank.R                # skald_rerank(), skald_retrieve_ragnar()
    ragnar.R                # ragnar-specific adapters
    ellmer.R                # skald_register_tool_retrieve()
    dsprrr.R                # optional adapter
    scores.R                # score matrix/pairwise/KD
    fusion.R                # RRF and score/rank fusion
    train.R                 # later: training wrappers
    eval.R                  # later: evaluators
    diagnostics.R           # Python/Torch/PyLate/device/index diagnostics
    utils-tidyselect.R
    utils-python.R
    utils-results.R
    utils-store.R
  inst/
    python/
      bridge.py             # flatten PyLate results; normalize ids/scores
  tests/
    testthat/
      helper.R
      test-rerank.R
      test-results.R
      test-store-schema.R
      test-ragnar-adapter.R
      test-scores.R
      test-diagnostics.R
  vignettes/
    quickstart.Rmd
    rerank-ragnar.Rmd
    skald-store.Rmd
    standalone-pylate.Rmd
    python-environments.Rmd
    dsprrr.Rmd
  man/
  README.Rmd
  README.md
  pkgdown/
  _pkgdown.yml
```

### 12.1 Python bridge

Keep `inst/python/bridge.py` tiny.

Responsibilities:

```python
def flatten_results(results, query_ids):
    """
    Convert list[list[{"id": ..., "score": ...}]] into a flat list of dicts:
    [{"query_id": ..., "rank": ..., "id": ..., "score": ...}, ...]
    """
```

Most logic should stay in R.

**Import mechanism.** Load the bridge module once at package load time using
`reticulate::import_from_path()` with `convert = FALSE`:

```r
.local$bridge <- NULL

skald_bridge <- function() {
  if (is.null(.local$bridge)) {
    bridge_path <- system.file("python", package = "skald")
    .local$bridge <- reticulate::import_from_path("bridge", path = bridge_path, convert = FALSE)
  }
  .local$bridge
}
```

Call as `skald_bridge()$flatten_results(results, query_ids)` wherever the
bridge is needed. Do not call `reticulate::source_python()` — it executes into
the global Python namespace and is not appropriate for package code.

---

## 13. Key implementation sketches

### 13.1 Model constructor

```r
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

  py_model <- models$ColBERT(
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
  )

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
    local_files_only = local_files_only
  )
}
```

### 13.2 Encoding

```r
skald_encode_queries <- function(
  model,
  queries,
  batch_size = 32,
  show_progress = interactive(),
  precision = "float32",
  normalize_embeddings = TRUE,
  convert_to_numpy = TRUE,
  ...
) {
  queries <- as.character(queries)

  emb <- model$py$encode(
    sentences = queries,
    batch_size = batch_size,
    show_progress_bar = show_progress,
    precision = precision,
    normalize_embeddings = normalize_embeddings,
    convert_to_numpy = convert_to_numpy,
    is_query = TRUE,
    ...
  )

  new_skald_embeddings(emb, kind = "query", n = length(queries), model = model)
}

skald_encode_documents <- function(
  model,
  documents,
  batch_size = 32,
  show_progress = interactive(),
  precision = "float32",
  normalize_embeddings = TRUE,
  convert_to_numpy = TRUE,
  ...
) {
  documents <- as.character(documents)

  emb <- model$py$encode(
    sentences = documents,
    batch_size = batch_size,
    show_progress_bar = show_progress,
    precision = precision,
    normalize_embeddings = normalize_embeddings,
    convert_to_numpy = convert_to_numpy,
    is_query = FALSE,
    ...
  )

  new_skald_embeddings(emb, kind = "document", n = length(documents), model = model)
}
```

### 13.3 Reranking algorithm

**`pylate.rank.rerank()` signature** (confirmed against PyLate 1.4.0):

```python
rerank(
    documents_ids: list[list[int | str]],   # per-query candidate id lists
    queries_embeddings: list[...],
    documents_embeddings: list[...],
    device: str | None = None
) -> list[list[dict]]                        # each dict: {"id": ..., "score": ...}
```

`documents_ids` is the critical first argument: a list of lists where each
inner list contains the candidate IDs for one query, in the same order as the
corresponding embeddings. For a single query with 50 candidates:
`[["id1", "id2", ..., "id50"]]`. For a batch of N queries:
`[["qA_doc1", ...], ["qB_doc1", ...], ...]`.

The return value `list[list[dict]]` is parallel: one inner list per query,
each dict containing `"id"` and `"score"`.

Pseudo-code:

```r
skald_rerank <- function(
  .data,
  model,
  query,
  text,
  id = NULL,
  query_id = NULL,
  top_k = NULL,
  batch_size = 32,
  device = NULL,
  score_col = "late_score",
  rank_col = "late_rank",
  keep_all = TRUE,
  ...
) {
  # 1. Capture tidy-eval arguments with rlang::enquo() / tidyselect::eval_select().
  # 2. Detect grouping via dplyr::group_vars(.data); split with dplyr::group_split().
  # 3. For each group (or the whole frame if ungrouped):
  #    a. Add .skald_input_order = seq_len(nrow(group)).
  #    b. Extract the unique query string (scalar from env or unique column value).
  #    c. Construct internal_ids: paste the id columns together, or use
  #       as.character(seq_len(nrow(group))) as fallback.
  #    d. Encode query:  q_emb  <- skald_encode_queries(model, query_str, ...)
  #    e. Encode docs:   d_embs <- skald_encode_documents(model, text_vec, ...)
  #    f. Call PyLate rerank — documents_ids must be a length-1 list wrapping
  #       the candidate ids for this single query:
  #
  #         rank_mod <- skald_py_mod("rank")
  #         raw <- rank_mod$rerank(
  #           documents_ids      = list(as.list(internal_ids)),
  #           queries_embeddings = list(q_emb$py),
  #           documents_embeddings = list(d_embs$py),
  #           device             = device
  #         )
  #
  #    g. raw[[1]] is list[dict{"id", "score"}]; convert to tibble:
  #         scores_tbl <- tibble::tibble(
  #           internal_id = vapply(raw[[1]], `[[`, character(1), "id"),
  #           !!score_col := vapply(raw[[1]], `[[`, double(1), "score")
  #         )
  # 4. Join scores_tbl back to group data on internal_id.
  # 5. Add rank_col = rank(desc(score_col), ties.method = "first").
  # 6. Sort by score_col desc, .skald_input_order asc.
  # 7. Remove .skald_input_order.
  # 8. Apply top_k per group if non-NULL.
  # 9. Recombine groups and return tibble.
}
```

**Batching note.** The pseudo-code above calls `rerank()` once per group
(sequential). For large grouped inputs, encoding all queries and all documents
in one pass, then calling `rerank()` with the full batch, is significantly
faster. PyLate's `rerank()` accepts N queries as `documents_ids` of length N
and parallel embedding lists. Implementors should prefer the batched path for
grouped inputs with more than one group.

### 13.4 Index creation

```r
skald_index_create <- function(
  index_folder = "skald-index",
  index_name = "colbert",
  overwrite = FALSE,
  use_fast = TRUE,
  nbits = 4,
  kmeans_niters = 4,
  n_ivf_probe = 8,
  n_full_scores = 8192,
  device = NULL,
  show_progress = interactive(),
  ...
) {
  indexes <- skald_py_mod("indexes")

  py_index <- indexes$PLAID(
    index_folder = index_folder,
    index_name = index_name,
    override = overwrite,
    use_fast = use_fast,
    nbits = nbits,
    kmeans_niters = kmeans_niters,
    n_ivf_probe = n_ivf_probe,
    n_full_scores = n_full_scores,
    device = device,
    show_progress = show_progress,
    ...
  )

  new_skald_index(
    py = py_index,
    index_folder = index_folder,
    index_name = index_name,
    use_fast = use_fast,
    nbits = nbits,
    n_ivf_probe = n_ivf_probe,
    n_full_scores = n_full_scores
  )
}
```

### 13.5 Low-level retrieval

```r
skald_index_retrieve <- function(
  index,
  model,
  query,
  top_k = 10,
  query_id = NULL,
  batch_size = 32,
  k_token = 100,
  device = NULL,
  subset = NULL,
  include_text = TRUE,
  ...
) {
  query <- as.character(query)
  query_id <- query_id %||% paste0("q", seq_along(query))

  q_emb <- skald_encode_queries(
    model,
    query,
    batch_size = batch_size
  )

  retrieve_mod <- skald_py_mod("retrieve")
  retriever <- retrieve_mod$ColBERT(index = index$py)

  results <- retriever$retrieve(
    queries_embeddings = q_emb$py,
    k = top_k,
    k_token = k_token,
    batch_size = batch_size,
    device = device,
    subset = subset,
    ...
  )

  out <- skald_results_to_tibble(results, query_id = query_id, query = query)

  if (include_text) {
    out <- skald_join_index_metadata(out, index)
  }

  out
}
```

---

## 14. DESCRIPTION draft

```text
Package: skald
Title: Late-Interaction Retrieval and Reranking for R
Version: 0.1.0.9000
Description: Provides tidy R interfaces to ColBERT-style late-interaction
    retrieval, reranking, scoring, and indexing. Wraps the Python PyLate
    library via reticulate and integrates with ragnar knowledge stores for
    retrieval-augmented generation workflows.
License: MIT + file LICENSE
Encoding: UTF-8
Roxygen: list(markdown = TRUE)
RoxygenNote: 7.3.3
Depends:
    R (>= 4.3.0)
Imports:
    cli,
    DBI,
    dbplyr,
    dplyr,
    duckdb,
    fs,
    glue,
    jsonlite,
    openssl,
    rlang (>= 1.1.0),
    reticulate (>= 1.42.0),
    S7,
    tibble,
    tidyr,
    tidyselect,
    vctrs
Suggests:
    ragnar,
    ellmer,
    dsprrr,
    testthat (>= 3.0.0),
    knitr,
    rmarkdown,
    pkgdown,
    arrow,
    mirai,
    carrier
Config/testthat/edition: 3
SystemRequirements: Python (>= 3.10)
```

---

## 15. Testing plan

### 15.1 Tier 1: pure R tests

Should run everywhere and never download models.

Test:

```text
tidyselect handling
query scalar vs query column behavior
grouped reranking setup
ID generation
stable sorting
score/rank column name conflict handling
result flattening
store schema creation
metadata filtering
ragnar output compatibility
ellmer tool wrapper shape
```

### 15.2 Tier 2: Python smoke tests

Should run in CI if Python dependencies resolve.

Test:

```text
import pylate
import torch
create tiny tensor inputs
validate score helper conversion
validate PyLate module import cache
validate Python bridge result flattening
```

### 15.3 Tier 3: integration tests

Skip unless:

```text
SKALD_RUN_INTEGRATION_TESTS=true
```

Test:

```text
load a small model
encode tiny query/doc set
build tiny PLAID index
retrieve
rerank ragnar-like candidates
```

### 15.4 Tier 4: GPU tests

Optional only.

Test:

```text
CUDA available path
MPS available path
GPU encode smoke test
GPU retrieve smoke test
```

Never required for CRAN or standard CI.

---

## 16. CI plan

Suggested GitHub Actions matrix:

```text
ubuntu-latest, R release: pure R + Python smoke tests
macOS-latest, R release: pure R + Python smoke tests
windows-latest, R release: pure R tests, optional Python smoke tests
weekly integration workflow: model download + retrieval/rerank
optional self-hosted GPU workflow: CUDA smoke tests
```

Do not allow model downloads to determine whether normal R CMD check passes.

---

## 17. Documentation plan

### 17.1 README

Show three examples:

1. Rerank ragnar results.
2. Build a SkaldStore from ragnar chunks.
3. Standalone PyLate index.

### 17.2 Vignettes

```text
quickstart.Rmd
rerank-ragnar.Rmd
skald-store.Rmd
standalone-pylate.Rmd
python-environments.Rmd
dsprrr.Rmd
```

### 17.3 Required conceptual docs

Document:

```text
What late interaction means
Why ColBERT embeddings are not ordinary dense embeddings
Why skald does not plug into ragnar_store_create(embed = ...)
How MaxSim scores should and should not be interpreted
How candidate_k and top_k interact
How to debug Python environments
How to use CPU vs GPU
How to use trust_remote_code safely
```

---

## 18. Training API, later phase

Training should not be part of the first MVP unless the package is explicitly intended for research users on day one.

Later add:

```r
skald_train_contrastive(
  model,
  train,
  output_dir,
  query = query,
  positive = positive,
  negatives = starts_with("negative"),
  eval = NULL,
  epochs = 1,
  batch_size = 16,
  learning_rate = 3e-6,
  temperature = 0.02,
  fp16 = TRUE,
  bf16 = FALSE,
  gather_across_devices = FALSE,
  ...
)

skald_train_distillation(
  model,
  train,
  queries,
  documents,
  output_dir,
  query_id = query_id,
  document_ids = document_ids,
  scores = scores,
  ...
)
```

Training wrappers should be thin and allow users to pass Python trainer/training arguments through.

---

## 19. Evaluation API, later phase

Optional evaluation functions:

```r
skald_triplet_evaluator(...)
skald_distillation_evaluator(...)
skald_nano_beir_evaluator(...)
skald_evaluate(model, evaluator, ...)
```

Add `pylate[eval]` support through `skald_configure(extras = "eval")`.

---

## 20. Future backends

Keep a backend abstraction early:

```r
backend = c("pylate", "pylate-rs", "next-plaid")
```

Recommended backend roadmap:

```text
v0.1: PyLate through reticulate
v0.2: deeper ragnar and ellmer integration
v0.3: training/evaluation
v0.4: optional NextPlaid client backend
v0.5: optional pylate-rs local inference backend
```

### 20.1 pylate-rs

Potential value:

- Faster local inference.
- Smaller runtime surface.
- Avoids full PyTorch/Transformers stack for some workflows.
- Useful for deployment and serverless cases.

Risk:

- More build complexity.
- Platform-specific binary concerns.
- Less complete training support.

### 20.2 NextPlaid

Potential value:

- External service/database for multi-vector search.
- Metadata prefiltering.
- Incremental updates.
- Better deployment story for production RAG systems.

Risk:

- Separate service lifecycle.
- REST/client complexity.
- Different operational assumptions from local R package workflows.

---

## 21. Risks and mitigations

### 21.1 Python environment friction

Mitigation:

- Use `reticulate::py_require()`.
- Provide `skald_configure()`.
- Provide `skald_diagnostics()`.
- Avoid eager Python initialization before user configuration.

### 21.2 Memory blow-up from conversion

Mitigation:

- Use `convert = FALSE` for imports.
- Keep embeddings opaque.
- Convert only final scores/results.

### 21.3 ragnar internals may change

Mitigation:

- MVP uses public ragnar retrieval and chunking outputs.
- Mark `skald_store_from_ragnar()` experimental.
- Avoid subclassing `RagnarStore` initially.

### 21.4 PyLate API drift

Mitigation:

- Pin stable versions, e.g. `pylate>=1.4.0,<1.5`.
- Add CI against latest PyLate separately.
- Pass advanced args through `...`.

### 21.5 Score misinterpretation

Mitigation:

- Document MaxSim clearly.
- Use `late_score`, not `similarity` or `probability`.
- Avoid default thresholds.

### 21.6 Model downloads and GPU expectations

Mitigation:

- CPU is the baseline.
- Integration tests are opt-in.
- GPU support is documented but optional.

### 21.7 Security around Hugging Face custom code

Mitigation:

- Default `trust_remote_code = FALSE`.
- Warn when enabled.
- Document that remote code can execute locally.

---

## 22. MVP scope

The first release should implement:

```text
skald_model()
skald_configure()
skald_diagnostics()
skald_encode_queries()
skald_encode_documents()
skald_rerank()
skald_retrieve_ragnar()
skald_index_create()
skald_index_add()
skald_index_retrieve()
skald_store_create()
skald_store_connect()
skald_store_insert()
skald_store_build_index()
skald_retrieve()
skald_register_tool_retrieve()
skald_retriever()
skald_score_pairwise()
skald_score_matrix()
```

The first release should not require:

```text
training
evaluation
pylate-rs
NextPlaid
full ragnar store mirroring
in-place index deletion
GPU support
CRAN-safe model downloads
```

---

## 23. Definition of done for v0.1

`skald` v0.1 is complete when:

1. A user can rerank `ragnar_retrieve()` results with one function.
2. A user can build a late-interaction index from `ragnar::markdown_chunk()` output.
3. A user can retrieve from that index and get a ragnar-shaped tibble.
4. A user can register an ellmer retrieval tool backed by a SkaldStore.
5. All Python model/index/embedding objects are lazy or opaque.
6. No default tests require network or model downloads.
7. `skald_diagnostics()` gives enough information to debug common install issues.
8. MaxSim score semantics are documented clearly.
9. `trust_remote_code` defaults to `FALSE`.
10. The package works on CPU as the baseline.
11. The package has tidyverse-native data-frame APIs with bare column support.
12. The package preserves ragnar output columns during reranking.

---

## 24. Reference links

- PyLate documentation: https://lightonai.github.io/pylate/
- PyLate API overview: https://lightonai.github.io/pylate/api/overview/
- PyLate ColBERT model API: https://lightonai.github.io/pylate/api/models/ColBERT/
- PyLate PLAID index API: https://lightonai.github.io/pylate/api/indexes/PLAID/
- PyLate retriever API: https://lightonai.github.io/pylate/api/retrieve/ColBERT/
- PyLate scoring API: https://lightonai.github.io/pylate/api/scores/colbert-scores
- pylate-rs documentation: https://lightonai.github.io/pylate-rs/
- NextPlaid documentation: https://lightonai.github.io/next-plaid/
- ragnar documentation: https://ragnar.tidyverse.org/
- ragnar retrieve reference: https://ragnar.tidyverse.org/reference/ragnar_retrieve.html
- ragnar store creation reference: https://ragnar.tidyverse.org/reference/ragnar_store_create.html
- ragnar markdown chunking reference: https://ragnar.tidyverse.org/reference/markdown_chunk.html
- reticulate Python requirements: https://rstudio.github.io/reticulate/reference/py_require.html
- reticulate package vignette: https://cran.r-project.org/web/packages/reticulate/vignettes/package.html
