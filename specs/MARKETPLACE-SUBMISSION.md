### Repository URL

https://github.com/murankar/omarchy-eso-server-status

### Category

Widgets

### Tags

bar, system, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

Outbound network access is the plugin's only notable behaviour, so this may be
useful when reviewing the Automated Security Baseline result.

- The sole network call is a single `curl` in `Service.qml`, fetching a JSON
  status document from `https://esoserverstatus.net/api/refresh`. The response
  is parsed with `JSON.parse` and rendered. Nothing is piped to a shell,
  evaluated, or written to disk, so none of the baseline's
  download-to-shell patterns should apply.
- All networking lives in the `service` kind, so exactly one request is made per
  poll interval per shell process. The bar widget holds no `Process` and issues
  no requests, and a multi-monitor setup does not multiply the request count.
- The endpoint is polled every 300s while healthy, every 60s while an incident is
  open, and backs off 60s to 600s on transport failure.
- The plugin depends only on `curl`, `omarchy-launch-browser`, and
  `omarchy-notification-send` (both shipped with Omarchy). No API key, no build
  step, no bundled assets.
- The manifest declares `keepLoaded: true`, so editing `Service.qml` requires
  `omarchy restart shell` rather than a hot reload. Bar-widget edits hot-reload
  normally.
- Status colours are resolved from the active theme by measured hue rather than
  by colour name, because several stock Omarchy themes ship a mismapped
  `green`. Verified across all 22 stock themes.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
