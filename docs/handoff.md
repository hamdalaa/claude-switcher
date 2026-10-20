# Local account handoff

## Contract and cost

Checked handoff (`ccx resume TARGET SESSION_ID`, also used by the menu) reuses the same
persisted conversation and shared state on one Mac. It adds no model request, generated summary,
heartbeat, background agent, prompt, or per-turn hook. It never edits the transcript.

This is a guarantee about the switcher's behavior, not Claude Code's billing or internal context.
The next turn can still process a large resumed context, and provider/account cache reuse is not
guaranteed. A compaction summary remains a compaction summary. No switcher can restore information
that was never persisted or promise identical model reasoning.

## What is shared

- `projects/`: saved transcripts and main project auto memory
- `tasks/`: task-tool lists (including lists keyed by session ID)
- `plans/`, `todos/`, `file-history/`: saved plans, legacy todos and checkpoints
- `agent-memory/`: global persistent subagent memory; project-scoped memory already lives in
  the same working tree
- `workflows/`: saved dynamic workflows
- The existing shared instructions, settings, skills, agents, plugins, hooks and prompt history

Each account retains its own authentication and native `sessions/`, `jobs/` and `daemon/` state.
Sharing runtime state can cause resume to attach to the old account's running process.

## Checks and compatibility

1. Validate command arguments and require an already-configured target account. Refuse inherited
   API-key/provider authentication overrides that would bypass that subscription. Explicit settings
   and project configuration are still the user's responsibility; do not put API credentials in them
   when intending to use a subscription.
2. Inspect native `sessions/*.json` entries across configured accounts. A matching session ID and
   live positive PID block handoff. This check sends no signal and cannot prove that *every* writer
   has stopped: absent/stale registries, PID reuse and concurrent launches are limitations.
3. Link missing shared paths and verify existing links refer to A's actual files/directories.
   Real destination objects, dangling links and wrong links are conflicts. Nothing is replaced.
   All configured accounts are checked because the transcript lacks reliable source-account
   provenance. Reconcile conflicts in even an unused configured account, or remove that account
   using the existing removal flow.
4. Find the exact ID under the common `projects/*/` store. Reject absent, empty or ambiguous files.
   Validate JSONL locally in a streaming pass, and recover the original absolute working folder.
5. Check the native registry again, enter the original folder, then invoke
   `claude --resume SESSION_ID` with the target account's config and explicit configuration options.

Supported layout: local CLI transcripts with `type`, `cwd` and optional `sessionId` fields, in
`projects/<project>/<session-id>.jsonl`. The first available `cwd` must still exist. Custom
`CLAUDE_CODE_PROJECT_DIR_NAME` is rejected rather than guessed. Project paths containing control
characters are rejected. Transcripts must be complete JSONL; no repair/truncation is attempted.
Claude Code can evolve these formats, so real-account testing is required for each supported
release. Tests use representative fixtures; they do not establish compatibility with every version.

Settings files are re-read by Claude Code, and it restores model/agent/goal state from its own
transcript as supported by that version. Handoff does not infer original command-line flags,
environment variables, trust settings or account-specific permissions. Re-supply launch-only flags
explicitly; use the same environment for custom task-list IDs or memory locations. Flags are not
recorded because they can contain credentials or private system prompts.

No automatic checkpoint summary is maintained. Keep essential goals/plans in the normal conversation,
plan files or project notes as part of the task, rather than generating a second summary every turn.

## Existing private account data

If `ccx sync` reports a conflict, stop affected sessions and back up both A's data and the
reported account path before changing either. Compare their contents. Preserve unique transcripts,
task lists and memory files in the intended common store, and resolve differing same-name files
deliberately. Only after reconciliation, move the private destination aside to a backup and rerun
`ccx sync` to create its shared link. Keep the backup until you have verified the result.

There is deliberately no blind merge or "force" option: replacing a private directory with a link
could hide the very task state the user wanted to keep. Credentials and `.claude.json` must not be
manually merged as part of this process.

## Validation

Automated tests run against a stub Claude in temporary directories. They cover repeated B→C→A→B
handoffs, original working directory, transcript checksums (including a compaction boundary and a
large tool result), target writes visible through the shared memory/tasks/plans, separate logins,
exact argv forwarding, zero prompt injection, and refusal paths without any Claude invocation.
They also cover real-file conflicts, wrong/dangling/relative links, live/stale registries,
invalid IDs, ambiguous/malformed transcripts, and missing project folders.

Before marking the feature verified with real subscriptions:

1. Use two accounts you control in a disposable local project; record the Claude Code version.
2. On A, make one short request that records a goal, a small plan and a task; include a project
   memory and a subagent memory if those features are in use. Record its session ID.
3. Exit A. Record checksums for its transcript and saved state. Resume on B through the menu.
4. Before sending a message, confirm the displayed history and `/status` account/model. A handoff
   must not automatically send a turn. Check file identity through B's shared links.
5. Send one short continuation request. Verify the previous goal, decision and next step, and verify
   a task/memory update is visible from A. Inspect actual usage rather than assuming cache reuse.
6. Exit B and resume on A. Repeat for a compacted conversation and any launch-only options used.
7. Try a live source session and a deliberate private-directory conflict. Both must stop with an
   explanation, without killing the source, altering its saved content, or creating a new turn.

This manual test consumes ordinary Claude usage for the explicit test prompts. It is not run by
the automated test suite or by the handoff command.

References:
- [Claude Code sessions](https://code.claude.com/docs/en/sessions)
- [Claude Code memory](https://code.claude.com/docs/en/memory)
- [Claude Code directory layout](https://code.claude.com/docs/en/claude-directory)
