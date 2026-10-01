# Patch Notes

Release notes for `murankar.eso-server-status`. Newest version first.

Versions follow the plugin's `manifest.json`. Each section covers what changed
for users of that version; the commit history has the implementation detail.

---

## 1.4.0 — 2026-10-01

A security and correctness release. No new features and no new settings; every
existing setting keeps its key, default, and behaviour.

The headline is that a compromised or hostile endpoint could previously cause
the plugin to contact a host of its choosing, and the recovery notification was
saying the opposite of what happened. Both are fixed, along with the resource
and I/O problems found alongside them.

### Security

**Server names are rendered as plain text.** A server name from the API
reached `Text` items that never set `textFormat`, so Qt 6 treated them as rich
text. A name of `<img src="http://attacker.example/">` was not inert: Qt's
rich-text loader fetched it, once per poll, from a long-running process with no
user interaction. Reproduced against a local server that logged every request —
the rich-text item fetched the injected image, the plain-text item made no
request at all.

Both items that render remote data now set `Text.PlainText`. Displayed names
are also reduced to a name-shaped alphabet (`A-Za-z0-9`, space, underscore,
period, hyphen), so a name that strips down to nothing reads as `Unknown`
rather than passing through. The stored payload key is untouched, so existing
`mutedServers` entries keep matching the key they were saved against.

This also makes the README's "one endpoint, nothing else" claim true of the
plugin rather than approximately true.

**A response body is bounded before it is parsed.** `curl --max-time` limits how
long a poll runs, not how much the collector can be made to hold. A hostile
endpoint can deliver far more than memory in well under ten seconds, and since
it sends no `Content-Length`, checking the size afterwards is already too late.
`--max-filesize` now caps collection at 1 MiB, and the body is refused before
`JSON.parse` if it is longer than 64 KiB.

The in-process guard exists because `--max-filesize` has no effect at all
before curl 8.4.0 on a response whose size is not known up front — which is
exactly what this endpoint sends. The parse is bounded either way.

Measured against a local server streaming 64 MiB with no `Content-Length`:
without the flag the full 64 MiB is collected and the process exits 0; with it,
exactly 1048576 bytes are collected and curl exits 63, which the plugin treats
as a transport failure and backs off from.

**An implausible fleet size is rejected.** The byte limit does not bound the
number of elements — 20 000 keys fit in about 200 KB — and the panel builds UI
per server. A payload claiming more than 256 servers is now refused, keeping the
last good reading intact. The real fleet is 7.

### Correctness

**The recovery notification now fires in the right direction.** It previously
appeared during an outage and stayed silent when servers actually came back.
Every incident, in both directions, the one user-facing notification was
inverted.

The cause was ordering rather than logic: the poll handler evaluates
`settle(apply(text))`, so the new status was already assigned before the check
ran, and the check compared the new verdict against itself. The verdict is now
snapshotted before the request goes out and the check reads that. A first
reading, which has no previous verdict, still stays silent.

**A poll that never reports can no longer wedge the widget.** The "poll in
progress" flag was cleared only by the process finishing or exiting, and neither
is guaranteed. When neither happened, polling stopped for the rest of the
session while the glyph went on showing its last known colour — a stale green
that nothing was checking.

A poll outstanding past 15 seconds is now failed by hand and retried, and
staleness is judged from two sources: a poll that reported a failure, and a
reading that has aged past its interval. A reading ages out on the clock even if
no poll ever completes, so a dead endpoint reads as stale rather than as healthy.
Pausing still suppresses the age check, keeping "paused" and "stale" distinct.

### Performance

**Editing a poll interval no longer rewrites `shell.json` on every keystroke.**
The numeric fields committed as they were typed, and a spin box clamps while
parsing, so typing `3600` into a field with a minimum of 120 committed 120, 120,
360, 3600 — four full writes, the first two of which were never numbers you
chose. The transient 120 briefly became the live poll interval, and then read
back as a deliberate setting.

Commits are now held and written once: when you look away from the field, after a
short pause, or when the panel closes. A value still being typed is never
committed. Writes that would not change anything are skipped entirely.

**Mute lookups are no longer quadratic.** Every row checked whether it was muted
by rebuilding a copy of the stored list, twice per row, so one poll allocated a
number of arrays proportional to rows × muted servers on the UI thread. Both the
panel and the service now build a lookup once per settings change, and the
service's per-poll scan over the same list is gone as well.

Mute state still updates the instant a switch is clicked rather than a poll
later.

### Panel and shell integration

These are the gaps a reviewer comparing against a stock Omarchy panel will
notice, since every first-party bar widget closes them.

- **The panel-switch keys now work.** Left, right, and the wrap-around keys did
  nothing, because the panel was passing itself to the bar where the bar
  expected its own widget. Overridden the way `clock` and `weather` do.
