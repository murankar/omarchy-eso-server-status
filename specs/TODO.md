# TODO

Working notes for `murankar.eso-server-status`. Moved into `specs/` and tracked
as of 1.4.1; these were gitignored and local-only up to 1.4.0.

Last updated: 2026-10-02

---

## 1. Configure this system for GitHub

**Why:** the Omarchy plugin marketplace only accepts plugins hosted on a public
**GitHub** repository. Listings are GitHub repos, submissions are GitHub issues,
and the verification workflow reads repositories through the GitHub API. There is
no GitLab path. Everything else in section 2 is blocked on this.

**Status: complete.** GitHub account is `murankar`, repo is public at
https://github.com/murankar/omarchy-eso-server-status, and an anonymous
HTTPS clone plus `omarchy plugin validate` both pass — the same checks the
marketplace validator runs.

### Already done

- [x] SSH key at `~/.ssh/id_ed25519`, shared by both hosts. No ssh-agent and no
      `~/.ssh/config` block are needed — verified against both:
      `ssh -T git@gitlab.com` → `Welcome to GitLab, @urix3!`
      `ssh -T git@github.com` → `Hi murankar! You've successfully authenticated`
- [x] `git user.name` / `user.email` configured globally
- [x] GitHub CLI installed (2.101.0) and authenticated as `murankar`, git
      protocol `ssh`
- [x] Public repo created and both `main` and `dev` pushed
- [x] Anonymous HTTPS clone verified working

### Remote layout

**GitHub is the only upstream.** The `gitlab` remote was removed; the GitLab copy
is frozen at `8e6c177` under the old `eso.server-status` id and is no longer
maintained. Delete or archive it at your convenience.

`origin` is the SSH URL. Note that `omarchy plugin add <https-url>` clones over
HTTPS, so a freshly installed copy has no push authentication — fix it once
after any reinstall:

```bash
cd ~/.config/omarchy/plugins/murankar.eso-server-status
git remote set-url origin git@github.com:murankar/omarchy-eso-server-status.git
```

Fetching works either way (the repo is public), so `omarchy plugin update` is
unaffected; only pushing back needs SSH.

---

## 2. Marketplace submission — published (2026-10-01)

**Status: done.** The submission was filed and the plugin is listed and
verified at https://omarchyplugins.com/plugin.html?id=murankar.eso-server-status

It was published from commit `f669178` (1.4.0) on `main`, with a
maintainer-reviewed verification and the `remote-build` capability accepted for
the documented checkout of this plugin. A reviewer first raised an unbounded
response-size concern at `f13906f` and then withdrew it, having found no
attacker-controlled input or allocation amplification in the fixed publisher
API.

The verified snapshot is still 1.4.0 at `f669178`, behind `main`, so the
listing reads `Update unverified` until a newer commit is verified through the
plugin verification form. Installs still clone mutable `HEAD`, so users already
receive 1.4.1 code; only the verified snapshot label lags.

The original draft is kept in this directory as `MARKETPLACE-SUBMISSION.md`.
It was checked mechanically against the issue form: six headings in order,
`Widgets` category, tags `bar, system, quickshell`, and all five checklist
lines byte-identical to the official wording.

### Readiness check

- [x] Valid `manifest.json` in the repo root — `omarchy plugin validate` passes
- [x] README with installation instructions
- [x] README with removal instructions (line 70)
- [x] **Repository on public GitHub** — `github.com/murankar/omarchy-eso-server-status`,
      public, anonymous clone verified
- [x] **Plugin ID decided** — `murankar.eso-server-status` (was `eso.server-status`).
      Matches Omarchy's own `<username>.<plugin>` shape. **Permanent once listed.**
      Renaming the manifest alone is not enough — see the id-in-QML trap below.
- [x] **`LICENSE` file** — MIT, added. Note: MIT *permits* commercial use; a
      non-commercial restriction was considered and deliberately dropped in
      favour of the OSI-approved default
- [x] External dependencies documented in the README (`curl`, `omarchy-*`)
- [x] Plugin ID is outside the reserved `omarchy.*` namespace
- [x] Optional `preview.png` in the repo root — added, and the marketplace
      picked it up as the card image

### Decisions needed before submitting

- [x] **Plugin ID.** Decided: `murankar.eso-server-status`.
- [x] **`author` field** — now `Matthias Urankar` (was the machine username
      `"uri"`, which the marketplace would have displayed publicly)
- [x] **Version** is `1.4.1`. Tags `v1.2.0`, `v1.3.0`, `v1.4.0`, and `v1.4.1`
      are all cut on the remote.
- [x] Check the intended ID is not already taken in the registry before
      submitting. *(Done — `catalog.json` queried: 4,522 listings, no collision
      on `murankar.eso-server-status`, no existing listing by `murankar`.
      Re-query immediately before filing.)*

### Process notes

- Approval is **not** a push. A maintainer reviews, and an
  "Automated Security Baseline" static scan runs against the exact commit.
  Publication requires an `approved-and-verified` label.
