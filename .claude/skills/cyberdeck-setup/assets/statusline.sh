#!/usr/bin/env bash
# ~/.claude/statusline.sh
#
# CYBERDECK status line for Claude Code.
# Mirrors the palette used in ~/.config/starship.toml:
#   soft_green   #00ff9f  -> directory
#   cyber_purple #9d4bff  -> git branch
#   neon_cyan    #00fff9  -> model
#   warn_amber   #ffb000  -> context usage (normal)
#   error_red    #ff003c  -> context usage (>=80%, danger)
#   muted_grey   #5c5c6e  -> separators / low-emphasis text
#
# Reads the statusLine JSON payload from stdin (see Claude Code docs).

input=$(cat)

# ---- 24-bit ANSI truecolor palette -----------------------------------------
C_RESET=$'\033[0m'
C_GREEN=$'\033[38;2;0;255;159m'    # soft_green
C_PURPLE=$'\033[38;2;157;75;255m'  # cyber_purple
C_CYAN=$'\033[38;2;0;255;249m'     # neon_cyan
C_AMBER=$'\033[38;2;255;176;0m'    # warn_amber
C_RED=$'\033[38;2;255;0;60m'       # error_red
C_GREY=$'\033[38;2;92;92;110m'     # muted_grey

sep="${C_GREY} │ ${C_RESET}"

# ---- directory: shorten $HOME to ~, truncate to last 3 path segments ------
dir_raw=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // "."')
dir_disp=${dir_raw/#$HOME/\~}

IFS='/' read -ra parts <<< "$dir_disp"
n=${#parts[@]}
if (( n > 3 )); then
    short_dir="…/${parts[n-3]}/${parts[n-2]}/${parts[n-1]}"
else
    short_dir="$dir_disp"
fi
[ -z "$short_dir" ] && short_dir="/"

# ---- git branch (skip optional locks so we never block/interfere) ---------
branch=""
if git -C "$dir_raw" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$dir_raw" --no-optional-locks branch --show-current 2>/dev/null)
fi

# ---- model ------------------------------------------------------------------
model=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "Claude"')

# ---- context window usage ----------------------------------------------------
used_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')

# ---- assemble ---------------------------------------------------------------
out="${C_GREEN}${short_dir}${C_RESET}"

if [ -n "$branch" ]; then
    out="${out}${C_GREY} on ${C_PURPLE}Ψ ${branch}${C_RESET}"
fi

out="${out}${sep}${C_CYAN}${model}${C_RESET}"

if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
    pct_int=$(printf '%.0f' "$used_pct" 2>/dev/null || echo "$used_pct")
    ctx_color=$C_AMBER
    if [ "$pct_int" -ge 80 ] 2>/dev/null; then
        ctx_color=$C_RED
    fi
    out="${out}${sep}${ctx_color}ctx ${pct_int}%${C_RESET}"
fi

printf '%s\n' "$out"
