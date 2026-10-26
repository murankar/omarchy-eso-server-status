# Project Notes — ESO Server Status Fixes

Local-only working notes. Gitignored on purpose — never committed, never pushed.

Last updated: 2026-09-30

---

## Findings Log

|| # | Date | Area | Summary | State |
|---|---|---|---|---|
| 1 | 2026-09-30 | Marketplace | Re-triggered stale baseline (v1.2.0 → v1.3.0) to unblock approval | Fixed |
| 2 | 2026-09-30 | Plugin | Unbounded `Process.stdout` in `Service.qml` — potential heap exhaustion from malicious response | Fixed locally, uncommitted |

---

## Marketplace Baseline Resolved (Item #1)

The recorded scan baseline was bound to `2aa96b6` but `main` had moved to `f13906f` (v1.3.0). The approve automation **guarantees failure** when post-label rescan differs from pre-label report.

**Resolution:** edited issue body → rerouted automation to scan current HEAD. Both bot comments updated:
- Baseline moved: `2aa96b6` → `f13906f` (v1.3.0)
- Validation passed: root preview detected ✅, no findings
- Outcome: `review-required` (awaiting maintainer action)

The marketplace has no entry for the plugin yet — this was the initial submission path. Marketplace permissions are read-only (`pull:true`). Cannot self-approve or request review. Per `SECURITY.md`: unblocking requires a maintainer applying `approved-and-verified`.

**Workflow note:** editing the issue body is preferred over close/reopen (preserves `createdAt` timestamps). Comments do not trigger the automation.

---

## Unbounded Response Buffering — Fixed (Item #2)

### The Problem
`StdioCollector { waitForEnd: true }` on curl Process buffered all stdout with no size cap. Only duration bound (`--max-time 10`). A malicious payload could exceed available memory inside 10 seconds, killing the Quickshell process. `apply()` compounded it by copying the buffer into a string then parsing JSON on top.

### The Fix
Added `--max-filesize 1048576` (1 MiB) to curl argv:

```qml
command: ["curl", "-fsS", "--max-time", "10",
  "--max-filesize", "1048576",
  "-H", "X-Requested-With: XMLHttpRequest",
  "-H", "Accept: application/json",
  root.apiUrl]
```

The real document is ~124 bytes. One flag enforces streaming per-chunk truncation even without `Content-Length` (verified on curl 8.22). Exit code 63 degrades into existing exponential backoff — no new error path needed.

---

## Unparsed JSON in Service.qml — Not Yet Fixed

**Finding.** `onStreamFinished` calls `JSON.parse(data)` with no try/catch. If the endpoint returns invalid JSON, the plugin thread crashes silently (QML unhandled exception behavior).

**Why deferred:** the trusted endpoint and size guard make failure unlikely, but this should be addressed before production release. Suggested pattern:
```qml
onStreamFinished: {
    try { processData(data) }
    catch(e) { console.warn("JSON parse error:", e) }
}
```