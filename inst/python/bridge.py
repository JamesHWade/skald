def flatten_results(results, query_ids):
    """Normalize PyLate nested result lists to flat dictionaries."""
    out = []

    for query_pos, query_results in enumerate(results):
        query_id = query_ids[query_pos]

        for rank, item in enumerate(query_results, start=1):
            out.append(
                {
                    "query_id": query_id,
                    "rank": rank,
                    "id": item["id"],
                    "score": item["score"],
                }
            )

    return out
