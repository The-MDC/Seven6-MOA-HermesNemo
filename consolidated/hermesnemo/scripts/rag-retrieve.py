#!/usr/bin/env python3
"""
RAG Retrieval for Seven6-MoA DeepSeek-V2 Advisor
Loads FAISS index + metadata, embeds query with BAAI/bge-m3,
returns top-k passages concatenated as a context block.
"""

import json
import sys
from pathlib import Path

INDEX_DIR = Path(__file__).resolve().parent.parent / "scratch" / "rag-index"
EMBEDDING_MODEL = "BAAI/bge-m3"
TOP_K = 5


def retrieve(query: str, top_k: int = TOP_K) -> str:
    index_path = INDEX_DIR / "index.faiss"
    meta_path = INDEX_DIR / "metadata.jsonl"

    if not index_path.exists() or not meta_path.exists():
        return ""

    try:
        import faiss
    except ImportError:
        print("WARNING: faiss-cpu not installed", file=sys.stderr)
        return ""

    try:
        from sentence_transformers import SentenceTransformer
    except ImportError:
        print("WARNING: sentence-transformers not installed", file=sys.stderr)
        return ""

    index = faiss.read_index(str(index_path))
    model = SentenceTransformer(EMBEDDING_MODEL)

    # Load metadata
    with open(meta_path, "r", encoding="utf-8") as f:
        metadata = [json.loads(line) for line in f if line.strip()]

    # Embed query
    q_emb = model.encode([query], convert_to_numpy=True)
    faiss.normalize_L2(q_emb)

    # Search
    scores, indices = index.search(q_emb, min(top_k, len(metadata)))

    passages = []
    for idx in indices[0]:
        if idx == -1 or idx >= len(metadata):
            continue
        passages.append(metadata[idx]["text"])

    if not passages:
        return ""

    context = "\n\n---\n\n".join(passages)
    return context


if __name__ == "__main__":
    query = sys.argv[1] if len(sys.argv) > 1 else ""
    if not query:
        print("Usage: python rag-retrieve.py <query>")
        sys.exit(1)
    context = retrieve(query)
    print(context)
