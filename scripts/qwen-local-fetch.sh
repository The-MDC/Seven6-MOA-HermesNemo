#!/usr/bin/env bash
# Download Qwen3.8-27B (Q8_0) and its three companion files for the llama.cpp server
# behind fallback 4 (configs/hermes/config.yaml -> providers.llamacpp-qwen).
#
# Run this on the BIG box that will serve the model, not on the 8 GB laptop.
#
#   bash scripts/qwen-local-fetch.sh              download what is missing, then verify
#   bash scripts/qwen-local-fetch.sh --check      verify only; downloads nothing
#   QWEN_DIR=/data/qwen bash scripts/qwen-local-fetch.sh
#
# WHAT IT FETCHES (ggml-org/Qwen3.8-27B-GGUF, pinned to one commit so the hashes below
# cannot drift under you; sizes and sha256 read from the Hub on 2026-10-21):
#   Qwen3.8-27B-Q8_0.gguf          the model, 28,595,763,648 B
#   mmproj-Qwen3.8-27B-Q8_0.gguf   vision encoder,  629,247,008 B
#   mtp-Qwen3.8-27B-Q8_0.gguf      MTP speculative head, 3,164,006,816 B
#   dflash-Qwen3.8-27B-Q8_0.gguf   DFlash drafter, 2,056,414,560 B
# Total about 34.4 GB. The files are public: no Hugging Face token is needed.
#
# Needs only curl and sha256sum. Downloads resume (curl -C -), so an interrupted run is
# safe to repeat. A file is accepted only if its size AND sha256 match; a mismatch is
# reported and the file is left in place for you to inspect, never trusted.
set -euo pipefail

REPO="ggml-org/Qwen3.8-27B-GGUF"
REV="a316ea527fde32c12487be7574e2db5ac2ad2a7e"
DIR="${QWEN_DIR:-$HOME/models/qwen3.8-27b}"

# name|bytes|sha256
FILES=(
  "Qwen3.8-27B-Q8_0.gguf|28595763648|aab65c67ef0dad127960efef9247f1832bca105faa1c7a052cc039b223cf86a1"
  "mmproj-Qwen3.8-27B-Q8_0.gguf|629247008|2e968a6af97ce35d8971890b257b9b7edabf20ad91450501fa53162a19ee33eb"
  "mtp-Qwen3.8-27B-Q8_0.gguf|3164006816|6447a4e9d29fa6eba89ed508b2127b0803f91bac3ec6cec725fa209f2c3d309d"
  "dflash-Qwen3.8-27B-Q8_0.gguf|2056414560|ef6a1340ed018cc58f53efd3613312c719b9ebf72b5586a046214c7ba366b297"
)

# Test hook (scripts/test_qwen_local.py): a file of name|bytes|sha256 lines replaces the
# list above, so the logic can be exercised with tiny files instead of 34 GB.
if [ -n "${QWEN_MANIFEST:-}" ]; then
  mapfile -t FILES <"$QWEN_MANIFEST"
fi

CHECK_ONLY=0
for a in "$@"; do
  case "$a" in
    --check) CHECK_ONLY=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "unknown argument: $a (try --help)" >&2; exit 2 ;;
  esac
done

for tool in curl sha256sum stat; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FAIL  $tool is not installed" >&2; exit 2; }
done

mkdir -p "$DIR"
bad=0

for entry in "${FILES[@]}"; do
  IFS='|' read -r name want_bytes want_sha <<<"$entry"
  path="$DIR/$name"
  have=0
  [ -f "$path" ] && have=$(stat -c %s "$path")

  if [ "$have" -ne "$want_bytes" ] && [ "$CHECK_ONLY" -eq 0 ]; then
    if [ "$have" -gt "$want_bytes" ]; then
      echo "FAIL  $name is $have bytes, larger than the expected $want_bytes - not resuming onto it; move it aside and rerun" >&2
      bad=$((bad + 1)); continue
    fi
    echo "get   $name ($have of $want_bytes bytes present)"
    curl -fL --retry 5 --retry-delay 5 -C - -o "$path" \
      "https://huggingface.co/$REPO/resolve/$REV/$name"
    have=$(stat -c %s "$path")
  fi

  if [ "$have" -ne "$want_bytes" ]; then
    echo "FAIL  $name is $have bytes, expected $want_bytes" >&2
    bad=$((bad + 1)); continue
  fi
  if [ "$(head -c 4 "$path")" != "GGUF" ]; then
    echo "FAIL  $name does not start with the GGUF magic bytes" >&2
    bad=$((bad + 1)); continue
  fi
  got_sha=$(sha256sum "$path" | cut -d' ' -f1)
  if [ "$got_sha" != "$want_sha" ]; then
    echo "FAIL  $name sha256 $got_sha, expected $want_sha - the file is corrupt or the pin is stale" >&2
    bad=$((bad + 1)); continue
  fi
  echo "ok    $name ($want_bytes bytes, sha256 verified)"
done

if [ "$bad" -ne 0 ]; then
  echo "FAILED  $bad file(s) did not verify" >&2
  exit 1
fi
echo "OK      all ${#FILES[@]} files verified in $DIR"
echo "next:   bash scripts/qwen-local-serve.sh"
