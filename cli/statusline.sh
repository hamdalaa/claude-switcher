#!/usr/bin/env bash
# Status line for Claude Switcher (accounts A–D).
# Shows which account this session runs on, plus the last-known 5h/7d usage of every account.
# Each session records its own account's rate_limits to ~/.claude-accounts/usage/<a-d>.json,
# so the other account's numbers are as fresh as the last time you used it.

input=$(cat)
STATE_DIR="$HOME/.claude-accounts/usage"
mkdir -p "$STATE_DIR"

config_dir=${CLAUDE_CONFIG_DIR%/}
case "$config_dir" in
  ""|"$HOME/.claude") me=a ;;
  "$HOME/.claude-b") me=b ;;
  "$HOME/.claude-c") me=c ;;
  "$HOME/.claude-d") me=d ;;
  *) me="" ;;   # not one of ours: recording it as A would show another login's usage as A's
esac

# Merge, don't overwrite: an idle session keeps redrawing with the numbers from its last request.
# A later reset is a newer window; within one window usage only goes up (same rule as the app).
record() {
  local file="$STATE_DIR/$me.json" tmp merged
  merged=$(jq -c --argjson new "$1" '
    def newer(o; n):
      if o == null then n elif n == null then o
      elif ((o.resets_at // 0) - (n.resets_at // 0)) as $d | ($d < 600 and $d > -600)
        then (if (o.used_percentage // 0) > (n.used_percentage // 0) then o else n end)
      elif (o.resets_at // 0) > (n.resets_at // 0) then o else n end;
    . as $old | $new + {five_hour: newer($old.five_hour; $new.five_hour),
                        seven_day: newer($old.seven_day; $new.seven_day)}' "$file" 2>/dev/null) || merged=$1
  [ -n "$merged" ] || merged=$1   # empty or unreadable file
  # Unchanged → no write. Most redraws end here, and a status line killed mid-redraw can't leak.
  [ "$(cat "$file" 2>/dev/null)" = "$merged" ] && return
  # Claude Code kills a status line that's still running when it redraws; don't leave the temp file.
  trap 'rm -f -- "${tmp:-}"; exit 143' HUP INT TERM
  tmp=$(mktemp "$STATE_DIR/.$me.XXXXXX") || return
  printf '%s' "$merged" > "$tmp" && mv "$tmp" "$file" || rm -f -- "$tmp"
  trap - HUP INT TERM
}

# Sweep temp files left by a status line that was SIGKILLed mid-write (traps can't catch that),
# and markers of sessions that ended long ago.
find "$STATE_DIR" -maxdepth 1 -type f -name '.[a-d].??????' -mmin +1 -delete 2>/dev/null
find "$STATE_DIR/.seen" -type f -mmin +1440 -delete 2>/dev/null

limits=$(jq -c '.rate_limits // empty' <<<"$input" 2>/dev/null)
session=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null | tr -cd 'A-Za-z0-9_-')
if [ -n "$me" ] && [ -n "$limits" ] && [ "$limits" != "{}" ]; then
  # An idle session redraws with the numbers from its last request. Record each session's numbers
  # only when they change, so it can't keep replaying an old reading over a newer live one.
  seen="$STATE_DIR/.seen/$session"
  if [ -z "$session" ] || [ "$(cat "$seen" 2>/dev/null)" != "$limits" ]; then
    record "$limits"
    if [ -n "$session" ]; then mkdir -p "$STATE_DIR/.seen" && printf '%s' "$limits" > "$seen"; fi
  fi
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

line="${DIM}[$model]${RST} $dir"
for acct in a b c d; do
  if [ "$acct" = a ] || [ -d "$HOME/.claude-$acct" ]; then line+="  │  $(segment "$acct")"; fi
done
printf '%s' "$line"
