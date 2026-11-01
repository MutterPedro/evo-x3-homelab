#!/usr/bin/env bash
# EVO-X3 homelab installer for Bazzite (Fedora Atomic).
#
#   ./install.sh system   One-time host setup (uses sudo, needs a reboot after)
#   ./install.sh user     Services, configs, CLI. Safe to re-run any time.
#   ./install.sh models   Download the default model set (~150 GB)
#   ./install.sh all      system + user (then reboot, then `models`)
#   ./install.sh zsh      Optional: zsh + Oh My Zsh + plugins + the `evo` prompt (docs/11)
#
# Every step is idempotent: re-running converges to the same state.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVO_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/evo"
QUADLET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
BIN_DIR="$HOME/.local/bin"
BREW="/home/linuxbrew/.linuxbrew/bin/brew"

c_bold=$'\e[1m'; c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'; c_off=$'\e[0m'
step() { printf '\n%s==> %s%s\n' "$c_bold" "$*" "$c_off"; }
ok()   { printf '%s  ok%s %s\n' "$c_green" "$c_off" "$*"; }
warn() { printf '%s  !!%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
die()  { printf '%s  xx %s%s\n' "$c_red" "$*" "$c_off" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
load_settings() {
  mkdir -p "$EVO_CONFIG_DIR"
  if [[ ! -f "$EVO_CONFIG_DIR/evo.env" ]]; then
    cp "$REPO_DIR/config/evo.env.example" "$EVO_CONFIG_DIR/evo.env"
    ok "created $EVO_CONFIG_DIR/evo.env (edit it to customise)"
  fi
  # shellcheck source=config/evo.env.example
  set -a; source "$EVO_CONFIG_DIR/evo.env"; set +a
}

check_platform() {
  [[ -f /run/ostree-booted ]] || warn "not an rpm-ostree system; this repo targets Bazzite"
  if ! grep -qi "bazzite" /etc/os-release 2>/dev/null; then
    warn "this does not look like Bazzite; continuing anyway"
  fi
  [[ "$(id -u)" -ne 0 ]] || die "run as your normal user, not root (sudo is used where needed)"
}

# ---------------------------------------------------------------------------
# SYSTEM (sudo) -- kernel args, groups, sleep, Wi-Fi, firewall, services
# ---------------------------------------------------------------------------

# Replace-or-add kernel arguments in a single rpm-ostree transaction.
set_kargs() {
  local -a want=("$@") args=()
  local current kv key cur_val
  current="$(rpm-ostree kargs)"
  for kv in "${want[@]}"; do
    key="${kv%%=*}"
    # existing value(s) for this key, if any
    while read -r cur_val; do
      [[ -z "$cur_val" ]] && continue
      [[ "$cur_val" == "$kv" ]] && continue
      args+=("--delete=$cur_val")
    done < <(tr ' ' '\n' <<<"$current" | grep -E "^${key//./\\.}(=|$)" || true)
    if [[ " $current " != *" $kv "* ]]; then
      args+=("--append=$kv")
    fi
  done
  if ((${#args[@]})); then
    echo "    rpm-ostree kargs ${args[*]}"
    sudo rpm-ostree kargs "${args[@]}"
    NEED_REBOOT=1
  else
    ok "kernel arguments already set"
  fi
}

remove_karg_key() {
  local key="$1" v
  while read -r v; do
    [[ -n "$v" ]] || continue
    sudo rpm-ostree kargs --delete="$v"; NEED_REBOOT=1
  done < <(rpm-ostree kargs | tr ' ' '\n' | grep -E "^${key//./\\.}(=|$)" || true)
}

ensure_group() {
  local g="$1"
  if ! grep -q "^${g}:" /etc/group; then
    # Fedora Atomic keeps base groups in /usr/lib/group; copy it to /etc/group
    # first so usermod can modify it (same approach as `ujust add-user-to-input-group`).
    grep "^${g}:" /usr/lib/group | sudo tee -a /etc/group >/dev/null
  fi
  if [[ " $(id -nG "$USER") " == *" $g "* ]]; then
    ok "$USER already in group $g"
  else
    sudo usermod -aG "$g" "$USER"; ok "added $USER to group $g (takes effect after reboot)"
    NEED_REBOOT=1
  fi
}

install_system() {
  check_platform
  load_settings
  NEED_REBOOT=0
  sudo -v || die "sudo is required for the system step"

  step "Unified memory: let the GPU borrow up to ${EVO_GTT_GIB} GiB of RAM"
  local pages=$((EVO_GTT_GIB * 262144))      # 4 KiB pages
  local mib=$((EVO_GTT_GIB * 1024))
  local -a kargs=("ttm.pages_limit=$pages" "ttm.page_pool_size=$pages" "amdgpu.gttsize=$mib")
  set_kargs "${kargs[@]}"
  if [[ "${EVO_DISABLE_IOMMU,,}" == "true" ]]; then
    set_kargs "amd_iommu=off"
  else
    remove_karg_key amd_iommu
  fi

  step "Hostname ${EVO_HOSTNAME:-evo-x3} (reachable as ${EVO_HOSTNAME:-evo-x3}.local on the LAN)"
  if [[ "$(hostnamectl --static 2>/dev/null)" != "${EVO_HOSTNAME:-evo-x3}" ]]; then
    sudo hostnamectl set-hostname "${EVO_HOSTNAME:-evo-x3}"
  fi
  ok "hostname $(hostnamectl --static)"

  step "GPU device access for rootless containers"
  ensure_group video
  ensure_group render

  step "Never sleep (this is a server)"
  sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1
  ok "sleep/suspend/hibernate masked"

  step "Wi-Fi power saving off (lower latency, fewer drops on MT7925)"
  sudo install -Dm644 "$REPO_DIR/system/NetworkManager/99-evo-wifi-powersave.conf" \
    /etc/NetworkManager/conf.d/99-evo-wifi-powersave.conf
  sudo systemctl reload NetworkManager 2>/dev/null || true
  ok "NetworkManager configured"

  step "Firewall: open LAN ports for API, chat, dashboards, streaming"
  if systemctl is-active --quiet firewalld; then
    local p
    for p in "$EVO_LLAMA_SWAP_PORT" "$EVO_WEBUI_PORT" "$EVO_GRAFANA_PORT"; do
      sudo firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null
    done
    sudo firewall-cmd --reload >/dev/null
    ok "ports $EVO_LLAMA_SWAP_PORT, $EVO_WEBUI_PORT, $EVO_GRAFANA_PORT/tcp open"
  else
    warn "firewalld not running; skipping"
  fi

  step "Keep user services running without a login (linger)"
  sudo loginctl enable-linger "$USER"; ok "linger enabled"

  step "Hardware watchdog on (auto-reboot if the kernel ever hangs)"
  if [[ " $(rpm-ostree kargs) " == *" nowatchdog "* ]]; then
    sudo rpm-ostree kargs --delete-if-present=nowatchdog --delete-if-present=modprobe.blacklist=sp5100_tco
    NEED_REBOOT=1
  fi
  sudo install -Dm644 "$REPO_DIR/system/systemd/99-evo-watchdog.conf" /etc/systemd/system.conf.d/99-evo-watchdog.conf
  ok "systemd RuntimeWatchdogSec configured"

  step "Remote access services (SSH, Tailscale, Cockpit web console)"
  sudo systemctl enable --now sshd >/dev/null 2>&1 && ok "sshd enabled" || warn "could not enable sshd"
  sudo systemctl enable --now tailscaled >/dev/null 2>&1 && ok "tailscaled enabled (run: sudo tailscale up)" || warn "tailscaled not available"

  step "TuneD (power profiles) available"
  if command -v tuned-adm >/dev/null; then
    ok "tuned-adm present: $(tuned-adm active 2>/dev/null | sed 's/.*: //')"
  else
    warn "tuned-adm missing; 'evo mode' will fall back to powerprofilesctl"
  fi

  if ((NEED_REBOOT)); then
    printf '\n%sReboot required%s to apply kernel arguments and group membership:\n  systemctl reboot\n' "$c_yellow" "$c_off"
  fi
}

# ---------------------------------------------------------------------------
# USER -- secrets, configs, llama-swap, containers, CLI
# ---------------------------------------------------------------------------

gen_secret() { head -c 48 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-40; }

ensure_secrets() {
  local f="$EVO_CONFIG_DIR/secrets.env"
  touch "$f"; chmod 600 "$f"
  local name
  for name in LLAMA_SWAP_KEY WEBUI_SECRET_KEY SEARXNG_SECRET GRAFANA_ADMIN_PASSWORD RESTIC_PASSWORD; do
    if ! grep -q "^${name}=" "$f"; then
      local val; val="$(gen_secret)"
      [[ "$name" == "LLAMA_SWAP_KEY" ]] && val="sk-evo-$val"
      echo "${name}=${val}" >>"$f"
      ok "generated $name"
    fi
  done
  set -a
  # shellcheck disable=SC1090
  source "$f"
  set +a
}

# Replace @VAR@ placeholders with values from the environment. Pure bash so it
# works on a minimal atomic host. Leaves ${...} (llama-swap macros) untouched.
render() {
  local src="$1" dst="$2" content var
  shopt -u patsub_replacement 2>/dev/null || true   # bash 5.2: '&' must stay literal
  content="$(<"$src")"
  for var in $(grep -oE '@[A-Z0-9_]+@' "$src" | sort -u | tr -d '@'); do
    [[ -n "${!var+x}" ]] || die "render $src: \$$var is not set"
    content="${content//@${var}@/${!var}}"
  done
  install -Dm"${3:-644}" /dev/stdin "$dst" <<<"$content"
}

write_runtime_env() {
  # systemd EnvironmentFile cannot expand $HOME, so write resolved values.
  local f="$EVO_CONFIG_DIR/runtime.env"
  {
    echo "# generated by install.sh -- edit evo.env instead"
    local v
    for v in $(compgen -v EVO_); do printf '%s=%s\n' "$v" "${!v}"; done
  } >"$f"
  ok "wrote $f"
}

install_brew_tools() {
  if [[ -x "$BREW" ]]; then
    local pkg missing=()
    for pkg in uv restic rclone jq; do
      "$BREW" list --formula "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
      "$BREW" install "${missing[@]}"
    fi
    ok "brew tools: uv restic rclone jq"
  else
    warn "Homebrew not found at $BREW; install uv/restic/rclone/jq manually"
  fi
}

install_llama_swap() {
  local ver cur=""
  # Download fully first, then parse in bash: piping curl into `grep -m1` makes
  # curl fail with "(23) Failure writing output" under `set -o pipefail`.
  local json
  json="$(curl -fsSL https://api.github.com/repos/mostlygeek/llama-swap/releases/latest)" \
    || die "could not query llama-swap releases (GitHub API rate limit? try again in a few minutes)"
  [[ "$json" =~ \"tag_name\":[[:space:]]*\"v?([^\"]+)\" ]] || die "could not parse llama-swap release tag"
  ver="${BASH_REMATCH[1]}"
  if [[ -x "$BIN_DIR/llama-swap" ]]; then
    local vout; vout="$("$BIN_DIR/llama-swap" -version 2>/dev/null || true)"
    [[ "$vout" =~ ([0-9]+) ]] && cur="${BASH_REMATCH[1]}"
  fi
  if [[ "$cur" == "$ver" ]]; then
    ok "llama-swap v$ver already installed"
    return
  fi
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/ls.tgz" \
    "https://github.com/mostlygeek/llama-swap/releases/download/v${ver}/llama-swap_${ver}_linux_amd64.tar.gz"
  tar -xzf "$tmp/ls.tgz" -C "$tmp"
  install -Dm755 "$tmp/llama-swap" "$BIN_DIR/llama-swap"
  rm -rf "$tmp"
  ok "installed llama-swap v$ver to $BIN_DIR"
}

install_user() {
  check_platform
  load_settings
  ensure_secrets

  step "Directories"
  mkdir -p "$EVO_MODELS_DIR" "$EVO_COMFY_DIR"/{comfy-models,comfy-outputs} \
           "$EVO_AI_DIR"/{open-webui,searxng,grafana,prometheus} "$BIN_DIR" \
           "$QUADLET_DIR" "$SYSTEMD_USER_DIR"
  ok "$EVO_AI_DIR"

  step "Configuration files"
  write_runtime_env
  render "$REPO_DIR/config/llama-swap/config.yaml.tmpl" "$EVO_CONFIG_DIR/llama-swap.yaml"
  render "$REPO_DIR/config/comfyui/extra_model_paths.yaml" "$EVO_CONFIG_DIR/comfyui-extra-model-paths.yaml"
  render "$REPO_DIR/config/searxng/settings.yml" "$EVO_AI_DIR/searxng/settings.yml"
  render "$REPO_DIR/config/prometheus/prometheus.yml" "$EVO_CONFIG_DIR/prometheus.yml"
  render "$REPO_DIR/config/open-webui.env" "$EVO_CONFIG_DIR/open-webui.env" 600
  mkdir -p "$EVO_CONFIG_DIR/grafana"
  cp -r "$REPO_DIR/config/grafana/." "$EVO_CONFIG_DIR/grafana/"
  render "$REPO_DIR/config/grafana/provisioning/datasources/prometheus.yaml" \
         "$EVO_CONFIG_DIR/grafana/provisioning/datasources/prometheus.yaml"
  ok "rendered into $EVO_CONFIG_DIR"

  step "Tools"
  install_brew_tools
  install_llama_swap
  "$BIN_DIR/llama-swap" -validate -config "$EVO_CONFIG_DIR/llama-swap.yaml" >/dev/null \
    || die "llama-swap rejected $EVO_CONFIG_DIR/llama-swap.yaml (see output above)"
  ok "llama-swap config validated"
  ln -sf "$REPO_DIR/bin/evo" "$BIN_DIR/evo"
  ln -sf "$REPO_DIR/bin/evo-notify" "$BIN_DIR/evo-notify"
  ok "evo CLI -> $BIN_DIR/evo"

  step "Containers (podman quadlets) and user services"
  local q
  for q in "$REPO_DIR"/quadlets/*; do
    render "$q" "$QUADLET_DIR/$(basename "$q")" 600
  done
  for q in "$REPO_DIR"/systemd/user/*; do
    render "$q" "$SYSTEMD_USER_DIR/$(basename "$q")"
  done
  systemctl --user daemon-reload
  ok "units installed"

  step "Pulling container images (first time takes a while)"
  local img
  for img in "$EVO_IMG_VULKAN" "$EVO_IMG_UNIFIED" "$EVO_IMG_KOKORO" \
             docker.io/searxng/searxng:latest ghcr.io/open-webui/open-webui:main \
             docker.io/prom/prometheus:latest docker.io/prom/node-exporter:latest \
             docker.io/grafana/grafana-oss:latest; do
    podman pull -q "$img" >/dev/null && ok "$img" || warn "failed to pull $img"
  done
  echo "    (ROCm and ComfyUI images are pulled on first use: evo images pull-all)"

  step "Starting services"
  systemctl --user enable llama-swap.service evo-backup.timer podman-auto-update.timer
  systemctl --user start evo-backup.timer podman-auto-update.timer
  # restart (not just start) so re-runs pick up changed configs
  systemctl --user restart llama-swap.service searxng.service open-webui.service \
    node-exporter.service prometheus.service grafana.service
  ok "services started"

  step "Desktop shortcuts"
  local d
  for d in "$REPO_DIR"/desktop/*.desktop; do
    render "$d" "$HOME/.local/share/applications/$(basename "$d")"
  done
  ok "Game / Server / Quiet mode launchers added to the app menu"

  local ip; ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  cat <<EOF

${c_bold}Done.${c_off}  Next:
  1. Download models:          ./install.sh models     (or: evo models pull <name>)
  2. Open the chat UI:         http://${ip:-evo-x3}:${EVO_WEBUI_PORT}  (first account becomes admin)
  3. API for coding tools:     http://${ip:-evo-x3}:${EVO_LLAMA_SWAP_PORT}/v1   key: evo secret api-key
  4. Dashboards:               http://${ip:-evo-x3}:${EVO_GRAFANA_PORT}  (admin / evo secret grafana)
  5. Check everything:         evo doctor
EOF
}

install_models() {
  load_settings
  "$REPO_DIR/bin/evo" models pull default
}

install_zsh() {
  local omz="$HOME/.oh-my-zsh" custom plug repo ts
  custom="$omz/custom"
  step "zsh: package"
  if command -v zsh >/dev/null 2>&1; then
    ok "zsh $(zsh --version | cut -d' ' -f2) is installed"
  else
    sudo rpm-ostree install zsh
    warn "zsh is layered but not active until you reboot; re-run './install.sh zsh' afterwards"
  fi

  step "zsh: Oh My Zsh and plugins"
  command -v git >/dev/null 2>&1 || die "git is required"
  [[ -d "$omz" ]] || git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$omz"
  mkdir -p "$custom/plugins" "$custom/themes"
  for repo in \
    zsh-users/zsh-autosuggestions \
    zdharma-continuum/fast-syntax-highlighting; do
    plug="$custom/plugins/${repo#*/}"
    [[ -d "$plug" ]] || git clone --depth 1 "https://github.com/$repo.git" "$plug"
  done
  ok "oh-my-zsh + zsh-autosuggestions, fast-syntax-highlighting"

  step "zsh: ~/.zshrc and the evo theme"
  cp "$REPO_DIR/config/zsh/evo.zsh-theme" "$custom/themes/evo.zsh-theme"
  if [[ -f "$HOME/.zshrc" ]] && ! cmp -s "$REPO_DIR/config/zsh/zshrc" "$HOME/.zshrc"; then
    ts="$(date +%Y%m%d-%H%M%S)"
    cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$ts"
    ok "backed up the old ~/.zshrc to ~/.zshrc.bak.$ts"
  fi
  cp "$REPO_DIR/config/zsh/zshrc" "$HOME/.zshrc"
  rm -f "$HOME"/.zcompdump*
  ok "installed ~/.zshrc and the evo theme"

  step "zsh: login shell"
  if [[ -x /usr/bin/zsh ]]; then
    if [[ "$(getent passwd "$USER" | cut -d: -f7)" == /usr/bin/zsh ]]; then
      ok "login shell is already /usr/bin/zsh"
    else
      sudo usermod -s /usr/bin/zsh "$USER"
      ok "login shell set to /usr/bin/zsh; log out of KDE and back in (Konsole and Ctrl+Alt+T then open zsh)"
    fi
  else
    warn "reboot, then run './install.sh zsh' again to set zsh as the login shell"
  fi
}

# Allow `source install.sh` (used by tests) without running anything.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    system) install_system ;;
    user)   install_user ;;
    models) install_models ;;
    zsh)    install_zsh ;;
    all)    install_system; install_user ;;
    *) sed -n '2,10p' "$0"; exit 1 ;;
  esac
fi
