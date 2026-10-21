#!/usr/bin/env bash
# Download the Q8+ GGUF files for the three local llama.cpp servers
# (configs/hermes/config.yaml -> providers.llamacpp-supervl-q8, llamacpp-ultra-q8,
# llamacpp-glm-q8).
#
# Run this on the BIG box that will serve the models, not on the 8 GB laptop.
#
#   bash scripts/q8-local-fetch.sh supervl          download what is missing, then verify
#   bash scripts/q8-local-fetch.sh ultra --check    verify only; downloads nothing
#   bash scripts/q8-local-fetch.sh all              all three, one after another
#   Q8_DIR=/data/q8 bash scripts/q8-local-fetch.sh glm
#
# WHAT EACH ONE IS (every size and sha256 below was read from the Hugging Face tree API
# on 2026-10-21; each repo is pinned to one commit so the hashes cannot drift under you):
#
#   supervl  ggml-org/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-GGUF         133.7 GB  3 files
#            Q8_0 model (128.5 GB), vision projector Q8_0, MTP head Q8_0. The same weights
#            as the hosted primary, at Q8_0. There is NO Q8_K_XL for this model.
#   ultra    unsloth/NVIDIA-Nemotron-3-Ultra-550B-A55B-GGUF               594.5 GB  14 shards
#            UD-Q8_K_XL, the "Q8+" quant (plain Q8_0 is 584.3 GB; it shares shards 1-12).
#            Text only. Unsloth's page says MTP is not supported for GGUFs.
#   glm      unsloth/GLM-5.3-Flash-GGUF                                   342.1 GB  9 files
#            Q8_0 in 8 shards (341.0 GB) plus the F16 vision projector. Needs a llama.cpp
#            build that has the GLM-5.3-Flash architecture -- see scripts/q8-local-serve.sh.
#
# Total for all three: about 1,070 GB. The script checks free disk space before it starts
# and refuses if the remaining downloads will not fit (Q8_SKIP_DISK_CHECK=1 overrides).
#
# The files are public: no Hugging Face token is needed. Needs only curl, sha256sum, stat,
# df. Downloads resume (curl -C -), so an interrupted run is safe to repeat. A file is
# accepted only if its size AND sha256 match; a mismatch is reported and the file is left
# in place for you to inspect, never trusted. Shards keep their original names, because
# llama-server finds shards 2..N by the name of shard 1.
set -euo pipefail

DIR="${Q8_DIR:-$HOME/models/q8}"

# per model: repo and commit
REPO_supervl="ggml-org/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-GGUF"
REV_supervl="2950ece63f57a4a20d5bd0e5861e11f612f1a8da"
REPO_ultra="unsloth/NVIDIA-Nemotron-3-Ultra-550B-A55B-GGUF"
REV_ultra="2fb7d5b3f4eae7aedb18b4839b6a6300111e46f6"
REPO_glm="unsloth/GLM-5.3-Flash-GGUF"
REV_glm="a38483c8cd5df544f53d70fb281afe97369d5ab6"

# remote path|bytes|sha256     (the local file is the basename, in $DIR/<model>/)
FILES_supervl=(
  "NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf|128472993728|6349a29171cdc21c9f65816a86f71150f23d438c52f7d6da5b979f0546ee96bc"
  "mmproj-NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf|966925568|5687736375f1056b25441f07293ad043107fe8418ed62795da8cae1e61f0aa88"
  "mtp-NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf|4276991712|fe4564dd41d934446d8168c4d14a61c262e7b19618f953318ee049f59621f9c6"
)
FILES_ultra=(
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00001-of-00014.gguf|7872128|dbf47237532f9a91960d3e1727f3ec2e9bfcb6c102961b98b3a2b6617a6735f1"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00002-of-00014.gguf|44985737888|dece4d216c654ee1c0bf233dce5f844d13010131e7b4846485966eda43e8f975"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00003-of-00014.gguf|48497386208|d058e36722a9df4dccbb13c1fee1c4079782c971160f8f7e4cb62f9f8f545664"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00004-of-00014.gguf|48497386208|e7d94be9166d12e76f05cb2c2438fbf7e355f8e3df0754e4c07f04a9e050d7ab"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00005-of-00014.gguf|48497386208|b8a1becfb2bb850651bc9b81e7f037222de0d610c066d1fdd34df3d7cc5ba776"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00006-of-00014.gguf|48497386208|338e7f8709dc1bea888fdd75c4e86d72d386635edac902ada0e4c1a3c4f57c32"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00007-of-00014.gguf|48497386208|5f1af1c54bea0fa850bf058422f21f1f3dc5474ebe76dbc41248a010ab3d1578"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00008-of-00014.gguf|48497386208|319e7a0e7fdfd3160be01021a4ecab9fca3926955206c37fd825ee81e37b6ae4"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00009-of-00014.gguf|48497386208|d89b5eff152d4123c8d6ba836efa018fc7e81c5eeaf139621eaeddd6d039618c"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00010-of-00014.gguf|48497386208|2ac7c591f587da853a319acb77252abfffbc1554c8e08675b50a831540d24266"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00011-of-00014.gguf|48644482080|986030d67c3a0f32243be7beeadc175dea8de34e53ec559774ac762a40053c65"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00012-of-00014.gguf|48497386208|12f71dbfcdaa2dcab6f453ffc6325433f5443d6f5c89393d74bf2843a4f35c75"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00013-of-00014.gguf|42504478880|c935d95bc9c47bffa460d4caf9e22cf3b0dd262f86fc40f9e8c2bdbe82178e2e"
  "UD-Q8_K_XL/NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00014-of-00014.gguf|21894267488|09b78b4dbe62b4e0f499ab86649bce0da56cbe3ae71b22772069d582ed123d0f"
)
FILES_glm=(
  "Q8_0/GLM-5.3-Flash-Q8_0-00001-of-00008.gguf|9429984|5dc239a59cbd2d3b9d90b647cf697b80c0f4101bfaa2280b3102156e94a24ccf"
  "Q8_0/GLM-5.3-Flash-Q8_0-00002-of-00008.gguf|49665857344|8aabbbc0a92c551894f62a0737b433c9fad60a94baaa61e669f96329bb1d88a6"
  "Q8_0/GLM-5.3-Flash-Q8_0-00003-of-00008.gguf|49822821280|7b50941b404fed3413be4e0ca52af43e79113e4b3e2c940d1f4cdf74e95ebb39"
  "Q8_0/GLM-5.3-Flash-Q8_0-00004-of-00008.gguf|49849652064|ff27fb4536d524cae687c4fb88dfa1b43a8ee0b4256e55304f95dc1aa38e8b81"
  "Q8_0/GLM-5.3-Flash-Q8_0-00005-of-00008.gguf|49974608352|c088636854c5da312e44a7be4195cd765dd9eb6339d7b014d1da4192851a9b5b"
  "Q8_0/GLM-5.3-Flash-Q8_0-00006-of-00008.gguf|49840638624|4bece55cb9e98720f3ef2e1e9683983aeced77434dbcd54584c0b7c80a2e95cb"
  "Q8_0/GLM-5.3-Flash-Q8_0-00007-of-00008.gguf|49831834720|a9f792204b0b58155e6092f9a4160a0659fcdc98a1c126e563ecc3cd02ad68ad"
  "Q8_0/GLM-5.3-Flash-Q8_0-00008-of-00008.gguf|41987123840|a6cb6887c0047653f08c0ab6e564972451d9511322202970f7052e36052aefd6"
  "mmproj-F16.gguf|1128047296|922b809664d6a89cc1e40bfeaa63618000edc6651baf4082ce0718a784adf947"
)

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d'; }

