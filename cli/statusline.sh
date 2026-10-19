#!/usr/bin/env bash
# Status line for the two-account setup.
# Shows which account this session runs on, plus the last-known 5h/7d usage of BOTH accounts.
# Each session records its own account's rate_limits to ~/.claude-accounts/usage/<a|b>.json,
# so the other account's numbers are as fresh as the last time you used it.

input=$(cat)
STATE_DIR="$HOME/.claude-accounts/usage"
mkdir -p "$STATE_DIR"

case "${CLAUDE_CONFIG_DIR:-}" in
  *".claude-b"|*".claude-b/") me=b ;;
  *) me=a ;;
esac

limits=$(jq -c '.rate_limits // empty' <<<"$input" 2>/dev/null)
if [ -n "$limits" ] && [ "$limits" != "{}" ]; then
  printf '%s' "$limits" > "$STATE_DIR/$me.json.tmp" && mv "$STATE_DIR/$me.json.tmp" "$STATE_DIR/$me.json"
fi

RED=$'\e[31m'; YEL=$'\e[33m'; GRN=$'\e[32m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RST=$'\e[0m'

color_for() {
  local p=${1%.*}
  if [ "$p" -ge 90 ]; then printf '%s' "$RED"
  elif [ "$p" -ge 70 ]; then printf '%s' "$YEL"
  else printf '%s' "$GRN"; fi
}

# Prints "<5h> <7d>" as integers; a window whose reset time has passed counts as 0, unknown as "-".
read_usage() {
  local file="$STATE_DIR/$1.json"
  [ -f "$file" ] || { echo "- -"; return; }
  jq -r --argjson now "$(date +%s)" '
    def pct(w): if w == null then "-"
                elif (w.resets_at // 0) < $now then "0"
                else (w.used_percentage // 0 | floor | tostring) end;
    "\(pct(.five_hour)) \(pct(.seven_day))"' "$file" 2>/dev/null || echo "- -"
}

segment() {
  local acct=$1 label five seven out
  label=$(tr '[:lower:]' '[:upper:]' <<<"$acct")
  read -r five seven <<<"$(read_usage "$acct")"
  if [ "$acct" = "$me" ]; then out="${BOLD}▶ ${label}${RST}"; else out="${DIM}${label}${RST}"; fi
  for pair in "5h:$five" "7d:$seven"; do
    local name=${pair%%:*} val=${pair#*:}
    if [ "$val" = "-" ]; then out+=" ${DIM}${name} –${RST}"
    else out+=" ${DIM}${name}${RST} $(color_for "$val")${val}%${RST}"; fi
  done
  printf '%s' "$out"
}

model=$(jq -r '.model.display_name // "Claude"' <<<"$input")
dir=$(jq -r '.workspace.current_dir // .cwd // ""' <<<"$input")
dir=${dir/#$HOME/\~}

printf '%s%s%s %s  │  %s  │  %s' "$DIM" "[$model]" "$RST" "$dir" "$(segment a)" "$(segment b)"