- The marketplace's own agent guidance requires the plugin owner to confirm the
  submission checklist and **explicitly approve the exact issue text** before
  it is filed. Do not submit unattended.
- Marketplace verification and `omarchy plugin add` are separate trust
  boundaries: `plugin add` clones mutable `HEAD`, so it may not install the
  verified commit.

---

## 3. Housekeeping

- [x] Mark the private-repo issue resolved in `ProjectNotes-BaseApp.md`
- [x] Licence decided and added: MIT, `Copyright (c) 2026 Matthias Urankar`
- [ ] Archive or delete the stale GitLab repo (frozen at `8e6c177`, old id)
- [x] Check `murankar.eso-server-status` is unclaimed in the marketplace registry
      before submitting. *(Done — `catalog.json` fetched, 4,522 listings, no
      collision on the id and no existing listing by `murankar`. Re-query
      immediately before filing, since ids are permanent.)*

---

## 4. Per-server status panel — complete (2026-09-29)

**Status: shipped** on `dev`, fast-forwarded to `main`, pushed to GitHub as
`94bc2ab`. Verified by a clean anonymous clone plus `omarchy plugin validate`.

Left click on the bar entry now toggles a popout listing all seven servers,
each coloured by its own state: green `true`, amber `2` (reachable but
impaired), red `false`, dimmed when the last poll failed. Right click still
opens the site, and the panel carries its own link.

### Decisions worth remembering

- **Amber is not red.** `2` means the service is up with ongoing issues.
  Collapsing it into offline overstates the severity, so it gets its own colour.
- **Nested panel, not a new manifest kind.** `Panel.qml` is a file inside the
  bar widget and is handed the live service object. It is a pure view, so
  opening it adds no request and cannot drift from the glyph. This is the
  pattern the weather plugin uses; `manifest.json` needs no `panel` kind.
- **`serverList` is reassigned wholesale.** A QML property holding an array only
  notifies bindings when the *reference* changes, so `apply()` builds a new
  array rather than mutating the old one.

### Traps hit while building it

- **`centerOnBar: true` is not what it sounds like.** It centres the card on the
  whole bar, i.e. screen centre, not under the bar entry. With a top bar you
  want `centerOnBar: false` so `cardOrigin` uses `anchorScreenPos`.
- **The KeyboardPanel window is larger than its card.** `panel.width/height` is
  the layershell window (500x500), not the visible surface. The card is
  `contentWidth x contentHeight` (300x375). Log the latter.
- **Do not debug this by colour-filtering a screenshot.** The popup background
  and a dark wallpaper are both near-black, so pixel heuristics produce false
  positives and false negatives alike. A temporary magenta `Rectangle` sized to
  `panel.contentWidth/Height` gives an exact bbox; a per-row `console.warn` of
  the resolved binding proves colours. Both were removed before committing.
- Screenshots come back at scale 2 (a 1500x1000 logical screen yields a
  3000x2000 PNG), so any bbox measured in pixels needs halving to compare
  against logged logical values.

---

## 5. Code review follow-ups — fixes done, LOW items open (2026-09-30)

**Status: all 6 HIGH/MEDIUM fixes committed and shipped in 1.4.0; 9 LOW items
and the nits still open.** Full report in this directory as
`ProjectNotes-CodeReview.md`. None of it blocked publication — the marketplace
submission in section 2 went live on 2026-10-01.

**Why:** a full review of the plugin at `f13906f` plus the then-uncommitted
`--max-filesize` work, looking at it the way a marketplace reviewer would —
remote input, subprocess handling, shell API divergence, and the manifest. Two
findings were serious enough to fix before anything else.

### Fixed — shipped in 1.4.0

- [x] **HIGH — remote payload rendered as rich text.** Server names reach `Text`
      items that never set `textFormat`, so Qt 6 defaulted to `AutoText`, i.e.
      rich text. An endpoint could inject `<img src="http://attacker/…">` and the
      rich-text loader **fetched it** — reproduced against a local beacon. Fixed
      with `textFormat: Text.PlainText` on both items plus `Servers.plain()` as a
      second line of defence. This was also a live falsification of the README's
      "one endpoint, nothing else" claim.
- [x] **HIGH — the recovery notification was inverted.** `onStreamFinished` runs
      `settle(apply(text))`, so `apply()` finished first and `settle` compared the
      **new** status against itself: recovery fired on the way *down* and stayed
      silent on the way *up*. Fixed with a `statusBeforePoll` snapshot taken in
      `maybePoll()`.
- [x] **MEDIUM — no cap on server count.** `--max-filesize` bounds bytes, not
      elements, and 20 000 keys fit in ~200 KB. Added `maxServers: 256`, a 64 KiB
      pre-`JSON.parse` body guard, and a `mutedLookup` binding so `isMuted()`
      stopped rebuilding an array per row.
- [x] **MEDIUM — `settled` was an unlatchable latch.** Only `onStreamFinished`
      or `onExited` cleared it, and neither is guaranteed. Added a 15 s watchdog
      on `pollStartedAt` plus clock-derived `overdue` staleness, so a poll that
      never reports back still goes stale instead of painting the last known
      green forever.
