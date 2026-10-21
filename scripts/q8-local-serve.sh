#!/usr/bin/env bash
# Serve one of the three Q8+ models with llama.cpp, for the loopback providers in
# configs/hermes/config.yaml (providers.llamacpp-supervl-q8, llamacpp-ultra-q8,
# llamacpp-glm-q8).
#
# Run on the BIG box, after scripts/q8-local-fetch.sh. Then, on the laptop that runs
# Hermes, open the tunnel for that model and leave it open. Local and remote port are the
# same number, one per model, so all three tunnels can be open at once:
#
#     ssh -N -L 8082:127.0.0.1:8082 -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 <user>@<box>   # supervl
#     ssh -N -L 8083:127.0.0.1:8083 ...                                                                # ultra
#     ssh -N -L 8084:127.0.0.1:8084 ...                                                                # glm
#
#   bash scripts/q8-local-serve.sh supervl               Nemotron 3.5 Super VL 120B, Q8_0, vision
#   bash scripts/q8-local-serve.sh ultra                 Nemotron 3 Ultra 550B, UD-Q8_K_XL, text only
#   bash scripts/q8-local-serve.sh glm                   GLM-5.3-Flash, Q8_0, vision (needs the fork build)
#   bash scripts/q8-local-serve.sh supervl --spec mtp    add the MTP head (supervl only; see below)
#   bash scripts/q8-local-serve.sh <model> --dry-run     print the command, start nothing
#   bash scripts/q8-local-serve.sh <model> --print       print alias / context / port, nothing else
#   bash scripts/q8-local-serve.sh <model> -- -ts 1,1,1,1    anything after `--` goes to llama-server
#
# WHICH llama.cpp (read this before glm):
#   supervl  mainline llama.cpp; ggml-org publishes the GGUFs and their own run line is
#            `llama serve -hf ggml-org/...`.
#   ultra    mainline llama.cpp; Unsloth's guide builds a plain clone and runs llama-server.
#            Unsloth also says MTP is NOT supported for the Ultra GGUFs, so there is no --spec.
#   glm      NOT mainline as far as the Unsloth page (read 2026-10-21) shows. It says to build
#            their branch: git clone --branch glm5next/upstream https://github.com/unslothai/llama.cpp
#            (ggml-org/llama.cpp PR 27754 is the upstream route; its state was not checked).
#            Point LLAMA_SERVER at that build. This script cannot tell whether a binary knows
#            the architecture; a binary that does not will exit with an unknown-architecture
#            error as soon as it opens the file.
#
# --spec mtp (supervl only): ggml-org ships mtp-...-Q8_0.gguf next to the model. The flags
# are the sidecar shape the Qwen script uses (`--spec-type draft-mtp --model-draft <head>`)
# and have NOT been run against this model; default is no speculation. The preflight greps
# the binary's --help for the flag. MTP, where it works, is output-equivalent: the target
# verifies every token, so it changes speed, not answers.
#
# LOOPBACK ONLY. There is no API key on these servers, so each binds 127.0.0.1 and the
# script refuses any other host. The SSH tunnel is the access control.
#
# SAMPLING. NVIDIA's cards for both Nemotron models and the GLM card say temperature 1.0,
# top_p 0.95; the script sets them as the server defaults. A request that sends its own
# values wins. Thinking mode is left to the chat template's default; Hermes can send
# chat_template_kwargs per request.
#
# MEMORY, from the file sizes (not a measurement of any box): supervl 133.7 GB, ultra
# 594.5 GB, glm 342.1 GB on disk, plus KV cache and compute buffers. All three at once is
# about 1,070 GB before those. Context is 131072 for all three (the primary's window, so a
# fallback can take over a session without truncating it); it is a choice, not a limit.
set -euo pipefail

MODEL_KEY=""
SPEC="none"
DRY=0
PRINT=0
PREFLIGHT=1
EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    supervl|ultra|glm) MODEL_KEY="$1"; shift ;;
    --spec)
      [ $# -ge 2 ] || { echo "--spec needs mtp or none" >&2; exit 2; }
      SPEC="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --print) PRINT=1; shift ;;
    --no-preflight) PREFLIGHT=0; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) echo "unknown argument: $1 (supervl, ultra, glm, --spec, --dry-run, --print, --no-preflight, -- ...)" >&2; exit 2 ;;
  esac
done
[ -n "$MODEL_KEY" ] || { echo "name a model: supervl, ultra or glm (try --help)" >&2; exit 2; }

case "$SPEC" in mtp|none) ;; *) echo "FAIL  --spec must be mtp or none, not '$SPEC'" >&2; exit 2 ;; esac
if [ "$SPEC" = "mtp" ] && [ "$MODEL_KEY" != "supervl" ]; then
  echo "FAIL  --spec mtp is only wired for supervl: ultra's GGUFs have no MTP support (Unsloth), and glm's MTP flag spelling is unverified - pass it yourself after --" >&2
  exit 2
fi

BASE="${Q8_DIR:-$HOME/models/q8}"
DIR="$BASE/$MODEL_KEY"
LLAMA_SERVER="${LLAMA_SERVER:-llama-server}"
HOST="${Q8_HOST:-127.0.0.1}"

