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


def colbert_tokens(model, texts, is_query=True):
    """Return ColBERT token metadata aligned to encoded token embeddings."""
    import torch

    if isinstance(texts, str):
        texts = [texts]

    texts = [str(text) for text in texts]
    features = model.tokenize(texts=texts, is_query=is_query)

    input_ids = features["input_ids"].detach().cpu()
    attention_mask = features.get("attention_mask")
    if attention_mask is None:
        attention_mask = torch.ones_like(input_ids, dtype=torch.long)
    attention_mask = attention_mask.detach().cpu()

    if is_query:
        if getattr(model, "do_query_expansion", False):
            keep_mask = torch.ones_like(input_ids, dtype=torch.bool)
        else:
            keep_mask = attention_mask.bool()
    else:
        skiplist_mask = model.skiplist_mask(input_ids=input_ids, skiplist=model.skiplist)
        keep_mask = torch.logical_and(skiplist_mask, attention_mask.bool())

    offsets = _colbert_offset_mappings(
        model=model,
        texts=texts,
        is_query=is_query,
        token_count=input_ids.shape[1],
    )

    tokenizer = model.tokenizer
    special_ids = set(getattr(tokenizer, "all_special_ids", []) or [])
    prefix_id = model.query_prefix_id if is_query else model.document_prefix_id
    pad_token_id = getattr(tokenizer, "pad_token_id", None)

    out = []
    for text_pos, token_ids in enumerate(input_ids.tolist()):
        tokens = tokenizer.convert_ids_to_tokens(token_ids)
        rows = []
        embedding_index = 0

        for token_pos, token_id in enumerate(token_ids):
            scored = bool(keep_mask[text_pos, token_pos].item())
            if scored:
                embedding_index += 1

            offset_start, offset_end = offsets[text_pos][token_pos]
            role = "content"
            if token_id == prefix_id:
                role = "prefix"
            elif token_id in special_ids:
                role = "special"

            rows.append(
                {
                    "token_index": token_pos + 1,
                    "embedding_index": embedding_index if scored else None,
                    "token_id": int(token_id),
                    "token": tokens[token_pos],
                    "offset_start": offset_start,
                    "offset_end": offset_end,
                    "attention": bool(attention_mask[text_pos, token_pos].item()),
                    "scored": scored,
                    "role": role,
                    "is_special": role in {"prefix", "special"},
                    "is_expansion": bool(
                        is_query
                        and getattr(model, "do_query_expansion", False)
                        and not bool(attention_mask[text_pos, token_pos].item())
                        and token_id == pad_token_id
                    ),
                }
            )

        out.append(rows)

    return out


def _colbert_offset_mappings(model, texts, is_query, token_count):
    """Return offsets matching ``model.tokenize()`` with PyLate's prefix token."""
    try:
        first = model._first_module()
        tokenizer = first.tokenizer
        max_length = model.query_length if is_query else model.document_length
        max_length = max_length - 1
        padding = "max_length" if is_query and model.do_query_expansion else False

        prepared = []
        shifts = []
        for text in texts:
            stripped = text.strip()
            shifts.append(len(text) - len(text.lstrip()))
            if getattr(first, "do_lower_case", False):
                stripped = stripped.lower()
            prepared.append(stripped)

        encoded = tokenizer(
            prepared,
            padding=padding,
            truncation="longest_first",
            return_offsets_mapping=True,
            max_length=max_length,
        )

        mappings = []
        for offsets, shift in zip(encoded["offset_mapping"], shifts):
            adjusted = []
            for start, end in offsets:
                if start == 0 and end == 0:
                    adjusted.append((None, None))
                else:
                    adjusted.append((int(start) + shift, int(end) + shift))

            adjusted = adjusted[:1] + [(None, None)] + adjusted[1:]
            adjusted = adjusted[:token_count]
            adjusted.extend([(None, None)] * (token_count - len(adjusted)))
            mappings.append(adjusted)

        return mappings
    except Exception:
        return [[(None, None)] * token_count for _ in texts]
