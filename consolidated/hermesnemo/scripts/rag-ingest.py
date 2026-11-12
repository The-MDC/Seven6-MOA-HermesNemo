#!/usr/bin/env python3
"""
RAG Ingestion Pipeline for Seven6-MoA DeepSeek-V2 Advisor
Scans ./rag-corpus/ for documents, chunks them, embeds with BAAI/bge-m3,
and writes a FAISS index + metadata JSONL to ./scratch/rag-index/
"""

import json
import os
import sys
from pathlib import Path

CORPUS_DIR = Path(__file__).resolve().parent.parent / "rag-corpus"
INDEX_DIR = Path(__file__).resolve().parent.parent / "scratch" / "rag-index"
CHUNK_SIZE = 512  # tokens (approx chars for fallback)
CHUNK_OVERLAP = 50
EMBEDDING_MODEL = "BAAI/bge-m3"


def read_document(path: Path) -> str:
    """Read a document, supporting .md, .txt, .pdf."""
    suffix = path.suffix.lower()
    if suffix in (".md", ".txt"):
        return path.read_text(encoding="utf-8")
    elif suffix == ".pdf":
        try:
            import PyPDF2
            reader = PyPDF2.PdfReader(str(path))
            return "\n".join(page.extract_text() or "" for page in reader.pages)
        except ImportError:
            print(f"WARNING: PyPDF2 not installed, skipping {path}", file=sys.stderr)
            return ""
    else:
        print(f"WARNING: Unsupported file type {suffix}, skipping {path}", file=sys.stderr)
        return ""


def chunk_text(text: str, size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[str]:
    """Simple character-based chunking (token-approx)."""
    if not text:
        return []
    chunks = []
    start = 0
    while start < len(text):
        end = min(start + size, len(text))
        chunks.append(text[start:end])
        if end >= len(text):
            break
        start = end - overlap
    return chunks


def main():
    INDEX_DIR.mkdir(parents=True, exist_ok=True)

    # Collect documents
    docs = []
    if not CORPUS_DIR.exists():
        print(f"Corpus dir {CORPUS_DIR} does not exist. Creating empty.")
        CORPUS_DIR.mkdir(parents=True, exist_ok=True)

    for f in sorted(CORPUS_DIR.rglob("*")):
        if f.is_file():
            text = read_document(f)
            if text.strip():
                docs.append({"path": str(f.relative_to(CORPUS_DIR)), "text": text})

    print(f"Found {len(docs)} documents in {CORPUS_DIR}")

    # Chunk all documents
    all_chunks = []
    for doc in docs:
        chunks = chunk_text(doc["text"])
        for i, chunk in enumerate(chunks):
            all_chunks.append({
                "doc": doc["path"],
                "chunk_index": i,
                "text": chunk,
            })

    print(f"Created {len(all_chunks)} chunks")

    if not all_chunks:
        print("No chunks to index. Exiting.")
        return

    # Embed with BAAI/bge-m3
    try:
        from sentence_transformers import SentenceTransformer
    except ImportError:
        print("ERROR: sentence-transformers not installed. Run: pip install sentence-transformers")
        sys.exit(1)

    print(f"Loading embedding model: {EMBEDDING_MODEL}")
    model = SentenceTransformer(EMBEDDING_MODEL)

    texts = [c["text"] for c in all_chunks]
    print(f"Embedding {len(texts)} chunks...")
    embeddings = model.encode(texts, show_progress_bar=True, convert_to_numpy=True)

    # Build FAISS index
    try:
        import faiss
    except ImportError:
        print("ERROR: faiss-cpu not installed. Run: pip install faiss-cpu")
        sys.exit(1)

    dim = embeddings.shape[1]
    index = faiss.IndexFlatIP(dim)  # inner product for cosine similarity
    faiss.normalize_L2(embeddings)
    index.add(embeddings)

    # Write index
    index_path = INDEX_DIR / "index.faiss"
    faiss.write_index(index, str(index_path))
    print(f"FAISS index written to {index_path}")

    # Write metadata JSONL
    meta_path = INDEX_DIR / "metadata.jsonl"
    with open(meta_path, "w", encoding="utf-8") as f:
        for c in all_chunks:
            f.write(json.dumps(c, ensure_ascii=False) + "\n")
    print(f"Metadata written to {meta_path}")

    print("RAG ingestion complete.")


if __name__ == "__main__":
    main()
