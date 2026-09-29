# ESO Server Status

An [Omarchy](https://omarchy.org/) status-bar widget that watches
[esoserverstatus.net](https://esoserverstatus.net/) and colours a single glyph
according to the health of the Elder Scrolls Online server fleet.

| State | Colour | Meaning |
|---|---|---|
| Green | all 7 servers online | nothing to do |
| Orange | any mix | partial outage, or a server flagged "ongoing issues" |
| Red | all 7 servers offline | total outage |
| (neutral) | last reading is stale | the endpoint could not be reached |

## Requirements

- Omarchy with the Quickshell-based `omarchy-shell` bar (developed and verified
  against Omarchy on Hyprland 0.56.2, Quickshell 0.3.1)
- `curl` on `PATH` — the plugin shells out to it for each poll
- `omarchy-launch-browser` and `omarchy-notification-send` (both ship with
  Omarchy)
- Outbound HTTPS to `esoserverstatus.net`
- A Nerd Font covering U+EB50 for the glyph to render

There is no build step and no runtime dependency beyond the above. The plugin
reads `https://esoserverstatus.net/api/refresh`, the same public JSON endpoint
the website's own page uses. No API key is required.

## Install

### Recommended: managed install, updates with `omarchy plugin update`

```bash
omarchy plugin add https://github.com/murankar/omarchy-eso-server-status.git --enable
```

`omarchy plugin add` clones the repo into `~/.config/omarchy/plugins/murankar.eso-server-status/`,
validates the manifest, and enables the widget. It will ask which bar section to
use, defaulting to the right-hand section. The command will warn you first that
shell plugins run as unsandboxed code inside the long-lived `omarchy-shell`
process — this is expected, and it is a fair moment to read the source.

Verify with `omarchy plugin list | grep eso`.

From then on, updates are a first-class operation:

```bash
omarchy plugin update                           # all git-managed plugins
omarchy plugin update murankar.eso-server-status # just this one
```

`omarchy plugin update` discovers managed plugins by looking for a `.git`
directory in each plugin folder, fetches `origin`, shows you the diff, asks for
confirmation, and fast-forwards. It re-validates the manifest afterwards and
rolls back if the update does not validate, so a bad release cannot leave you
with a broken shell.

Two things worth knowing:

- Updates are **fast-forward only**. If you edit files inside your installed
  copy and commit them, the update will refuse rather than clobber your work
  (it will tell you to reset or reinstall). For local changes, use the
  development install below instead.
- After an update, run `omarchy restart shell`. The plugin's service is
  declared `keepLoaded`, so bar-widget changes hot-reload on their own but
  service changes need a restart to take effect.

Uninstalling:

```bash
omarchy plugin remove murankar.eso-server-status
```

### Development install

For working on the plugin, or if you prefer to manage it yourself:

```bash
git clone https://github.com/murankar/omarchy-eso-server-status.git \
  ~/.config/omarchy/plugins/murankar.eso-server-status
omarchy-shell shell rescanPlugins
omarchy plugin enable murankar.eso-server-status
```

This works identically — `omarchy plugin update` will still manage the
checkout, since it is a git repository — but it fails if you push local
commits, because updates require a fast-forward.

Do not use both methods on the same machine. `omarchy plugin add` refuses to
proceed when a plugin id is already present; if you previously hand-installed
the plugin, remove `~/.config/omarchy/plugins/murankar.eso-server-status` before running
it.

## Usage

| Action | Result |
|---|---|
| **Hover** | Tooltip reads `ESO Server Status` (or `ESO Server Status - 6/7 online` when the `detail` setting is on) |
| **Left click** | Toggles the per-server panel |
| **Right click** | Opens <https://esoserverstatus.net/> in your browser |
| **Middle click** | Forces an immediate re-poll instead of waiting out the current interval |

The widget is hidden entirely until the first successful response arrives, so it
never appears in the bar as a meaningless empty slot during startup.

### The server panel

Left click opens a popout under the bar entry listing all seven servers, each
coloured by its own reported state rather than by the fleet as a whole:

| State | Colour | Meaning |
|---|---|---|
| `online` | green | The service reported `true` |
| `ongoing issues` | amber | The service reported `2`: reachable, but impaired |
| `offline` | red | The service reported `false` |
| `unknown` | dimmed | The last poll failed, so no state is being claimed |

Amber is deliberately distinct from red: a server reporting ongoing issues is
still up, and collapsing the two would overstate the severity.

The panel opens under the bar entry, closes on outside click, on `Escape`, and
via the shell's normal panel dismissal, and carries its own link to the site so
right click is never the only route there. It is a pure view: it never performs
a request of its own, so opening it does not change the request budget below.

### Tabs

The panel has two tabs, set between a pair of dividers and drawn the same way as
the DNS provider row in the network panel, so the two read as the same control:

| Tab | Contents |
|---|---|
| **Servers** | The seven-server list, plus the site link |
| **Settings** | The four polling settings below |

### Settings

All five are editable from the panel's **Settings** tab and are stored in your
`~/.config/omarchy/shell.json`.

| Tab label | Key | Default | Effect |
|---|---|---|---|
| `Pause polling` | `paused` | `false` | Stop polling entirely and hold the last known status |
| `Healthy poll (s)` | `healthyInterval` | `300` | Seconds between polls while all servers are online |
| `Incident poll (s)` | `alertInterval` | `60` | Seconds between polls while an incident is open |
| `Notify on recovery` | `notifyRecovery` | `true` | Send a desktop notification when all servers come back online |
| `Count in tooltip` | `detail` | `false` | Append ` - N/7 online` to the tooltip |

A new interval takes effect on the next poll; nothing needs restarting. The
numeric fields are bounded to the same minimums the service clamps to, so a
value cannot be entered that the service would silently override.

**Pausing** spends no requests at all, which is the point if you are on a
metered link or simply do not want the icon to change under you. Resuming
forces an immediate refresh rather than waiting out the interval that was left
over, so the panel never presents pre-pause data as current.

Because the counts really are last-known while paused, the plugin stops
claiming a live status everywhere at once. Four surfaces change together, so
the state is unambiguous wherever you happen to be looking:

| Surface | While paused | While live |
|---|---|---|
| Bar glyph | Plain foreground, same as the other bar glyphs | Green / amber / red by fleet status |
| Bar tooltip | `polling paused` | Status count, with `detail` on |
| Panel header | `Polling paused - N of 7 servers online` | `N of 7 servers online` |
| Every server row | `paused`, dot in the server name's own colour | That server's state and colour |

The per-row change is the important one: a green or red dot next to the word
`paused` would be a state claim the plugin has withdrawn, so while paused each
row's dot and status take the same neutral colour as the server name. Nothing
on screen can be misread as a live reading. Turning polling back on restores
the glyph and every row to the appropriate colour on the next refresh.

## Request budget

The widget is deliberately frugal, because it polls a small third-party
endpoint and outages are rare and long.

**One poller per shell process.** All networking lives in the plugin's
`service` kind, which the shell instantiates exactly once. The bar widget
itself never issues a request, so a three-monitor setup still makes one request
per interval rather than three.

**Asymmetric cadence.** A healthy machine polls rarely; the frequent cadence is
spent only while an incident is actually open, which is the only window where
freshness matters to a user.

| Situation | Interval | Requests/day |
|---|---|---|
| All servers online | 300s | 288 |
| Incident open | 60s | 1440 |
| Endpoint unreachable | 60 → 600s backoff | 144 |

**Exponential backoff** on transport failure (60, 120, 240, 480, 600s), so an
offline network cannot turn the widget into a request flood.

**A stale reading never lies.** If a poll fails the last known status is kept
but the glyph drops to the neutral foreground colour, so a dead endpoint cannot
read as "all clear".

## Privacy and network behaviour

This is a network client, so it is worth being precise about what it sends.

**One endpoint, nothing else.** The only address the plugin ever contacts is:

```
https://esoserverstatus.net/api/refresh
```

There is no analytics, no telemetry, no crash reporting, no update check, and
no home-server-style beacon. The widget never contacts a developer, a package
registry, or any third party other than the site it displays.

**No data is collected, stored, or transmitted.** The plugin reads a public
status document and renders a colour. It writes no files, keeps no database,
sends no identifiers, and has no configuration that could be used to report
anything back. Nothing it learns is transmitted onward.

**What the site can see.** Like any HTTP client, the request necessarily reveals
your IP address and the `curl` user agent to the site, plus the two headers the
endpoint requires. The plugin sets no cookies and stores none — `curl` is
invoked without a cookie jar, so any session cookie in the response is ignored
and not persisted. There is no way to use this widget without the site seeing
that your machine contacted it, which is the same exposure as visiting the
status page yourself.

**When it contacts the site.** Only while the plugin is installed and enabled,
at the cadence in the table above — 300s while healthy, 60s during an incident,
and backing off to 600s on transport failure. Uninstalling the plugin ends all
outbound traffic:

```bash
omarchy plugin remove murankar.eso-server-status
```

**Right click**, or the link at the foot of the panel, is a separate,
user-initiated request: it opens <https://esoserverstatus.net/> in your browser
exactly as clicking the link in this README would. Opening the panel itself is
not a network request.

**HTTPS only, and no redirects.** The URL is a hardcoded `https://` constant and
`curl` is invoked without `-L`, so the request cannot be redirected to a
plaintext or third-party host. Certificate verification stays enabled — `-k` is
never used — and no credentials are ever sent, since the invocation includes
neither `--user` nor `--netrc`.

## Theming

Colours come from your active Omarchy theme and update live on a theme switch.

Theme colour *names* are not reliably semantic across themes — `lumon` ships a
blue under `green`, `lupine` a purple, `white` a grey, and several others are
similarly mismapped. `Theme.js` therefore parses the active theme's palette and
selects the first candidate whose **actual hue** falls in the required band,
falling back to a fixed, hue-correct constant when a theme offers nothing
usable. Tested across all 21 stock Omarchy themes; every one produces a correct
green, orange, and red.

## Architecture

```
Service.qml    one per shell process; owns the Process, the Timer, and all state
BarWidget.qml  per bar surface; reads published state, renders, handles input
Panel.qml      per bar surface; the popout list, a view onto the same service
Theme.js       hue-aware colour selection from the active theme's palette
manifest.json  plugin metadata and the settings schema
```

The split matters: the widget can be instantiated many times (one per monitor)
while the service cannot, which is what keeps the request count independent of
monitor count.

`Panel.qml` is nested inside the bar widget rather than declared as its own
entry point. It is handed the live service object, so it is a view and never a
second source of truth: opening the panel adds no polling, and it cannot drift
from what the bar glyph reports.

`service` is declared `keepLoaded: true` so that editing and hot-reloading the
bar widget cannot orphan the live service object. The trade-off is that changes
to the service itself need `omarchy restart shell` rather than the usual
automatic reload.

## Development

```bash
omarchy plugin validate ~/.config/omarchy/plugins/murankar.eso-server-status
omarchy restart shell        # required after editing Service.qml
```

Bar-widget edits hot-reload on save. Watch the log with:

```bash
journalctl --user -f | grep eso
```

A widget failing to load is logged as `Plugin widget murankar.eso-server-status failed`
with the QML error; a widget that loads but silently shows nothing is usually a
missing `implicitWidth`/`implicitHeight` on the root item.

To confirm the request behaviour, the network calls are visible as `curl`
processes while a poll is in flight.

## Credits

Data from [esoserverstatus.net](https://esoserverstatus.net/), which is not
affiliated with ZeniMax Online Studios or Bethesda Softworks.

## License

MIT — see [LICENSE](LICENSE). In short: use it however you like, including
commercially, but keep the copyright notice in any copy or substantial portion
of the plugin.

Built by Matthias Urankar.