- [x] **MEDIUM — `NumberField` wrote `shell.json` per keystroke** and persisted
      the transient clamped value as the live poll interval. Commits are now
      coalesced and skipped while a field has focus.
- [x] **LOW-7 — the `--max-filesize` comment overstated its own protection.**
      See the trap below.

### Still open, in the order I would do them

The four trivial ones first — a marketplace reviewer notices these before any of
the rest.

- [ ] **LOW-1 — `bar.barForeground` instead of `barForeground`, 23 places.**
      **18 `TypeError`s per panel construction, measured.** One `sed`. Stock
      panels have zero occurrences; `clock/Panel.qml:79-80` guards it explicitly.
- [ ] **LOW-2 — `switchPanel` never overridden.** Panel-switch keys do nothing.
      Four lines, copied from `clock/Panel.qml:113-117`.
- [ ] **LOW-3 — no `ipcTarget`,** so `omarchy shell summon|hide|toggle
      murankar.eso-server-status` does nothing. All ten stock panels set it.
- [ ] **LOW-6 — `~/.curlrc` is not disabled.** Add `-q`, or the README's
      "certificate verification stays enabled" is a claim about the *user's* rc
      rather than about the plugin.
- [ ] **LOW-4 — `apply()` accepts an array as `servers`.** `{"servers":[true,false]}`
      renders two rows named `0` and `1`. Add `Array.isArray(servers)`.
- [ ] **LOW-5 — `mutedServers` is never pruned** and grows monotonically in
      `shell.json`; a server the site drops returns pre-muted. **This one is a
      policy call, not just a bug** — keeping it is defensible, it just needs to
      be a decision on record.
- [ ] **LOW-8 — `manifest.json:18` hardcodes "all 7 ESO servers"** in the
      marketplace-visible description. Goes stale on the next fleet change.
- [ ] **LOW-9 — `Service.qml`'s `property var shell` is injected and never
      read.** The real issue is the undocumented coupling underneath it: the
      service's entire settings channel is `BarWidget.pushSettings()`, so with no
      widget in the bar it polls on hardcoded defaults. Comment it or drop it.
- [ ] **LOW-10 — `README.md:216` says "the four polling settings"; there are
      five.** The same file says "All five" two lines later.
- [ ] **Nits (7)** — unused `index` property, one misindented `Text`, the
      `siteLink` anchors, the plugin id hardcoded twice in `BarWidget.qml`,
      `toRgb` parsing before it length-checks.

### Not done, and not a decision yet

- [ ] **`omarchy restart shell`** — required before any of the above is live.
      `manifest.json:58` sets `keepLoaded: true`, and `shell.qml:1025-1035`
      deliberately retains such services across a hot-reload, so saving
      `Service.qml` logs "Local plugin changed, reloading" and applies nothing.
      **This is why the `--max-filesize` flag did nothing when it was first
      written, and it still applies to every LOW fix below** — none of them are
      active in the running shell until it is restarted.

### Traps hit while reviewing

- **`--max-filesize` needs curl 8.4.0.** Before that it had *no effect at all*
  on a response whose size is unknown before the download — which is exactly what
  this endpoint sends, since it returns no `Content-Length`. A user on an older
  distro had no protection while the comment claimed it. `maxBodyChars` in
  `apply()` is now the named backstop.
- **The threshold is a running total, not a per-chunk ceiling.** Measured: a 64
  MiB streamed body collects in full and exits 0 without the flag, and collects
  *exactly* 1048576 with it. Exactly, because a per-chunk check would have
  overshot. `--max-time` alone bounds nothing.
- **Do not trust a rich-text finding without a real window.** My first harness
  put the `Text` items in an unlaid-out parent and the fetch never happened,
  which briefly looked like the finding was wrong. With explicit geometry the
  `AutoText` item fetched and the `PlainText` one did not.
- **`qs` needs `file:` for absolute import paths,** not a bare path, and refuses
  to load the config otherwise. `Quickshell 0.3.1` has no `StreamSink`, so test
  output goes out through `Process` + `sh -c 'printf … "$@"'` with each line as
  an argv element — several of the hostile test strings would not survive being
  interpolated into a shell string.
- **A QML binding does not re-evaluate when an array is mutated in place.** The
  test writer's `command` binding went stale and emitted an empty file for the
  same reason `Service.qml` reassigns `serverList` wholesale. Assign
  `command` imperatively in anything that builds argv from a growing list.
- **`bar.barForeground` errors are real and loud, not theoretical.** Loading
  `Panel.qml` bare — exactly the state the bar widget's `Loader` creates it in —
  produced 18 of them and nothing else, which is also how the review edits were
  confirmed to have introduced no new failure of their own.
- **Harnesses are in `/tmp/opencode/`, not committed.** The `Service.qml` one
  runs 41 assertions against the real file, paused from birth so the poll timer
  never touches the network. It verifies logic, not the wiring the shell does
  around it, and it does not survive a reboot.


