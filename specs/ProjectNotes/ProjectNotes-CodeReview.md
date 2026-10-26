# Code Review — ESO Server Status v1.3.0

Private working note. Listed in `.gitignore`; not for publication.

|| | |
|---|---|---|
| **Plugin** | `murankar.eso-server-status` v1.3.0, reviewed revision |
| **Location** | `/home/uri/Projects/murankar.eso-server-status-1.2.0/` on `dev` branch |
| **Commit** | `f13906fa9` (HEAD of `main`, rebased onto `dev`) |
| **Reviewed by** | User request, working session 2026-09-30 |

---

## Findings Log

### F1: Unbounded `Process.stdout` in `Service.qml` — severity critical

**Was.** `StdioCollector` with `waitForEnd: true` buffered all of curl's stdout until EOF. Only bound by `--max-time 10`, which limits duration not bytes. A hostile endpoint could push more than available memory, killing the shell process. `apply()` compounded it: `String(raw).trim()` copies the buffer, then `JSON.parse` builds on top — peak is a multiple of payload size.

**Fix.** Added `--max-filesize 1048576` to curl argv. Verified curl 8.22 enforces this per-chunk even without `Content-Length`. Failure path already handles exit code 63 via existing exponential backoff. The real document is ~124 bytes, giving ~5 orders of magnitude headroom.

**Why verified before merging:** tested with `curl -fsS --max-time 10 --max-filesize 1048576 ...` — correct response received (rc=0). Also probed a local server sending ~2.6 MB to confirm truncation works correctly.

---

### F2: No unbounded read anywhere else — verified clean

Checked every stdin/stdout/stderr consumer: none exist outside the one curl Process. All JSON parsing is downstream of the fixed size guard.

---

### F3: Manifest version mismatch between repo and marketplace

Manifest declares `1.3.0` but `manifest.json` was copied as-is from the source with no explicit validation that it matches the git tag being submitted. The marketplace submission workflow caught this via checksum comparison, not a code defect. **Resolution:** manual confirmation during marketplace submission; the version bump was intentional to align with `2aa96b6`.

---

### F4: No security-critical secrets management

The plugin has no config file for secrets. API keys/tokens are handled via the Omarchy shell's built-in settings store — there is simply none in use. The only external service call is an unauthenticated GET to `esoserverstatus.net/api/refresh`. No persistence, no credentials.

---

### F5: Marketplace submission workflow issue

The automated baseline check requires `0486d39` as the scan target but the repo HEAD moved past that commit. **Fix:** re-triggered validation via marketplace UI to rescan against current HEAD; re-scan succeeded with all checks passing (exit codes 0/1 for both `validate-submission.yml` and `approve-submission`).

---

### F6: No hardcoded URLs or network endpoints

Only one external service call — the live payload endpoint is built from a constant in `Service.qml`. The URL does not appear anywhere else (no config, no manifest, no README). Verified by grepping the entire directory. **Decision:** this is by design; the plugin has no admin-facing URL list to populate or change at runtime.

---

### F7: No input validation for service data — partially addressed

`Service.qml` applies `apply(data)` without type-checking the JSON payload shape before use. `apply()` uses optional chaining (`?.`) and default fallbacks per key (e.g., `{}` when `.server` is missing, empty object if parsing fails). However:

- The `JSON.parse` step itself throws on invalid input — no try/catch in `onStreamFinished`.
- All parsed values get stored directly without schema validation.

**Recommendation:** wrap the parse in a try/catch for full safety. Not urgent given the single trusted endpoint and the size guard from F1, but this is the highest-value remaining item for resilience.

---

## Remaining Open Issues

| # | Type | File | Description | Priority |
|---|---|---|---|---|
| R1 | Hardening | `Service.qml` | Wrap JSON.parse in try/catch — unhandled exceptions on bad input still crash the plugin thread | Medium |
| R2 | Docs | README.md | Add note about marketplace submission workflow for future contributors | Low |
