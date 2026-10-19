#!/usr/bin/env bash
# End-to-end tests for cli/ccx against a stub `claude`, in a throwaway $HOME.
# Never touches real accounts or the real Keychain.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CCX="$ROOT/cli/ccx"
PASS=0; FAIL=0

setup() {
  T=$(mktemp -d)
  export HOME="$T/home"; mkdir -p "$HOME/.claude/skills" "$HOME/.claude/projects"
  echo '{"theme":"dark"}' > "$HOME/.claude/settings.json"
  echo '# shared memory' > "$HOME/.claude/CLAUDE.md"
  echo '{"oauthAccount":{"emailAddress":"a@example.com"},"mcpServers":{"x":{"command":"y"}},"theme":"dark","secretThing":1}' > "$HOME/.claude.json"
  mkdir -p "$T/bin"
  cat > "$T/bin/claude" <<'STUB'
#!/usr/bin/env bash
json="${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/.claude.json}"; json="${json:-$HOME/.claude.json}"
case "$1 ${2:-}" in
  "auth status") if jq -e '.oauthAccount.emailAddress' "$json" >/dev/null 2>&1; then echo '{"loggedIn":true}'; else echo '{"loggedIn":false}'; fi ;;
  "auth login")  [ -f "$json" ] || echo '{}' > "$json"
                 tmp=$(mktemp); jq '.oauthAccount={"emailAddress":"b@example.com"}' "$json" > "$tmp" && mv "$tmp" "$json"; echo "LOGIN ${CLAUDE_CONFIG_DIR:-default}" ;;
  "auth logout") tmp=$(mktemp); jq 'del(.oauthAccount)' "$json" > "$tmp" && mv "$tmp" "$json"; echo "LOGOUT" ;;
  *) echo "RUN dir=${CLAUDE_CONFIG_DIR:-default} child=${CLAUDE_CODE_CHILD_SESSION:-none} args=$*" ;;
esac
STUB
  chmod +x "$T/bin/claude"
  export PATH="$T/bin:/usr/bin:/bin"
  unset CLAUDE_CONFIG_DIR
}
teardown() { rm -rf "$T"; }