CHECK_ONLY=0
TARGETS=()
for a in "$@"; do
  case "$a" in
    --check) CHECK_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    supervl|ultra|glm) TARGETS+=("$a") ;;
    all) TARGETS+=(supervl ultra glm) ;;
    *) echo "unknown argument: $a (supervl, ultra, glm, all, --check)" >&2; exit 2 ;;
  esac
done
[ "${#TARGETS[@]}" -gt 0 ] || { echo "name a model: supervl, ultra, glm or all (try --help)" >&2; exit 2; }

for tool in curl sha256sum stat df; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FAIL  $tool is not installed" >&2; exit 2; }
done

bad=0
checked=0

fetch_model() {
  local key="$1" repo rev
  local -n files="FILES_$key"
  repo="REPO_$key"; repo="${!repo}"
  rev="REV_$key";  rev="${!rev}"

  # Test hook (scripts/test_q8_local.py): a file of remote|bytes|sha256 lines replaces
  # the list above, so the logic can be exercised with tiny files instead of 1 TB.
  if [ -n "${Q8_MANIFEST:-}" ]; then
    mapfile -t files <"$Q8_MANIFEST"
  fi

  local dir="$DIR/$key"
  mkdir -p "$dir"

  # Refuse early if the rest cannot fit. A 594 GB download that dies at 560 GB on a full
  # disk wastes hours; the check costs one df call.
  if [ "$CHECK_ONLY" -eq 0 ] && [ "${Q8_SKIP_DISK_CHECK:-0}" != "1" ]; then
    local need=0 e remote want_bytes want_sha have name
    for e in "${files[@]}"; do
      IFS='|' read -r remote want_bytes want_sha <<<"$e"
      name="${remote##*/}"
      have=0; [ -f "$dir/$name" ] && have=$(stat -c %s "$dir/$name")
      [ "$have" -lt "$want_bytes" ] && need=$((need + want_bytes - have))
    done
    local avail
    avail=$(df -B1 --output=avail "$dir" | tail -n 1 | tr -d ' ')
    if [ "$need" -gt "$avail" ]; then
      echo "FAIL  $key needs $need more bytes but only $avail are free in $dir - free space, set Q8_DIR to a bigger disk, or Q8_SKIP_DISK_CHECK=1" >&2
      bad=$((bad + 1)); return
    fi
  fi

  local entry remote want_bytes want_sha name path have got_sha
  for entry in "${files[@]}"; do
    IFS='|' read -r remote want_bytes want_sha <<<"$entry"
    name="${remote##*/}"
    path="$dir/$name"
    have=0
    [ -f "$path" ] && have=$(stat -c %s "$path")

    if [ "$have" -ne "$want_bytes" ] && [ "$CHECK_ONLY" -eq 0 ]; then
      if [ "$have" -gt "$want_bytes" ]; then
        echo "FAIL  $name is $have bytes, larger than the expected $want_bytes - not resuming onto it; move it aside and rerun" >&2
        bad=$((bad + 1)); continue
      fi
      echo "get   $key/$name ($have of $want_bytes bytes present)"
      curl -fL --retry 5 --retry-delay 5 -C - -o "$path" \
        "https://huggingface.co/$repo/resolve/$rev/$remote"
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
    echo "ok    $key/$name ($want_bytes bytes, sha256 verified)"
    checked=$((checked + 1))
  done
}

for t in "${TARGETS[@]}"; do
  fetch_model "$t"
done

if [ "$bad" -ne 0 ]; then
  echo "FAILED  $bad problem(s); $checked file(s) verified" >&2
  exit 1
fi
echo "OK      $checked file(s) verified under $DIR"
echo "next:   bash scripts/q8-local-serve.sh <supervl|ultra|glm>"
