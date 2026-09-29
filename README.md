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
| **Left click** | Opens <https://esoserverstatus.net/> in your browser |
| **Middle click** | Forces an immediate re-poll instead of waiting out the current interval |

The widget is hidden entirely until the first successful response arrives, so it
never appears in the bar as a meaningless empty slot during startup.

## Settings

All four are editable from the shell settings panel and are stored in your
`~/.config/omarchy/shell.json`.

| Key | Default | Effect |
|---|---|---|
| `healthyInterval` | `300` | Seconds between polls while all servers are online |
| `alertInterval` | `60` | Seconds between polls while an incident is open |
| `notifyRecovery` | `true` | Send a desktop notification when all servers come back online |
| `detail` | `false` | Append ` - N/7 online` to the tooltip |

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
Theme.js       hue-aware colour selection from the active theme's palette
manifest.json  plugin metadata and the settings schema
```

The split matters: the widget can be instantiated many times (one per monitor)
while the service cannot, which is what keeps the request count independent of
monitor count.

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
