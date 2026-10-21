# Future project: fine-tune Super VL for instruct, reasoning, and coding + maths

Status: **not started** (parked 2026-10-21, on request). This note records what was
researched so the work can restart without redoing it. Nothing here is wired into
`configs/hermes/config.yaml`.

## The idea

Three LoRA adapters on `nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-BF16`, one per mode:

| Adapter | Trained with | Reward / target |
|---|---|---|
| instruct | `enable_thinking` off | short, correct answers |
| reasoning | `enable_thinking` on | concise, correct rationales |
| coding + maths | SFT, then RL | checkable: unit tests (`forge test` for Solidity), answer match for maths |

Super VL already has both modes in one set of weights (`enable_thinking` false is the
instruct mode; `medium_effort` sits between). Training is for quality and length on
specific tasks, not to add a missing capability.

## What the search found (2026-10-21)

- No ready-made coding, instruct or reasoning fine-tune of Super VL exists on Hugging Face
  (30 derivatives checked): only quants, speculative-decoding drafters, uncensored
  versions, and two domain LoRA merges (Fastino Finance, Healthcare; text-only,
  vision encoder dropped).
- Fastino's published recipe (vendor numbers, early-access checkpoint, single SFT seed):
  LoRA rank 32 on attention, Mamba, latent-projection and shared-expert weights (75.2M
  trainable, 0.06%); routed experts frozen; 2 epochs, batch 16, learning rate 1e-4 to 2e-4.
  500 FinQA rows took FinQA from 35.2% to 77.2% in 15 minutes. Maths RL (Tinker
  `math_rl` recipe, 40 steps) took MATH-500 from 84.5% to 91.4% and cut output 25%.
- Their lessons that matter here: mix skills so a narrow adapter does not drag a
  neighbouring task (TAT-QA fell 5.5 to 17.7 points); keep the chat template identical
  between training and serving, including the thinking flag; the base sometimes emits
  several JSON tool calls in one message, which matters for Hermes.

## Getting the weights right

- Train on BF16 (248.9 GB, 124.45B parameters). A GGUF is a serving format, not a
  training one. Pipeline: BF16 + LoRA, merge, convert, quantize to Q8_0.
- **There is no Q8_K_XL for Super VL.** Largest quants: Q8_0 131.6 GB (unsloth, four
  shards), Q8_0 128.5 GB (ggml-org, one file, plus 1.0 GB mmproj and 4.3 GB MTP head).
  UD-Q8_K_XL exists only for Ultra (594.5 GB).
- The ggml-org and unsloth GGUFs are made from the post-trained BF16 and embed a
  12,927-character chat template that mentions `enable_thinking` and `medium_effort`.
  The pretrain-only checkpoint is a separate repo (`...-Base-BF16`); do not use it.
- Ultra 550B-A55B: Q8_0 584 GB, BF16 about 1.12 TB. GLM-5.3 Flash: Q8_0 341 GB,
  BF16 642 GB.

## Cost and size of the work

- Hosted (Fastino Training API, list $0.96 per million training tokens): $21-43 and
  2-5.5 hours on one B200 per full adapter. Six runs (3 adapters x 2) is about
  $126-258; nine about $189-387.
- Self-run with Unsloth (free software; Pro and Enterprise are "Contact us"): Unsloth's
  text-only Nemotron 3 Super page says BF16 LoRA works on 256 GB of VRAM, which is two
  B200s. At the Oct 2026 median of $7.99 per GPU-hour (range about $4-9) that is
  roughly $24-88 per run, so six runs about $144-528. Hours are borrowed from Fastino's
  numbers, not measured on Unsloth. Unsloth documents Super VL for running only;
  fine-tuning of the VL path is unconfirmed.
- Neither figure includes debugging, evaluation inference or RL rollouts.

## Runs

Two runs per adapter, changed in the way that helps: learning rate 1x vs 2x for SFT,
two seeds for RL. A third run only for RL if the first two differ by more than the
eval's noise. Choose by held-out score, not training loss.

## Preconditions before starting

1. **A real eval.** About 200 held-out items per adapter plus an untouched neighbour
   benchmark. At 80% accuracy and n = 200 the standard error is about 2.8 points, so a
   20-question eval cannot rank two runs.
2. **Data decision.** Open datasets only, or the maintainers' own Solidity/TypeScript.
   Own code sent to a hosted trainer leaves their hands. Training data must never be
   committed to this repo.
3. **A serving plan** for the result (Q8_0 base, adapters merged or loaded with
   `--lora`; multi-adapter serving is unverified for this architecture).
4. **The licence.** The base is "other", not Apache. Read what it allows for derivative
   models before publishing one.

## Not verified

- Whether Tinker, NeMo RL or Unsloth supports the VL path of this model.
- Whether LoRA hot-swap works on the Q8_0 GGUF.
- Fastino's current pricing ("special pricing for a limited time").
- Anything on a real `llama-server` or a real Hermes install.

## Sources

- Fastino, "Big Model, Small Adapter" (2026-10-15): fastino.ai/blog/nvidia-nemotron-3-5-super-vl-fine-tuning
- Fastino Finance model card: huggingface.co/fastino/Fastino-Nemotron-3.5-Super-VL-Finance
- NVIDIA Super VL BF16 card: huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-BF16
- ggml-org and unsloth Super VL GGUF repos; unsloth Ultra and GLM-5.3-Flash GGUF repos
- Unsloth pricing and Nemotron docs: unsloth.ai/pricing, unsloth.ai/docs/models/nemotron-3/nemotron-3-super
- B200 rental prices: getdeploying.com/gpus/nvidia-b200, computeprices.com/gpus/b200
