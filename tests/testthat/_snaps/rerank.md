# skald_rerank reports score column conflicts

    Code
      skald_rerank(candidates, model, query = "q", text = text)
    Condition
      Error in `.skald_column_exists_abort()`:
      ! Column late_score already exists.
      i Set `score_col` to a different name.

