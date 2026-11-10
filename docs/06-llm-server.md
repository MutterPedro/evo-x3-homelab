# 06 · The LLM server

## How requests flow

```
client ──► llama-swap :8080 ──► starts/stops one podman container per model
             │  API key, profiles,        (kyuz0 Strix Halo llama.cpp images)
             │  capacity router
             └─► /v1/chat/completions · /v1/messages (Anthropic) · /v1/embeddings
                 /v1/audio/transcriptions · /v1/audio/speech · /comfyui/
```

- **Models load on first request** (10–90 s depending on size; Open WebUI shows "loading…").
- **The capacity router** keeps several models resident as long as their `capacities.gpu` sum fits in the pool (112 GiB by default). When a new one doesn't fit, it unloads the ones that are cheapest to reload first (`evict_cost`).
- **Nothing unloads because of idleness** (it's a server), except whisper/TTS/ComfyUI, which free memory after 10–15 minutes.

## The models (Oct 2026 picks for 128 GB Strix Halo)

| ID | What | Memory | Expected speed* | Best for |
|---|---|---|---|---|
| `qwen3.8-flash-next` | Qwen3.8 Flash-Next 125B-A6B, UD-IQ4_XS, vision, **MTP** | ~100 GB | ~25 tok/s plain, ~45–55 with MTP | Hardest questions, coding agents, documents, images |
| `gpt-oss-120b` | OpenAI gpt-oss 120B (MXFP4) | ~68 GB | 35–55 tok/s | Reliable tool calling, reasoning. `:high` / `:low` variants set reasoning effort |
| `qwen3.6-35b-a3b` | Qwen3.6 35B-A3B UD-Q4_K_XL, vision | ~26 GB | ~60 tok/s, fast prefill | Coding agents, quick edits |
| `gemma-4-26b-a4b` | Gemma 4 26B-A4B QAT, vision | ~18 GB | 50–100 tok/s | Family chat, Portuguese, photos/screenshots, summaries |
| `qwen3-embedding-0.6b` | embeddings | ~2 GB | – | Open WebUI documents/knowledge (RAG) |
| `whisper-large-v3-turbo` | speech-to-text | ~2 GB | real-time+ | Voice input |
| `kokoro-tts` | text-to-speech (CPU) | 0 GPU | real-time | Voice output (`pf_dora` pt-BR, `af_heart` en) |
| `comfyui_auto` | ComfyUI (ROCm) | up to ~64 GB | – | Image / video generation |

\*From community benchmarks (Vulkan RADV, llama.cpp). Measure your own with `evo bench <id>`. Sources are in [00-hardware](00-hardware.md).

`qwen3.8-flash-next` also has a `:instruct` variant (thinking off, Qwen's recommended non-thinking sampling) for snappier replies.

## Profiles: the stable names clients use

Point every client at **`chat`, `code`, `vision` or `fast`**, never at a concrete model. Then `evo profile …` changes what's behind them without touching any client:

| Profile | chat | code | vision | fast | Typical resident set |
|---|---|---|---|---|---|
| **smart** (default) | Flash-Next | Flash-Next | Flash-Next | Flash-Next | Flash-Next (~104 GiB) + embeddings + whisper ≈ 110 GiB; nothing else big fits |
| **fast** | gpt-oss-120b | Qwen3.6 | Qwen3.6 | Qwen3.6 | gpt-oss + Qwen3.6 + helpers ≈ 100 GiB |
| **multi** | Gemma 4 | Qwen3.6 | Gemma 4 | Gemma 4 | ≈ 53 GiB, leaving ~60 GB for ComfyUI |

### Measured performance

Measured on the EVO-X3 (Bazzite 44, kernel 7.2, BIOS V1.01 Performance mode, GTT 120 GiB) with a ~10k-token Portuguese prompt, one request at a time, models loaded from cold. "GTT" is `mem_info_gtt_used` after the request; `capacities.gpu` is that plus ~2 GiB, **except for Flash-Next**, whose real footprint is ~104 GiB of host memory although GTT shows only 70 (see [10-operations](10-operations.md#out-of-memory-reboot-2026-11-10)). Size capacities from `MemTotal - MemAvailable`, not from GTT.

| Model | Backend | Prompt (tok/s) | Generation (tok/s) | GTT (GiB) |
|---|---|---|---|---|
| Qwen3.8 Flash-Next IQ4_XS + MTP, 128k ctx | Vulkan RADV | 441 | 34-38 | 70 |
| | ROCm 10.0 | 499 | 34 | 69 |
| gpt-oss-120b | Vulkan RADV | 942 | 36 | 66 |
| | ROCm 10.0 | 935 | 33 | 65 |
| Qwen3.6-35B-A3B | Vulkan RADV | 1409 | 58 | 24 |
| | ROCm 10.0 | 1534 | 51 | 24 |
| Gemma 4 26B-A4B | Vulkan RADV | 1523 | 62 | 19 |
| | ROCm 10.0 | 1534 | 56 | 19 |

Vulkan generates 5-15% faster on every model but Flash-Next (a tie); ROCm processes prompts up to 13% faster on the two models where it differs. Generation speed matters more for chat, so every model defaults to Vulkan. To try ROCm for one model, change `${vulkan}` to `${rocm}` in its `cmd`. Flash-Next's MTP draft accepts about 58% of drafted tokens.

The concrete IDs (`gpt-oss-120b:high`, etc.) stay available for anyone who wants a specific model. The default profile after a reboot is set by `EVO_DEFAULT_PROFILE`; `evo profile X` also persists across restarts.

## Connecting clients

API base: `http://evo-x3.local:8080/v1` · key: `evo secret api-key`

**Open WebUI** (`http://evo-x3.local:3000`) is already wired to llama-swap, SearXNG web search, embeddings, whisper and Kokoro. The default model is `chat`.

**Claude Code** (llama-swap speaks the Anthropic Messages API):

```bash
export ANTHROPIC_BASE_URL=http://evo-x3.local:8080
export ANTHROPIC_AUTH_TOKEN=<api key>
export ANTHROPIC_MODEL=code
export ANTHROPIC_DEFAULT_HAIKU_MODEL=fast   # used for quick background tasks
claude
```

**OpenAI-compatible tools** (Continue, Cline / Roo, opencode, Aider, Zed, LibreChat, n8n…). Use a "custom OpenAI" provider with:

```yaml
base_url: http://evo-x3.local:8080/v1
api_key:  <api key>
model:    code          # or chat / fast / vision
```

**curl test:**

```bash
curl http://evo-x3.local:8080/v1/chat/completions \
  -H "Authorization: Bearer $(evo secret api-key)" -H 'Content-Type: application/json' \
  -d '{"model":"fast","messages":[{"role":"user","content":"Olá! Quem é você?"}]}'
```

## Images and video (ComfyUI)

1. Download workflows' models once: `evo comfy models` (kyuz0's TUI: Qwen Image, Wan 2.2, LTX-2.3, HunyuanVideo…). They go into `~/ai/comfy/comfy-models`.
2. Open **`http://evo-x3.local:8080/comfyui/`**. The browser asks for credentials: any username, with the API key as the password. The first page load starts ComfyUI (~30 s).
3. ComfyUI unloads after 10 idle minutes. While it runs, the capacity router may unload big LLMs to make room (switch to `evo profile multi` to avoid ping-pong).

*Image generation inside Open WebUI* is optional. In *Admin Panel → Settings → Images*, choose **ComfyUI** with base URL `http://127.0.0.1:8080/comfyui` and paste a workflow exported from ComfyUI ("Export (API)"). This can't be pre-configured by the repo because the workflow depends on the models you download.

## Tuning for the best experience

| Knob | Where | Notes |
|---|---|---|
| Vulkan ↔ ROCm per model | `config/llama-swap/config.yaml.tmpl`: change `${vulkan}` to `${rocm}` in a model's `cmd` | RADV usually wins at generation, ROCm at long-prompt prefill. Try `evo bench <id>` both ways |
| Context length | `-c` per model | Bigger context means more KV memory. Raise `capacities.gpu` accordingly, or the router will over-commit |
| KV cache precision | `-ctk/-ctv q8_0` | Halves KV memory with negligible quality loss. `q4_0` for extreme contexts |
| Parallel requests | `--parallel N` | Each slot gets `ctx/N` tokens. MTP models use 1 slot |
| MTP speculative decoding | `--model-draft … --spec-type draft-mtp --spec-draft-n-max 3` | 1.3–1.7× speed on Qwen3.8. Try n-max 2–4 |
| Smaller Flash-Next | `evo models pull qwen3.8-flash-next-iq3` and point the model at `UD-IQ3_XXS` | 82 GB instead of 94, leaving room for gpt-oss alongside |
| GTT size | `EVO_GTT_GIB` in `evo.env` → `./install.sh system`, reboot | 120 is a good balance; 124 is the community max |
| Pool size | `EVO_GPU_POOL_GIB` → `./install.sh user` | Keep ~8 GiB below GTT |

### Adding a model

1. Add a line to `config/models.tsv` (HF repo + file patterns) and run `evo models pull <name>`.
2. Copy one of the model blocks in `config/llama-swap/config.yaml.tmpl`, then adjust the path, `-c`, sampling and `capacities.gpu` (≈ file size + KV + 2–4 GB).
3. `./install.sh user` and the model appears in `/v1/models` and Open WebUI.

Good sources for what's new: Unsloth's Hugging Face page, [local-llm-benchmarks.dev](https://local-llm-benchmarks.dev/), [llamaperf Strix Halo](https://llamaperf.com/gpu/strix-halo-128gb), r/LocalLLaMA, and the Strix Halo Home Lab Discord.

## Security notes

- **The API key protects everything on :8080** (API, llama-swap UI, ComfyUI). Never expose :8080 directly to the internet. Use Tailscale ([08-remote-access](08-remote-access.md)).
- Open WebUI has its own accounts. New sign-ups are *pending* until an admin approves them.
- Rotate the API key: edit `LLAMA_SWAP_KEY` in `~/.config/evo/secrets.env`, then `./install.sh user && systemctl --user restart llama-swap open-webui`. Old clients must be updated. Because Open WebUI keeps its connection settings in its database, also update the key in *Admin → Settings → Connections*.

➡ Next: [07-gaming](07-gaming.md)
