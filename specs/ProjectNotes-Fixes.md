# Project Notes — ESO Server Status Fixes

Local-only working notes. Gitignored on purpose — never committed, never pushed.

Last updated: 2026-09-30

**Purpose of this document.** A running log of security and marketplace findings
and their fixes, with enough detail to re-derive the reasoning later. Complements
`ProjectNotes-BaseApp.md` (what the plugin is) and `TODO.md` (what is still
planned). This file records *what broke, why it mattered, and why the fix is the
shape it is*.

---

## 1. Log at a glance

| # | Date | Area | Summary | State |
|---|---|---|---|---|
| 1 | 2026-09-30 | Marketplace | Baseline evidence was stale (`2aa96b6` vs HEAD `f13906f`); re-triggered validation | Fixed |
| 2 | 2026-09-30 | Plugin | Unbounded response buffering in `Service.qml` could exhaust shell memory | Fixed locally, uncommitted |

---

## 2. Marketplace baseline was stale, blocking approval

**Context.** Submission issue is
**[#9346](https://github.com/omacom/omarchy-plugin-marketplace/issues/9346)** in
`omacom/omarchy-plugin-marketplace`. Labels: `submission`, `validated`,
`security-review-required`.

### 2.1 The "security review" is not ours to do

Worth writing down because it reads like a task aimed at us and is not. Per
`SECURITY.md:92`, unblocking is a maintainer applying the `approved-and-verified`
label, which fires `.github/workflows/approve-submission.yml`. Our permissions on
the marketplace repo are read-only:

```json
{"admin":false,"maintain":false,"triage":false,"push":false,"pull":true}
```

So we cannot request or self-approve it. `SECURITY.md:126` also forbids
circumventing it: *"Do not weaken, relabel, or manually fabricate a baseline
result."* The only correct move is to make the evidence current and let a
maintainer act on it.

### 2.2 The actual blocker was staleness, not the review

The recorded baseline was bound to `2aa96b6fd4880a33a19a8afbcb9ddac152dc1aed`
(v1.2.0, scanned 00:59:11Z) while `main` had moved to
`f13906fa9545fd44650d136d6018c072fd5a7173` (v1.3.0).

`scripts/approve-submission.mjs:171` throws
`approval-security-baseline-changed` — *"The fresh security baseline does not
match the report approved by the maintainer"* — whenever the post-label rescan
differs from the pre-label report. Approval was therefore **guaranteed to fail**
until a fresh bot report existed at the current HEAD. `SECURITY.md:96` states the
same rule from the other direction: *"A changed branch head invalidates the
recorded validation and requires a new run."*

### 2.3 How to re-trigger validation

`route-issue-automation.yml` listens on `issues: [opened, edited, reopened,
labeled, unlabeled]` and routes to `validate-submission.yml`, which re-scans at
current HEAD. Available triggers, given we cannot label:

- **Edit the issue body** — works, used this time. Preserves `createdAt` on the
  bot comments.
- Close and reopen — also fires, but reads like gaming the automation. Prefer
  the edit.
- Re-applying the `submission` label would work but needs `triage`, which we lack.
- A comment does **not** work; `commented` is not in the trigger list.

```bash
gh issue view 9346 -R omacom/omarchy-plugin-marketplace --json body --jq '.body' > body.md
# append a short, factual re-request note
gh issue edit 9346 -R omacom/omarchy-plugin-marketplace --body-file body.md
```

Note the workflow **edits the two existing bot comments in place** rather than
posting new ones, so the issue always has exactly one current validation comment
and one current baseline comment. Do not be confused by their `createdAt` still
showing the original submission time.

### 2.4 Result

Run `36769116890` at 19:56:16Z, `route: success`, `validate-submission/validate:
success`. Both bot comments updated:

| | Before | After |
|---|---|---|
| Baseline commit | `2aa96b6` (v1.2.0) | `f13906f` (v1.3.0) |
| Baseline `checkedAt` | 00:59:11Z | 19:56:38Z |
| Validation | *No supported root preview detected* | ✅ Optional root preview detected |
| Manifest version | 1.2.0 | 1.3.0 |
| Outcome | `review-required` | `review-required` |
| Capabilities | `remote-build` | `remote-build` (`README.md:93`) |
| Findings | none | none |

The preview complaint cleared for free — `preview.png` has been tracked at the
root since `5370a03`, the earlier scan just predated it.

### 2.5 The `remote-build` flag is expected and benign

It fires on one line, the documented install path:

```
git clone https://github.com/murankar/omarchy-eso-server-status.git ~/.config/omarchy/plugins/murankar.eso-server-status
```

`SECURITY.md:59`: a path that obtains code *only from the submitted repository*
"is not automatically rejected; it produces the `remote-build` capability and
requires maintainer review." So this is a capability, not a finding, and our
outcome is `review-required` rather than `needs-fixes`. Nothing to remove — every
plugin installed via `git clone` trips this. The maintainer notes already on the
submission pre-answer it.

### 2.6 What the scanner cannot see

`SECURITY.md:31`: the baseline *"does not perform general data-flow analysis."*
It matches documented static patterns — `curl-pipe-shell`, `cargo-git-unpinned`,
`sudoers-*`, and friends. Resource limits, unbounded buffers and unchecked
parsing are **outside its model entirely**. Do not expect a proactive hardening
fix to change the label; finding these is on us.

---

## 3. Unbounded response buffering in `Service.qml`

**Found by:** our own review, on the `f13906f` code. Not caught by the baseline
(see 2.6).

**Was:** `Process.stdout` used a `StdioCollector` with `waitForEnd: true`, which
buffers all of stdout until EOF, with no ceiling. The only bound was
`--max-time 10`, which bounds *duration*, not bytes. A hostile or compromised
endpoint could push far more than available memory well inside a ten-second
window, killing the Quickshell shell process — bar gone, desktop needs a shell
restart.

`apply()` compounded it: `String(raw || "").trim()` copies the whole buffer, then
`JSON.parse` builds an object graph on top, so peak memory is a small multiple of
the payload.

### 3.1 The trap: a check after collection fixes nothing

The instinct is to add a length guard in `apply()`. That is **too late** — the
exhaustion happens during collection, before any of our code sees the string. The
bound has to be enforced at the curl layer.

The obvious curl-layer bound, `--max-filesize`, looked unsafe: the endpoint
sends **no `Content-Length`** at all (HTTP/2, Cloudflare, `cf-cache-status:
DYNAMIC`), and `--max-filesize` is documented in terms of `Content-Length`.

Probed it rather than trusting the docs. Local server offering ~2.6 MB,
`--max-filesize 65536`, curl 8.22.0:

```
Content-Length present | bytes=      0 | exit=63 | curl: (63) Maximum file size exceeded
NO Content-Length      | bytes=  65536 | exit=63 | curl: (63) Exceeded the maximum allowed file size (65536) with 65536 bytes
```

**curl 8.22 enforces the cap incrementally, per chunk**, independent of
`Content-Length`. It read exactly 65536 bytes then aborted. So one flag closes
this even against a server that omits or lies about its length.

Caveat if this is ever revisited: this streaming enforcement is a modern-curl
behaviour. On a much older curl the no-`Content-Length` case would not be bounded
here, and the post-collection guard in 3.3 becomes load-bearing.

### 3.2 The fix

One flag in the `Process.command` argv:

```qml
command: ["curl", "-fsS", "--max-time", "10",
  "--max-filesize", "1048576",
  "-H", "X-Requested-With: XMLHttpRequest",
  "-H", "Accept: application/json",
  root.apiUrl]
```

Why the failure path is already correct: exit 63 is non-zero, so `onExited` feeds
`settle(false)` → `failures++` → the existing exponential backoff (60s → 600s).
An oversized response degrades into an ordinary transport failure instead of
becoming a new failure mode. `settle()`'s `if (!settled) return` guard means the
truncating `onStreamFinished` cannot double-count the same fetch.

Why 1 MiB: the real document is **124 bytes**.

```json
{"servers":{"PC-EU":true,"PC-NA":true,"PC-PTS":true,"XBOX-EU":true,
 "XBOX-NA":true,"PS4-EU":true,"PS4-NA":true,"PS4-EU":true,"PS4-NA":true},"message":""}
```

1 MiB is roughly four orders of magnitude of headroom — a ceiling, not a guess at
real size, so ordinary fleet growth never trips it.

Verified live with the exact new argv: `rc=0`, 124 bytes, parses clean.

### 3.3 Optional belt-and-braces, deliberately not added

A length guard in `apply()` would be cheap insurance and would make the invariant
explicit in QML:

```js
if (String(raw || "").length > 1048576) return false
```

Not added because it is **not** a memory control (see 3.1) and the curl cap
already guarantees the bound, so it would be redundant defence dressed up as
protection. Worth adding only alongside a genuinely new parse path, or if we ever
must support a curl too old for streaming enforcement.

### 3.4 State and follow-up

- Change is **uncommitted**. `git status` shows `M Service.qml` only, 10 lines
  added. Not yet committed, not pushed.
- `qmllint` is not installed on this machine, so the edit is not machine-checked.
  It is an argv array literal plus a comment; the exact command was verified by
  hand against the live endpoint.
- **Committing invalidates the baseline again.** New commit moves HEAD, and
  `SECURITY.md:96` requires another validation run. Batch every other pending
  change into the same commit, then re-trigger once via the method in 2.3. Do not
  commit this alone and re-trigger twice.
- The label will not change: outcome stays `review-required` with the same lone
  `remote-build`. This fix is above what the marketplace asks for.

---

## 4. Process gotchas hit this session

**`pkill -f` self-matched and wedged the shell.** Running
`pkill -f 'szt/srv.py'` killed the invoking `bash -c` process itself, because
that pattern matched its own command line. The persistent shell hung and every
subsequent command timed out; heredoc-written scratch files were lost with it.
Use the bracket trick so the pattern cannot match itself:

```bash
pkill -9 -f 'szt[/]'        # not 'szt/'
```

Also: a backgrounded process holding stdout open will block the tool call from
returning even when the command itself finished. Prefer running a probe
self-contained in one foreground script.

---

## 5. Reference: files and lines

| What | Where |
|---|---|
| Network owner, the fix | `Service.qml` — `Process { id: fetch }`, `command:` |
| Bounded parse | `Service.qml` — `apply()` |
| Single-count outcome funnel | `Service.qml` — `settle()` |
| Submission issue | `omacom/omarchy-plugin-marketplace` #9346 |
| Marketplace policy | `SECURITY.md` (lines 31, 59, 92, 96, 126) |
| Stale-evidence guard | `scripts/approve-submission.mjs:171` |
| Re-validation trigger | `.github/workflows/route-issue-automation.yml` |
| Approval trigger | `.github/workflows/approve-submission.yml` |
| Local-only notes | `.gitignore`, lines 10–16 |
