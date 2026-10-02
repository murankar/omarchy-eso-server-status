# TODO

Working notes for `murankar.eso-server-status`. Moved into `specs/` and tracked
as of 1.4.1; these were gitignored and local-only up to 1.4.0.

Last updated: 2026-09-29

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

## 2. Marketplace submission — ON HOLD at owner's request (2026-09-29)

**Status: deliberately paused, not blocked.** Section 1 is complete, so this
*could* be filed today. The owner decided to hold publication. Do not submit
without a fresh, explicit go-ahead.

A complete, validated draft is saved in this directory as
`MARKETPLACE-SUBMISSION.md` (gitignored). It was checked mechanically against
the issue form: six headings in order, `Widgets` category, tags
`bar, system, quickshell`, and all five checklist lines byte-identical to the
official wording. `murankar.eso-server-status` is confirmed **available** in
`https://plugins.omarchy.org/catalog.json` (4,522 listings, no collision on the
id, and no existing listing by the author `murankar`).

To file it later:

```bash
gh issue create --repo omacom/omarchy-plugin-marketplace \
  --title "[Plugin]: ESO Server Status" \
  --body-file MARKETPLACE-SUBMISSION.md
```

Note the ID availability check is a point-in-time result. Re-query `catalog.json`
immediately before submitting, since ids are permanent and never reused.

Submit via: `omacom/omarchy-plugin-marketplace` →
[Submit a plugin](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml)

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
- [ ] Optional `preview.png` in the repo root — not present, not required

### Decisions needed before submitting

- [x] **Plugin ID.** Decided: `murankar.eso-server-status`.
- [x] **`author` field** — now `Matthias Urankar` (was the machine username
      `"uri"`, which the marketplace would have displayed publicly)
- [x] **Version** is `1.3.0` (bumped for per-server muting and the grouped
      server names). Tags `v1.2.0` and `v1.3.0` are both cut on the remote.
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

