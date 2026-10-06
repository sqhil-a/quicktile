# Agent requests and phone replies

Tap a waiting agent tile to see the current question or approval. Choose an option or enter an answer, then Send answer. An approval offers Allow once and Decline; QuickTile never grants a session-wide exception. Replies go over the paired local connection, and completion is shown only after Codex confirms the matching request was resolved.

## What works with each connection

- Lifecycle hooks and local compatibility records provide status and bounded request details. They cannot reply to every built-in question in an already-running desktop session.
- A live Codex app-server control connection can deliver input/approval requests and accept their exact responses. QuickTile attaches through `codex app-server proxy` to the default user-owned control socket when tracking is enabled. It does not start or resume another copy of a task.
- If a request did not arrive through a live control connection, it is read-only. QuickTile displays that limitation; it never types into a general chat composer or pretends that a message answered an approval.

The current desktop Codex process on the development Mac uses stdio and does not expose the default control socket. End-to-end desktop replies are therefore **not verified or enabled for that process**. This environment also prohibits Codex UI inspection, so no Accessibility workaround was used.

For a separate compatible terminal workflow, Codex documents a local listener and remote CLI interface:

```sh
codex app-server --listen unix://
```

In another terminal:

```sh
codex --remote unix://
```

Use the CLI's available sessions normally. Do not resume a desktop task concurrently in a second server. Keep the listener local; no public network port is needed. The installed Codex version must support these commands and route pending requests to the connected client. Transport/request behavior is version-dependent and requires live verification; app-server transport is experimental. [Official Codex app-server documentation](https://learn.chatgpt.com/docs/app-server).

## Status correction

Shell approval/completion correlation uses the actual command, excluding changing approval descriptions and execution wrapper options. An id-less completion resolves only a unique matching pending request. Unrelated work cannot clear another approval. Old unresolvable cached approval records become unknown until fresh lifecycle evidence is received. Direct runtime status, when available, overrides compatibility inference; nonblocking questions do not manufacture a waiting state.

## Privacy and validation

Only bounded pending request details are fetched on demand. Full conversations are not transmitted. Request content is not added to general capability broadcasts or sent to Groq. Hook details may be cached locally until resolved; disabling tracking removes QuickTile-owned caches. Live requests and submitted answers are held in memory and excluded from board export.

Replies require an authenticated phone session, a fresh command timestamp, replay protection, the exact live request, valid question identifiers and allowed answers. Resolved/cancelled requests and duplicate in-flight responses are rejected. A missing acknowledgement is an uncertain outcome, not success; QuickTile does not replay the reply automatically.

Deterministic tests cover request parsing, runtime running/waiting transitions, resolution identity, stale/cancelled requests, exact answer encoding, and confirmation. Simulator UI uses DEBUG-only fixtures for the request sheet. Real pending question/approval delivery and confirmation in a live compatible Codex session remain an acceptance gate.