check() {  # check <name> <expected-substring> <actual>
  if [[ "$3" == *"$2"* ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fi
}
usage_file() {  # usage_file <acct> <5h> <7d>
  mkdir -p "$HOME/.claude-accounts/usage"
  echo "{\"five_hour\":{\"used_percentage\":$2,\"resets_at\":9999999999},\"seven_day\":{\"used_percentage\":$3,\"resets_at\":9999999999}}" > "$HOME/.claude-accounts/usage/$1.json"
}

setup
check "version" "ccx 1.2.0" "$("$CCX" version)"
check "help" "ccx use <acct>|auto" "$("$CCX" help)"
check "a runs default config" "RUN dir=default" "$("$CCX" a -c 2>&1)"
check "a passes args" "args=-c --model x" "$("$CCX" a -c --model x 2>&1)"
check "b not signed in → login first" "LOGIN $HOME/.claude-b" "$("$CCX" b 2>&1 <<<'' )"
check "b runs in B dir" "RUN dir=$HOME/.claude-b" "$("$CCX" b 2>&1)"
check "b links skills" "$HOME/.claude/skills" "$(readlink "$HOME/.claude-b/skills")"
check "b links settings" "$HOME/.claude/settings.json" "$(readlink "$HOME/.claude-b/settings.json")"
check "b links memory" "$HOME/.claude/CLAUDE.md" "$(readlink "$HOME/.claude-b/CLAUDE.md")"
check "b json has mcpServers" '"y"' "$(jq -c .mcpServers "$HOME/.claude-b/.claude.json")"
check "b json keeps own login" "b@example.com" "$(jq -r .oauthAccount.emailAddress "$HOME/.claude-b/.claude.json")"
check "b json never copies other keys" "null" "$(jq -r .secretThing "$HOME/.claude-b/.claude.json")"
check "b json is private" "600" "$(stat -f %Lp "$HOME/.claude-b/.claude.json")"
check "a login untouched" "a@example.com" "$(jq -r .oauthAccount.emailAddress "$HOME/.claude.json")"
check "child-session env stripped" "child=none" "$(CLAUDE_CODE_CHILD_SESSION=1 CLAUDECODE=1 "$CCX" a 2>&1)"
check "inherited CLAUDE_CONFIG_DIR ignored for a" "RUN dir=default" "$(CLAUDE_CONFIG_DIR=/tmp/elsewhere "$CCX" a 2>&1)"

# real file in B is never overwritten by a link
rm "$HOME/.claude-b/CLAUDE.md"; echo "B's own" > "$HOME/.claude-b/CLAUDE.md"
check "sync skips real files" "skip CLAUDE.md" "$("$CCX" sync 2>&1)"
check "real file kept" "B's own" "$(cat "$HOME/.claude-b/CLAUDE.md")"

# pin / auto pick
check "use b" "starts on account B" "$("$CCX" use b)"
check "which pinned" "b" "$("$CCX" which)"
check "run uses pin" "RUN dir=$HOME/.claude-b" "$("$CCX" run --resume 2>&1)"
check "run passes all args (incl. words ccx uses)" "args=status --help" "$("$CCX" run status --help 2>&1)"
check "use auto" "more headroom" "$("$CCX" use auto)"
usage_file a 80 10; usage_file b 20 10
check "auto picks lower 5h" "b" "$("$CCX" which)"
usage_file a 10 95; usage_file b 60 10
check "auto avoids full weekly" "b" "$("$CCX" which)"
usage_file a 30 40; usage_file b 30 40
check "auto tie → a" "a" "$("$CCX" which)"
echo '{"five_hour":{"used_percentage":99,"resets_at":1}}' > "$HOME/.claude-accounts/usage/a.json"; usage_file b 50 10
check "expired window counts as 0" "a" "$("$CCX" which)"
check "plain ccx announces pick" "ccx → account A" "$("$CCX" 2>&1)"
check "status lists both" "b@example.com" "$("$CCX" status)"
check "status mode" "auto (most headroom)" "$("$CCX" status)"

# logout b → auto never picks a signed-out account
"$CCX" logout b >/dev/null
usage_file a 95 95; usage_file b 0 0
check "auto skips signed-out b" "a" "$("$CCX" which)"
check "run never prompts login for signed-out account" "RUN dir=$HOME/.claude-b" "$("$CCX" use b >/dev/null; "$CCX" run --version 2>&1)"
check "run printed no sign-in nag" "" "$("$CCX" run --version 2>&1 | grep -c 'signing in' | sed 's/^0$//')"
check "api-key users never get a login prompt" "RUN dir=$HOME/.claude-b" "$(ANTHROPIC_API_KEY=x "$CCX" b 2>&1 | grep -v '^$')"
"$CCX" use auto >/dev/null
check "bad account" "account must be a, b, c or d" "$("$CCX" login z 2>&1)"
check "bad use" "usage: ccx use a|b|c|d|auto" "$("$CCX" use x 2>&1)"
teardown

# shared dirs are created in A so B links them from the first launch
setup; rm -rf "$HOME/.claude/projects"; mkdir -p "$HOME/.claude-b"
"$CCX" sync >/dev/null
check "missing shared dir created in A" "$HOME/.claude/projects" "$(readlink "$HOME/.claude-b/projects")"
check "sync is quiet the 2nd time" "accounts synced" "$("$CCX" sync 2>&1)"
check "no skip warnings on 2nd sync" "0" "$("$CCX" sync 2>&1 | grep -c skip)"
before=$(stat -f %m "$HOME/.claude-b/.claude.json"); sleep 1; "$CCX" sync >/dev/null
check "unchanged json is not rewritten" "$before" "$(stat -f %m "$HOME/.claude-b/.claude.json")"
echo 'not json' > "$HOME/.claude.json"
"$CCX" sync >/dev/null 2>&1; check "corrupt source → sync exits non-zero" "1" "$?"
teardown

# float resets_at doesn't print shell errors
setup; mkdir -p "$HOME/.claude-accounts/usage"
echo '{"five_hour":{"used_percentage":10,"resets_at":9999999999.5},"seven_day":{"used_percentage":5,"resets_at":9999999999.5}}' > "$HOME/.claude-accounts/usage/a.json"
check "float resets_at is fine" "" "$("$CCX" status 2>&1 >/dev/null)"
teardown

# accounts C and D
setup
"$CCX" b </dev/null >/dev/null 2>&1          # B signs in (stub writes b@example.com)
check "use c before it exists is refused" "isn't set up yet" "$("$CCX" use c 2>&1)"
check "login c creates its folder" "LOGIN $HOME/.claude-c" "$("$CCX" login c 2>&1)"
check "c links shared skills" "$HOME/.claude/skills" "$(readlink "$HOME/.claude-c/skills")"
check "c json gets mcpServers" '"y"' "$(jq -c .mcpServers "$HOME/.claude-c/.claude.json")"
check "c runs in its own dir" "RUN dir=$HOME/.claude-c" "$("$CCX" c 2>&1)"
check "status lists c" "C  b@example.com" "$("$CCX" status)"
usage_file a 95 10; usage_file b 92 10; usage_file c 40 20
check "auto picks c when a, b full" "c" "$("$CCX" which)"
mkdir -p "$HOME/.claude-d"; echo '{"oauthAccount":{"emailAddress":"d@example.com"}}' > "$HOME/.claude-d/.claude.json"; usage_file d 10 90
check "auto skips full d (weekly), keeps c" "c" "$("$CCX" which)"
usage_file d 10 30
check "auto picks d (lowest 5h)" "d" "$("$CCX" which)"
"$CCX" use c >/dev/null
check "pin c" "RUN dir=$HOME/.claude-c" "$("$CCX" run 2>&1)"
check "remove c" "account C removed" "$("$CCX" remove c 2>&1)"
check "c folder gone" "gone" "$([ -d "$HOME/.claude-c" ] && echo still || echo gone)"
check "c folder is in the Trash" ".claude-c-" "$(ls -A "$HOME/.Trash")"
check "pin cleared with c" "auto (most headroom)" "$("$CCX" status)"
check "a can't be removed" "can't be removed" "$("$CCX" remove a 2>&1)"
check "remove unknown" "isn't set up" "$("$CCX" remove c 2>&1)"
check "sync covers b and d" "accounts synced" "$("$CCX" sync 2>&1)"
check "d got linked" "$HOME/.claude/skills" "$(readlink "$HOME/.claude-d/skills")"
teardown

# missing claude
setup; rm "$T/bin/claude"
check "missing claude is explained" "Claude Code isn't installed" "$("$CCX" a 2>&1)"
teardown

echo "ccx tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