# ALIAS, CTX and PORT must equal providers.<provider>.default_model / context_length / the
# port in .api in configs/hermes/config.yaml. CI compares them (scripts/test_q8_local.py);
# change all of them together. The alias is the model id Hermes sends; it belongs to this
# gateway, not to Hugging Face or NVIDIA (rule 1 in CLAUDE.md).
MMPROJ=""
MTP=""
case "$MODEL_KEY" in
  supervl)
    ALIAS_DEFAULT="nemotron-3.5-super-vl-120b-a12b-q8"; CTX_DEFAULT=131072; PORT_DEFAULT=8082
    MODEL="$DIR/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf"
    MMPROJ="$DIR/mmproj-NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf"
    MTP="$DIR/mtp-NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf"
    SHARDS=1 ;;
  ultra)
    ALIAS_DEFAULT="nemotron-3-ultra-550b-a55b-q8"; CTX_DEFAULT=131072; PORT_DEFAULT=8083
    MODEL="$DIR/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00001-of-00014.gguf"
    SHARDS=14 ;;
  glm)
    ALIAS_DEFAULT="glm-5.3-flash-q8"; CTX_DEFAULT=131072; PORT_DEFAULT=8084
    MODEL="$DIR/GLM-5.3-Flash-Q8_0-00001-of-00008.gguf"
    MMPROJ="$DIR/mmproj-F16.gguf"
    SHARDS=8 ;;
esac
ALIAS="${Q8_ALIAS:-$ALIAS_DEFAULT}"
CTX="${Q8_CTX:-$CTX_DEFAULT}"
PORT="${Q8_PORT:-$PORT_DEFAULT}"

if [ "$PRINT" -eq 1 ]; then
  echo "KEY=$MODEL_KEY"
  echo "ALIAS=$ALIAS"
  echo "CTX=$CTX"
  echo "PORT=$PORT"
  exit 0
fi

case "$HOST" in
  127.0.0.1|localhost|::1) ;;
  *) echo "FAIL  Q8_HOST=$HOST: this server has no API key, so it must bind loopback and be reached over an SSH tunnel" >&2; exit 2 ;;
esac

# Every shard must be present: llama-server opens shard 1 and fails late and obscurely if a
# later one is missing. Shard names are NAME-0000N-of-0000M.gguf; check them all by number.
need=("$MODEL")
[ -n "$MMPROJ" ] && need+=("$MMPROJ")
[ "$SPEC" = "mtp" ] && need+=("$MTP")
if [ "$SHARDS" -gt 1 ]; then
  prefix="${MODEL%-00001-of-*}"
  total=$(printf '%05d' "$SHARDS")
  for i in $(seq 2 "$SHARDS"); do
    need+=("$prefix-$(printf '%05d' "$i")-of-$total.gguf")
  done
fi
for f in "${need[@]}"; do
  [ -f "$f" ] || { echo "FAIL  missing $f - run: bash scripts/q8-local-fetch.sh $MODEL_KEY" >&2; exit 2; }
done

args=(-m "$MODEL")
[ -n "$MMPROJ" ] && args+=(--mmproj "$MMPROJ")
args+=(
  --alias "$ALIAS"
  -c "$CTX"
  -np 1
  -ngl 99
  -fa on
  --jinja
  --temp 1.0
  --top-p 0.95
  --host "$HOST"
  --port "$PORT"
)
[ "$SPEC" = "mtp" ] && args+=(--spec-type draft-mtp --model-draft "$MTP" --spec-draft-n-max 3)
[ "${#EXTRA[@]}" -gt 0 ] && args+=("${EXTRA[@]}")

if [ "$PREFLIGHT" -eq 1 ] && [ "$DRY" -eq 0 ]; then
  command -v "$LLAMA_SERVER" >/dev/null 2>&1 || { echo "FAIL  $LLAMA_SERVER not found - build llama.cpp (CUDA) or set LLAMA_SERVER=/path/to/llama-server" >&2; exit 2; }
  help_text="$("$LLAMA_SERVER" --help 2>&1 || true)"
  flags=(--alias --jinja)
  [ -n "$MMPROJ" ] && flags+=(--mmproj)
  for flag in "${flags[@]}"; do
    grep -q -- "$flag" <<<"$help_text" || { echo "FAIL  this llama-server does not list $flag - update llama.cpp (or pass --no-preflight if you know better)" >&2; exit 2; }
  done
  if [ "$SPEC" = "mtp" ]; then
    grep -q -- '--spec-type' <<<"$help_text" && grep -q -- 'draft-mtp' <<<"$help_text" || {
      echo "FAIL  this llama-server does not list '--spec-type draft-mtp' - update llama.cpp, or run without --spec mtp" >&2; exit 2; }
  fi
  if [ "$MODEL_KEY" = "glm" ]; then
    echo "note  glm needs a llama.cpp build with the GLM-5.3-Flash architecture (Unsloth's glm5next/upstream branch); this check cannot see that" >&2
  fi
fi

echo "serving $ALIAS on $HOST:$PORT  ctx=$CTX  spec=$SPEC"
if [ "$DRY" -eq 1 ]; then
  printf '%q ' "$LLAMA_SERVER" "${args[@]}"; echo
  exit 0
fi
exec "$LLAMA_SERVER" "${args[@]}"
