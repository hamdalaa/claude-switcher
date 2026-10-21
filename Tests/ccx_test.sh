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
  export CCX_TEST_CALLS="$T/claude-calls"
  : > "$CCX_TEST_CALLS"
  unset CCX_TEST_CAPTURE
  cat > "$T/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$CCX_TEST_CALLS"
json="${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/.claude.json}"; json="${json:-$HOME/.claude.json}"
case "$1 ${2:-}" in
  "auth status") if jq -e '.oauthAccount.emailAddress' "$json" >/dev/null 2>&1; then echo '{"loggedIn":true}'; else echo '{"loggedIn":false}'; fi ;;
  "auth login")  [ -f "$json" ] || echo '{}' > "$json"
                 tmp=$(mktemp); jq '.oauthAccount={"emailAddress":"b@example.com"}' "$json" > "$tmp" && mv "$tmp" "$json"; echo "LOGIN ${CLAUDE_CONFIG_DIR:-default}" ;;
  "auth logout") tmp=$(mktemp); jq 'del(.oauthAccount)' "$json" > "$tmp" && mv "$tmp" "$json"; echo "LOGOUT" ;;
  *)
    if [ -n "${CCX_TEST_CAPTURE:-}" ]; then
      config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
      jq -n --arg cwd "$PWD" --arg config "$config" --args '$ARGS.positional as $args | {cwd:$cwd,config:$config,args:$args}' -- "$@" > "$CCX_TEST_CAPTURE"
      # Simulate a real resumed turn updating the common memory/task/plan stores.
      echo 'continued on target' >> "$config/projects/test-project/memory/MEMORY.md"
      echo 'done' > "$config/tasks/test-session/task-1"
      echo 'next step' >> "$config/plans/test-plan.md"
      echo 'review continued' >> "$config/agent-memory/reviewer/MEMORY.md"
    fi
    echo "RUN dir=${CLAUDE_CONFIG_DIR:-default} child=${CLAUDE_CODE_CHILD_SESSION:-none} args=$*" ;;
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
equal() {
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fi
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
for shared in tasks agent-memory workflows plans; do
  equal "$shared linked before first write" "$HOME/.claude/$shared" "$(readlink "$HOME/.claude-b/$shared")"
done
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

# Checked handoff: all fixtures and Claude calls are local; no real login or inference.
handoff_setup() {
  setup
  project="$T/project with 'quotes' and spaces"
  mkdir -p "$project" "$HOME/.claude/projects/test-project/memory" \
    "$HOME/.claude/tasks/test-session" "$HOME/.claude/agent-memory/reviewer" \
    "$HOME/.claude/plans" "$HOME/.claude-b" "$HOME/.claude-c"
  echo '{"oauthAccount":{"emailAddress":"b@example.com"}}' > "$HOME/.claude-b/.claude.json"
  echo '{"oauthAccount":{"emailAddress":"c@example.com"}}' > "$HOME/.claude-c/.claude.json"
  transcript="$HOME/.claude/projects/test-project/test-session.jsonl"
  jq -nc --arg cwd "$project" '{type:"user",sessionId:"test-session",cwd:$cwd,message:{role:"user",content:"Goal: implement feature. Keep the agreed plan."}}' > "$transcript"
  jq -nc '{type:"assistant",sessionId:"test-session",message:{role:"assistant",model:"test-model",content:[{type:"text",text:"Step 1 complete; next run tests."}]}}' >> "$transcript"
  echo 'project knowledge' > "$HOME/.claude/projects/test-project/memory/MEMORY.md"
  echo 'in progress' > "$HOME/.claude/tasks/test-session/task-1"
  echo 'reviewer knowledge' > "$HOME/.claude/agent-memory/reviewer/MEMORY.md"
  echo 'original plan' > "$HOME/.claude/plans/test-plan.md"
  export CCX_TEST_CAPTURE="$T/resumed.json"
}
refuses_handoff() {
  local name=$1 expected=$2 result status
  shift 2
  : > "$CCX_TEST_CALLS"
  result=$("$CCX" "$@" 2>&1); status=$?
  equal "$name exits non-zero" 1 "$status"
  check "$name explains failure" "$expected" "$result"
  equal "$name never launches Claude" 0 "$(wc -l < "$CCX_TEST_CALLS" | tr -d ' ')"
}

handoff_setup
before=$(shasum -a 256 "$transcript")
result=$("$CCX" resume b test-session 2>&1); status=$?
if [ "$status" -ne 0 ]; then printf '%s\n' "$result"; fi
equal "handoff succeeds" 0 "$status"
equal "handoff makes exactly one Claude invocation" 1 "$(wc -l < "$CCX_TEST_CALLS" | tr -d ' ')"
equal "handoff sends no prompt or summarization request" '["--resume","test-session"]' "$(jq -c .args "$CCX_TEST_CAPTURE")"
equal "handoff returns to exact original cwd" "$project" "$(jq -r .cwd "$CCX_TEST_CAPTURE")"
equal "handoff authenticates with B config" "$HOME/.claude-b" "$(jq -r .config "$CCX_TEST_CAPTURE")"
equal "handoff never rewrites transcript" "$before" "$(shasum -a 256 "$transcript")"
equal "target task writes visible in A" done "$(cat "$HOME/.claude/tasks/test-session/task-1")"
check "target memory writes visible in A" 'continued on target' "$(cat "$HOME/.claude/projects/test-project/memory/MEMORY.md")"
check "target plan writes visible in A" 'next step' "$(cat "$HOME/.claude/plans/test-plan.md")"
check "subagent memory shared" 'reviewer knowledge' "$(cat "$HOME/.claude-b/agent-memory/reviewer/MEMORY.md")"
check "target subagent memory write visible in A" 'review continued' "$(cat "$HOME/.claude/agent-memory/reviewer/MEMORY.md")"
equal "A login preserved by handoff" a@example.com "$(jq -r .oauthAccount.emailAddress "$HOME/.claude.json")"
equal "B login preserved by handoff" b@example.com "$(jq -r .oauthAccount.emailAddress "$HOME/.claude-b/.claude.json")"
equal "no login or model probe" '--resume' "$(cat "$CCX_TEST_CALLS")"
for account in c a b; do
  "$CCX" resume "$account" test-session >/dev/null 2>&1
  equal "repeat handoff on $account" 0 "$?"
done
equal "repeated switches keep transcript unchanged" "$before" "$(shasum -a 256 "$transcript")"

# A compaction boundary and large tool result must remain byte-for-byte intact.
jq -nc '{type:"system",sessionId:"test-session",subtype:"compact_boundary",compactMetadata:{trigger:"auto"}}' >> "$transcript"
jq -nc '{type:"user",sessionId:"test-session",message:{content:[{type:"tool_result",content:("x" * 1048576)}]}}' >> "$transcript"
before=$(shasum -a 256 "$transcript")
"$CCX" resume b test-session >/dev/null 2>&1
equal "large compacted transcript resumes" 0 "$?"
equal "large compacted transcript preserved" "$before" "$(shasum -a 256 "$transcript")"

# Explicit launch options stay argv, with no interpolation or extra prompt.
"$CCX" resume b test-session -- --model test-model --add-dir "$project/extra path" --append-system-prompt 'literal $(touch SHOULD_NOT_EXIST)' >/dev/null 2>&1
equal "configuration options preserved exactly" '["--resume","test-session","--model","test-model","--add-dir","'"$project"'/extra path","--append-system-prompt","literal $(touch SHOULD_NOT_EXIST)"]' "$(jq -c .args "$CCX_TEST_CAPTURE")"
equal "no shell interpolation" no "$([ -e "$project/SHOULD_NOT_EXIST" ] && echo yes || echo no)"
refuses_handoff "prompt rejected" 'unsupported handoff option' resume b test-session -- 'continue now'
refuses_handoff "fork rejected" 'unsupported handoff option' resume b test-session -- --fork-session
refuses_handoff "session override rejected" 'unsupported handoff option' resume b test-session -- --session-id other
refuses_handoff "missing option value" 'missing value' resume b test-session -- --model
refuses_handoff "unknown ID" 'saved session not found' resume b missing
refuses_handoff "path traversal" 'exact session ID' resume b ../test-session
refuses_handoff "unconfigured account" "isn't set up" resume d test-session
refuses_handoff "missing arguments" 'usage: ccx resume' resume b
export ANTHROPIC_API_KEY=synthetic-secret-must-not-be-printed
refuses_handoff "API billing override" 'requires account authentication' resume b test-session
equal "API key never printed" no "$("$CCX" resume b test-session 2>&1 | grep -q synthetic-secret && echo yes || echo no)"
unset ANTHROPIC_API_KEY

# Detect a live source on any configured account, even when the target is A.
mkdir -p "$HOME/.claude-c/sessions"
jq -nc --argjson pid "$$" '{sessionId:"test-session",pid:$pid}' > "$HOME/.claude-c/sessions/live.json"
refuses_handoff "live session" 'session is still running on account C' resume a test-session
equal "live process not killed" yes "$(kill -0 "$$" && echo yes)"
rm "$HOME/.claude-c/sessions/live.json"
echo '{"sessionId":"test-session","pid":2147483647}' > "$HOME/.claude-c/sessions/stale.json"
"$CCX" resume b test-session >/dev/null 2>&1
equal "dead registry entry does not block" 0 "$?"
refuses_handoff "persistence flag rejected" 'unsupported handoff option' resume b test-session -- --no-session-persistence
export CLAUDE_CODE_SKIP_PROMPT_HISTORY=1
refuses_handoff "persistence environment disabled" 'requires session persistence' resume b test-session
unset CLAUDE_CODE_SKIP_PROMPT_HISTORY
export CLAUDE_CODE_PROJECT_DIR_NAME=custom
refuses_handoff "custom project layout" 'custom CLAUDE_CODE_PROJECT_DIR_NAME' resume b test-session
unset CLAUDE_CODE_PROJECT_DIR_NAME
echo 'invalid config' > "$HOME/.claude-c/.claude.json"
refuses_handoff "corrupt account settings" 'shared state conflicts' resume b test-session
teardown

# Conflicting state is never replaced; raw ccx run stays transparent.
handoff_setup
"$CCX" sync >/dev/null
rm "$HOME/.claude-b/tasks"
mkdir -p "$HOME/.claude-b/tasks"
echo 'private task' > "$HOME/.claude-b/tasks/private"
refuses_handoff "private target tasks" 'shared state conflicts' resume b test-session
equal "private tasks preserved" 'private task' "$(cat "$HOME/.claude-b/tasks/private")"
refuses_handoff "private source tasks" 'shared state conflicts' resume a test-session
unset CCX_TEST_CAPTURE
"$CCX" use b >/dev/null
check "raw run remains transparent on conflict" 'args=--resume test-session' "$("$CCX" run --resume test-session 2>&1)"
rm -r "$HOME/.claude-b/tasks"
ln -s "$HOME/missing" "$HOME/.claude-b/tasks"
refuses_handoff "dangling link" 'shared state conflicts' resume b test-session
equal "dangling link unchanged" "$HOME/missing" "$(readlink "$HOME/.claude-b/tasks")"
rm "$HOME/.claude-b/tasks"
ln -s "$HOME/.claude/plans" "$HOME/.claude-b/tasks"
refuses_handoff "wrong link" 'shared state conflicts' resume b test-session
rm "$HOME/.claude-b/tasks"
ln -s ../.claude/tasks "$HOME/.claude-b/tasks"
"$CCX" resume b test-session >/dev/null 2>&1
equal "correct relative link accepted" 0 "$?"
teardown

handoff_setup
cp "$transcript" "$T/original"
printf '{"type":' >> "$transcript"
refuses_handoff "partial transcript" 'incomplete or unsupported transcript' resume b test-session
cp "$T/original" "$transcript"
jq -c '.sessionId = "another-session"' "$T/original" > "$transcript"
refuses_handoff "mismatched transcript" 'incomplete or unsupported transcript' resume b test-session
cp "$T/original" "$transcript"
echo '{"type":"assistant","sessionId":"original-before-fork","message":{"content":"prior history"}}' >> "$transcript"
"$CCX" resume b test-session >/dev/null 2>&1
equal "fork may retain parent session IDs" 0 "$?"
cp "$T/original" "$transcript"
mkdir -p "$HOME/.claude/projects/duplicate"
cp "$transcript" "$HOME/.claude/projects/duplicate/test-session.jsonl"
refuses_handoff "ambiguous ID" 'more than one project' resume b test-session
rm "$HOME/.claude/projects/duplicate/test-session.jsonl"
rmdir "$project"
refuses_handoff "missing project" 'original project folder is unavailable' resume b test-session
teardown

echo "ccx tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
