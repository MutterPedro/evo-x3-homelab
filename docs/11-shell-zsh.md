# 11 · Shell: zsh + Oh My Zsh + the `evo` prompt

Bazzite ships bash. This sets up zsh with Oh My Zsh, four plugins and a prompt
that shows the machine's mode (game / server / quiet), the `evo` profile and
unified-memory (GTT) use. Files: [`config/zsh/zshrc`](../config/zsh/zshrc) and
[`config/zsh/evo.zsh-theme`](../config/zsh/evo.zsh-theme).

> **Shortcut:** `./install.sh zsh` does all of the steps below. It is idempotent and
> backs up an existing `~/.zshrc`. The first run layers zsh and asks you to reboot;
> run it again after the reboot to set the login shell, then log out and back in.

## 1. Install zsh and make it the login shell

Bazzite is an atomic image, so zsh is a layered package and needs a reboot.
`chsh` is not installed; use `usermod`.

```bash
sudo rpm-ostree install zsh
systemctl reboot
sudo usermod -s /usr/bin/zsh "$USER"
```

Then **log out of KDE and back in** (a running session keeps `SHELL=/bin/bash`
and Konsole inherits it). Konsole and **Ctrl+Alt+T** then open zsh. Plasma
already binds Ctrl+Alt+T to Konsole by default through
`/usr/share/kglobalaccel/org.kde.konsole.desktop`; do not add your own entry to
`~/.config/kglobalshortcutsrc`, a hand-written one broke the shortcut.

## 2. Oh My Zsh and plugins

```bash
git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
C=~/.oh-my-zsh/custom/plugins
git clone https://github.com/zsh-users/zsh-autosuggestions.git            $C/zsh-autosuggestions
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git $C/fast-syntax-highlighting
git clone --depth 1 https://github.com/marlonrichert/zsh-autocomplete.git  $C/zsh-autocomplete
# optional, not enabled (redundant with fast-syntax-highlighting):
# git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $C/zsh-syntax-highlighting
```

Plugin list, from [n1snt's gist](https://gist.github.com/n1snt/454b879b8f0b7995740ae04c5fb5b7df#install-plugins),
trimmed: `plugins=(git zsh-autosuggestions fast-syntax-highlighting)`.

## 3. Install the config and theme

```bash
cd ~/Projects/evo-x3-homelab        # or wherever the repo is cloned
cp config/zsh/zshrc ~/.zshrc        # back up your old ~/.zshrc first
mkdir -p ~/.oh-my-zsh/custom/themes
cp config/zsh/evo.zsh-theme ~/.oh-my-zsh/custom/themes/
rm -f ~/.zcompdump*
```

What the `zshrc` changes from the Oh My Zsh template:

| Change | Why |
|---|---|
| `PATH` includes `~/.local/bin`, `~/bin`, Homebrew; `typeset -U path PATH` | Only `~/.bashrc` added them, so zsh could not find `claude` or `evo`. |
| `zsh-autocomplete` is **sourced before** `source $ZSH/oh-my-zsh.sh`, not listed in `plugins=()` | As an OMZ plugin it loads after `compinit` and Tab prints `command not found: _autocomplete__unambiguous`. |
| `ZSH_THEME="evo"` | The custom prompt below. |
| Aliases `game`, `server`, `quiet`, `gpu` | `evo mode game\|server\|quiet`, and `nvtop`. |

If `zsh-autocomplete` misbehaves with `fast-syntax-highlighting` (reported in
the gist's comments), drop `zsh-autocomplete` first.

## 4. The `evo` prompt

```
┌ 🧠 SERVER·smart │ GPU 38/120G 74% │ ~/Projects/evo-x3-homelab on main*
└ ❯                                                          ✘ 1  14:03
```

- **Badge:** GAME (purple), SERVER + profile (cyan/blue), QUIET (yellow), or
  `◌ no mode` before `evo mode` has ever been run. Read from
  `~/.local/state/evo/state.env`, so it follows `evo mode ...` and
  `evo run -- %command%` immediately.
- **GPU:** GTT used/total in GiB (yellow at 60%, red at 85%) and GPU busy %,
  read from `/sys/class/drm/card*/device/`. No forks or network calls per prompt.
- **Right side:** exit code when non-zero, and the clock. `❯` is red after a failure.
- No Nerd Font required.

Switch modes from the prompt with `game`, `server`, `quiet`.
