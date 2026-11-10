# 14 · Developer tools (for you and for coding agents)

Bazzite's `/usr` is read-only, so everything here is installed with **Homebrew** in user space: no `sudo`, no reboot, nothing layered onto the OS image, and a Bazzite update cannot break it. The list lives in [`config/Brewfile`](../config/Brewfile), which is the single source of truth.

```bash
./install.sh devtools          # install what is missing (never upgrades what is there)
brew bundle --file config/Brewfile   # the same thing, directly
brew upgrade                   # update everything when you choose to
```

Safe to re-run any time. To add a tool, add a `brew "name"` line to the Brewfile and re-run; the commit is the documentation.

## What you get

| Group | Tools | Notes |
|---|---|---|
| **Node.js** | `node`, `npm`, `npx`, `corepack` | `corepack enable` gives `pnpm` and `yarn`. Global installs (`npm i -g …`) go into Homebrew's prefix, which you own. |
| **Go** | `go` | Binaries from `go install` land in `~/go/bin`; add it to `PATH` if you use them. |
| **Rust** | `rustc`, `cargo`, `clippy`, `rustfmt`, `rust-analyzer` | The Homebrew toolchain (stable, one version). Need nightly or several toolchains? `brew install rustup` and use `rustup` instead. |
| **Python** | system `python3` + `pip`, `uv`, `ruff` | Use `uv` for everything: `uv venv`, `uv pip install …`, `uv run script.py`, `uv tool install <cli>`, `uv python install 3.13` for other versions. Don't `pip install` into the system Python. |
| **GitHub** | `gh` | Run `gh auth login` once (HTTPS or SSH, browser or token). `git push` over SSH works without it. |
| **Data** | `jq`, `yq` (mikefarah), `sqlite3` | `yq` reads YAML/TOML/XML with jq-like syntax. |
| **Search and view** | `rg` (ripgrep), `fd`, `bat`, `eza`, `delta`, `tldr` (tealdeer), `fzf`, `tree` | `rg` and `fd` respect `.gitignore`, which is why agents prefer them over `grep`/`find`. Run `tldr --update` once. |
| **Quality** | `shellcheck`, `shfmt`, `actionlint`, `direnv`, `hyperfine` | `shellcheck` and `actionlint` are what CI runs on this repo, so run them before pushing. |
| **System** | `htop`, `btop`, `ncdu`, `duf` | `ncdu ~/ai` shows where the disk went. |
| **Already on Bazzite** | `git`, `gcc`, `make`, `curl`, `wget`, `tmux`, `just`, `podman`, `distrobox`, `zstd`, `unzip` | Not in the Brewfile because the OS provides them. |

Versions installed on 2026-11-10: node 26, go 1.27, rust 1.99, gh 2.103, yq 4.54, ripgrep 15, ruff 0.17 (Homebrew keeps current).

## Checks before you push this repo

```bash
shellcheck -S warning -x install.sh bin/evo bin/evo-notify bin/evo-memguard tests/render-test.sh
actionlint
bash tests/render-test.sh
```

## Hints for coding agents (opencode, Claude Code, …)

- Everything above is on `PATH` for any shell started after Homebrew is initialised (Bazzite does this in its default shell profile). If a tool is "not found" inside an agent's sandbox or a systemd unit, add `/home/linuxbrew/.linuxbrew/bin` to `PATH`.
- Prefer `rg`/`fd`/`jq`/`yq` for searching and editing structured files, `uv run` for Python scripts, `gh` for issues/PRs.
- For anything that needs a different distro, compiler or system library, use a container instead of changing the host: `distrobox create`/`podman run`, as the model servers already do.
- Heavy builds compete with the LLM for the same 124 GiB: the [memory guard](13-guardrails.md) will unload models if a build plus a loaded model runs the machine out of RAM. Check `evo status` first, or `evo mode game` to free everything.

## Gotcha: two Pythons

Installing Node through Homebrew also installs Homebrew's `python3` (3.15), and on this box Homebrew's `bin` comes before `/usr/bin` in `PATH`, so `python3` now means Homebrew's. It is "externally managed" (no `pip install`) and has no PyYAML, while the system `/usr/bin/python3` has PyYAML. For your own scripts use `uv run --with <package> script.py` or `uv venv`, not either `python3` directly. `tests/render-test.sh` picks a Python that can import PyYAML (falling back to `/usr/bin/python3`, then `uv`), so it works either way.

## Why Homebrew and not `rpm-ostree install`

Layering packages makes every OS update slower, needs a reboot, and can fail an update when a layered package conflicts with the new image. Homebrew and containers do not touch the image. `rpm-ostree install` is reserved for things that genuinely must live in `/usr` (the repo uses it only for `zsh`, in `./install.sh zsh`).