- **The panel can be summoned by hotkey or script.** With an `ipcTarget` set,
  `omarchy shell summon`, `hide`, and `toggle` reach it by plugin id.
- **No more QML errors on open.** The panel read `bar.barForeground` in 23
  places before the bar widget had been injected, so every construction logged
  18 `TypeError`s. It now uses the null-safe inherited colour, which is what
  stock panels use. The errors were harmless but visible in the log, and a
  reviewer checking `journalctl` would have seen them.
- **`~/.curlrc` can no longer alter the request.** A user's curl config carrying
  `-k`, `--proxy`, or `--netrc` would silently change what the plugin does —
  including turning off the certificate verification this README claims is left
  enabled. `curl -q` now disables the config file, which is what makes "one
  endpoint, nothing else" a property of the plugin rather than of the user's
  home directory.
- **An array is no longer accepted as the server map.** `typeof []` is
  `"object"`, so `{"servers":[true,false]}` passed the type check and rendered
  two rows named `0` and `1`. It is now refused like any other malformed
  payload.

### Documentation

- **Patch Notes** added: this file, linked from the README under Install and in
  Development.
- The bar widget description no longer hardcodes "all 7 servers", which goes
  stale on the next fleet change.
- The Settings tab description said four polling settings; there are five.

### Internal

- Working notes used for the review are excluded from version control.
- Each fix is a separate commit, so any one of them can be reverted on its own.

### Upgrade note

The plugin keeps a live service across a config reload, so `Service.qml` changes
need a shell restart to take effect:

```bash
omarchy restart shell
```

No settings migration is required: all five keys keep their names, defaults, and
meaning.

---

## 1.3.0 — 2026-09-30

A documentation and metadata release. No behaviour changed from 1.2.0.

- Refreshed the marketplace screenshots to match the current grouped, mutable
  panel.
- Re-validated the plugin against the marketplace's recorded baseline, which had
  gone stale against an earlier commit.

---

## 1.2.0 — 2026-09-29

Per-server muting and a reorganised panel.

### Added

- **Per-server muting.** Each row has its own switch. Muted servers stay listed
  so you can see them, but they are excluded from the counts and from the
  verdict — a fleet you are not watching does not paint your glyph.
- **Grouped server names.** Servers are listed under region headings — NA, then
  EU, then the public test server — each group alphabetical. A name carrying no
  region gets no heading, so there is no empty band above it.
- **Accent-coloured group headings**, so the structure is readable without
  competing with the per-server status colours.
- **Panel screenshots** and a marketplace preview image.
- **MIT license**, with the public author field corrected.

### Changed

- Screenshots and preview refreshed to the new grouped, mutable panel.
- The plugin id is now `murankar.eso-server-status` across the manifest and the
  bar widget, and the README documents the managed install so
  `omarchy plugin update` works.
- The README documents privacy and network behaviour precisely: one endpoint, no
  telemetry, no update check, certificate verification left enabled.

---

## 1.1.0 — 2026-09-29

First release.

### Added

- **Bar glyph** coloured by fleet health: green when all servers are online,
  amber for a partial outage or a server flagged "ongoing issues", red when all
  are offline, neutral when the last reading is stale.
- **Per-server status panel** on left click, showing each server's own state.
- **Servers / Settings tabs** in the panel.
- **Pause switch** that forces an immediate refresh on resume, so the panel never
  presents pre-pause data as current.
- **Paused state shown everywhere at once** — glyph, tooltip, panel header, and
  every row — so nothing on screen can be misread as a live reading.
- **Outage-aware polling.** One poller per shell regardless of monitor count.
  A healthy fleet polls every 300 s; an open incident polls every 60 s; nothing
  monitored polls rarely; transport failures back off exponentially from 60 s to
  600 s.

---

## Verification

The 1.4.0 fixes were verified rather than argued, using harnesses that drive the
plugin's real code paths:

- 51 assertions against the poll and parsing logic, all passing, including ten
  added for the mute-lookup change and coverage of inherited-property names.
- A live beacon test confirming the rich-text fetch reproduced before the fix and
  is absent after it.
- A 64 MiB streamed-body test confirming the size cap collects exactly 1 MiB and
  fails the poll.
- Panel construction checks confirming the mute and settings changes introduced
  no new errors, and that opening the panel now logs none of its own.
- Each array-payload assertion was checked against the unfixed code and fails
  there, so it is testing the fix rather than passing either way.

Known remaining gaps are tracked in the project's working notes. None of them
affect the fixes above; the one open design question is whether a server the
site stops listing should keep its muted entry, which currently means it returns
pre-muted if it ever comes back.
