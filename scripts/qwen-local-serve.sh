#!/usr/bin/env bash
# Serve Qwen3.8-27B Q8_0 (with vision and speculative decoding) with llama.cpp, for
# fallback 3 in configs/hermes/config.yaml (providers.llamacpp-qwen).
#
# Run on the BIG box, after scripts/qwen-local-fetch.sh. Then, on the laptop that runs
# Hermes, open the tunnel and leave it open:
#
#     ssh -N -L 8081:127.0.0.1:8080 -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 <user>@<box>
#
#   bash scripts/qwen-local-serve.sh                  MTP speculative decoding (default)
#   bash scripts/qwen-local-serve.sh --spec dflash    DFlash drafter instead
#   bash scripts/qwen-local-serve.sh --spec none      no speculation
#   bash scripts/qwen-local-serve.sh --dry-run        print the command, start nothing
#
# MTP and DFlash are ALTERNATIVES: this runs one. Both are output-equivalent to plain
# decoding (the target model verifies every token), so the choice is speed only. On a
# bandwidth-bound box a dense 27B at Q8 reads 28.6 GB per token; speculation is what
# lifts the ceiling. One third-party Jetson AGX Thor test reported MTP at depth 3 taking
# Qwen3.8-27B from about 13 to 35 tokens/s; an ik_llama.cpp test on a GPU measured MTP
# ahead of DFlash for a 27B. Neither is a measurement of THIS box -- time your own.
#
# LOOPBACK ONLY. There is no API key on this server, so it binds 127.0.0.1 and refuses
# any other host. The SSH tunnel is the access control.
#
# The flags below follow the speculative-decoding page in llama.cpp's own docs (DFlash) and its MTP sidecar
# shape (`--spec-type draft-mtp` plus `--model-draft <head>`); the spelling has changed
# between llama.cpp builds, so the script asks the binary before it starts (see
# --no-preflight). It has not been run against a real llama-server by the author.
set -euo pipefail

DIR="${QWEN_DIR:-$HOME/models/qwen3.8-27b}"
# ALIAS and CTX must equal providers.llamacpp-qwen.default_model and .context_length in
# configs/hermes/config.yaml. CI compares them; change all three together.
ALIAS="${QWEN_ALIAS:-qwen3.8-27b-q8}"
CTX="${QWEN_CTX:-262144}"
HOST="${QWEN_HOST:-127.0.0.1}"
PORT="${QWEN_PORT:-8080}"
LLAMA_SERVER="${LLAMA_SERVER:-llama-server}"

SPEC="mtp"
DRY=0
PREFLIGHT=1
while [ $# -gt 0 ]; do
  case "$1" in
    --spec)
      [ $# -ge 2 ] || { echo "--spec needs mtp, dflash or none" >&2; exit 2; }
      SPEC="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --no-preflight) PREFLIGHT=0; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

case "$SPEC" in mtp|dflash|none) ;; *) echo "FAIL  --spec must be mtp, dflash or none, not '$SPEC'" >&2; exit 2 ;; esac

case "$HOST" in
  127.0.0.1|localhost|::1) ;;
  *) echo "FAIL  QWEN_HOST=$HOST: this server has no API key, so it must bind loopback and be reached over an SSH tunnel" >&2; exit 2 ;;
esac

MODEL="$DIR/Qwen3.8-27B-Q8_0.gguf"
MMPROJ="$DIR/mmproj-Qwen3.8-27B-Q8_0.gguf"
MTP="$DIR/mtp-Qwen3.8-27B-Q8_0.gguf"
DFLASH="$DIR/dflash-Qwen3.8-27B-Q8_0.gguf"

need=("$MODEL" "$MMPROJ")
[ "$SPEC" = "mtp" ] && need+=("$MTP")
[ "$SPEC" = "dflash" ] && need+=("$DFLASH")
for f in "${need[@]}"; do
  [ -f "$f" ] || { echo "FAIL  missing $f - run: bash scripts/qwen-local-fetch.sh" >&2; exit 2; }
done

args=(
  -m "$MODEL"
  --mmproj "$MMPROJ"
  --alias "$ALIAS"
  -c "$CTX"
  -np 1
  -ngl 99
  -fa on
  --jinja
  --host "$HOST"
  --port "$PORT"
)
case "$SPEC" in
  mtp)    args+=(--spec-type draft-mtp --model-draft "$MTP" --spec-draft-n-max 3) ;;
  dflash) args+=(--spec-type draft-dflash --model-draft "$DFLASH" --spec-draft-n-max 8) ;;
esac

if [ "$PREFLIGHT" -eq 1 ] && [ "$DRY" -eq 0 ]; then
  command -v "$LLAMA_SERVER" >/dev/null 2>&1 || { echo "FAIL  $LLAMA_SERVER not found - build llama.cpp (CUDA) or set LLAMA_SERVER=/path/to/llama-server" >&2; exit 2; }
  help_text="$("$LLAMA_SERVER" --help 2>&1 || true)"
  for flag in --mmproj --alias --jinja; do
    grep -q -- "$flag" <<<"$help_text" || { echo "FAIL  this llama-server does not list $flag - update llama.cpp (or pass --no-preflight if you know better)" >&2; exit 2; }
  done
  case "$SPEC" in
    mtp)    want='draft-mtp' ;;
    dflash) want='draft-dflash' ;;
    *)      want='' ;;
  esac
  if [ -n "$want" ]; then
    grep -q -- '--spec-type' <<<"$help_text" && grep -q -- "$want" <<<"$help_text" || {
      echo "FAIL  this llama-server does not list '--spec-type $want' - update llama.cpp, or run with --spec none" >&2; exit 2; }
  fi
fi

echo "serving $ALIAS on $HOST:$PORT  ctx=$CTX  spec=$SPEC"
if [ "$DRY" -eq 1 ]; then
  printf '%q ' "$LLAMA_SERVER" "${args[@]}"; echo
  exit 0
fi
exec "$LLAMA_SERVER" "${args[@]}"
