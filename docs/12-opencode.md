# 12 · opencode (terminal coding agent)

[opencode](https://opencode.ai) is a coding agent for the terminal. It talks to the local llama-swap API, so code never leaves the house.

## Setup

1. Install opencode (see its site; it is not part of `./install.sh`).
2. Copy the provider config and export the API key (it stays out of the file, so the file is safe to share):

```bash
mkdir -p ~/.config/opencode
cp config/opencode/opencode.json ~/.config/opencode/opencode.json
echo "export EVO_API_KEY=$(evo secret api-key)" >> ~/.zshrc     # or ~/.bashrc
```

3. Start `opencode` and pick **Local (llama-swap)** → a model. `qwen3.6-35b-a3b` is the quick coder, `qwen3.8-flash-next` the best one.

From another machine, change `baseURL` to `http://evo-x3.local:8080/v1` (or `http://evo-x3:8080/v1` over Tailscale).

## What the config says

- `providers.llama`: an OpenAI-compatible provider pointing at llama-swap on `:8080`; `apiKey` is read from `$EVO_API_KEY`.
- One entry per chat model, with the capabilities (tools, image input) and `limit.context`. Each limit is the model's `-c` divided by its `--parallel` slots in `config/llama-swap/config.yaml.tmpl`: Flash-Next 131072 (1 slot), gpt-oss and Qwen3.6 65536 (2 slots), Gemma 32768 (4 slots). If you change `-c` or `--parallel` there, change it here.
- opencode's own `service.json` holds a local password and `cli.json` is UI preferences: neither belongs in the repo.

The provider schema (`package`, `compatibility`) follows the opencode config you set up by hand; it was not validated against an opencode install on this machine.
