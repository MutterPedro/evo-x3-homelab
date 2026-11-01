# evo.zsh-theme -- prompt for the EVO-X3 (local LLMs <-> gaming).
#
#  ┌ GAME|SERVER|QUIET · profile  ·  GPU 38/120G 74%  ·  ~/dir  ·  branch
#  └ ❯
#
# The mode and profile come from `evo` (~/.local/state/evo/state.env), so the
# badge changes the moment you run `evo mode ...`. GPU numbers are read from
# sysfs on every prompt: no forks, no network, no lag. Plain Unicode only
# (no Nerd Font needed).

setopt prompt_subst
autoload -Uz add-zsh-hook

_evo_state_file=${XDG_STATE_HOME:-$HOME/.local/state}/evo/state.env
_evo_gpu_dev=
for _d in /sys/class/drm/card*/device(N); do
  [[ -r $_d/mem_info_gtt_total ]] && { _evo_gpu_dev=$_d; break }
done
unset _d

_evo_precmd() {
  local mode= prof= line
  if [[ -r $_evo_state_file ]]; then
    for line in "${(@f)$(<$_evo_state_file)}"; do
      case $line in
        MODE=*)    mode=${line#MODE=} ;;
        PROFILE=*) prof=${line#PROFILE=} ;;
      esac
    done
  fi

  case $mode in
    game)   _evo_badge="%F{magenta}%B 🎮 GAME %b%f" ;;
    server) _evo_badge="%F{cyan}%B 🧠 SERVER %b%f"
            [[ -n $prof ]] && _evo_badge+="%F{8}·%f%F{blue}$prof%f" ;;
    quiet)  _evo_badge="%F{yellow}%B 🌙 QUIET %b%f" ;;
    *)      _evo_badge="%F{8} ◌ no mode %f" ;;
  esac

  _evo_gpu=
  if [[ -n $_evo_gpu_dev ]]; then
    local used total busy color=green
    used=$(<$_evo_gpu_dev/mem_info_gtt_used)   2>/dev/null
    total=$(<$_evo_gpu_dev/mem_info_gtt_total) 2>/dev/null
    busy=$(<$_evo_gpu_dev/gpu_busy_percent)    2>/dev/null
    if [[ -n $used && -n $total ]]; then
      local u=$(( used / 1073741824 )) t=$(( total / 1073741824 ))
      (( t > 0 && u * 100 / t >= 60 )) && color=yellow
      (( t > 0 && u * 100 / t >= 85 )) && color=red
      _evo_gpu="%F{8}GPU%f %F{$color}${u}/${t}G%f"
      [[ -n $busy ]] && _evo_gpu+=" %F{8}${busy}%%%f"
    fi
  fi
}
add-zsh-hook precmd _evo_precmd

# git branch, dirty marker
ZSH_THEME_GIT_PROMPT_PREFIX="%F{8}on%f %F{green}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%f"
ZSH_THEME_GIT_PROMPT_DIRTY="%F{red}*"
ZSH_THEME_GIT_PROMPT_CLEAN=""

PROMPT='%F{8}┌%f${_evo_badge} %F{8}│%f ${_evo_gpu}${_evo_gpu:+ %F{8}│%f }%F{blue}%B%~%b%f $(git_prompt_info)
%F{8}└%f%(?.%F{green}.%F{red})❯%f '
RPROMPT='%(?..%F{red}✘ %?%f )%F{8}%*%f'
