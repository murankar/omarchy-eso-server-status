import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Theme.js" as Theme
import "Servers.js" as Servers

// The popout listing every server with its own status colour.
//
// This panel is pure view: it performs no I/O and never contacts the network.
// All state arrives by injection from the bar widget, which reads it from the
// single shared service. That keeps the request count independent of how many
// panels are open.
//
// The colours are resolved from the active theme by measured hue for the same
// reason the bar glyph is: several stock themes ship a mismapped `green`.
Panel {
  id: root

  // Injected by the bar widget.
  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  readonly property var barIdentity: hostWidget || root

  readonly property var servers: service && service.serverList ? service.serverList : []

  // The same rows in panel order: NA, then EU, then the public test server,
  // each group alphabetical by display name. Sorted on a copy so the service's
  // list stays in whatever order the site sent it.
  readonly property var orderedServers: {
    var rows = root.servers.slice()
    rows.sort(Servers.compare)
    return rows
  }

  // What the repeater actually walks: a heading per region, then its servers.
  // Built here rather than with nested repeaters so one delegate draws both,
  // and so a group heading cannot end up separated from its rows.
  readonly property var serverRows: {
    var out = []
    var group = null
    for (var i = 0; i < root.orderedServers.length; i++) {
      var server = root.orderedServers[i]
      var region = Servers.region(server.name)
      if (region !== group) {
        group = region
        // A name carrying no region gets no heading: there is nothing to
        // group it under, and an empty band above it would just be noise.
        if (region !== "")
          out.push({ heading: true, label: Servers.groupLabel(region) })
      }
      out.push({ heading: false, server: server, label: Servers.label(server.name) })
    }
    return out
  }
  readonly property int onlineCount: service ? service.onlineCount : -1
  readonly property int totalCount: service ? service.totalCount : 0
  readonly property bool stale: service ? service.stale : false
  readonly property bool hasReading: service ? service.hasReading : false
  // The service owns the real switch, so the toggle reflects what actually
  // gates the polls rather than just what is in the settings object.
  readonly property bool paused: service ? service.paused : root.boolSetting("paused", false)

  // True when at least one server currently listed is muted. Derived from the
  // live rows rather than from the stored list, so a name the site has since
  // dropped does not keep the panel talking about a selection it cannot show.
  readonly property bool anyMuted: {
    for (var i = 0; i < root.servers.length; i++)
      if (root.isMuted(root.servers[i].name)) return true
    return false
  }

  // Left click used to open the site, so the poll settings had nowhere to live
  // except a hand-edited shell.json. They get a tab now.
  property int tab: 0


  readonly property var tabs: ["Servers", "Settings"]

  function intSetting(name, fallback) {
    var raw = root.settings ? root.settings[name] : undefined
    if (raw === undefined || raw === null) return fallback
    var n = Number(raw)
    return isFinite(n) ? Math.round(n) : fallback
  }

  function boolSetting(name, fallback) {
    var raw = root.settings ? root.settings[name] : undefined
    return (raw === undefined || raw === null) ? fallback : !!raw
  }

  // Push into the service as well as persisting, so a new interval takes effect
  // on the next poll instead of waiting for the shell.json write to come back
  // through the bar. The service re-reads its intervals on every poll, so no
  // restart is needed.
  //
  // The write is seeded from the service's settings rather than this panel's
  // own copy. More than one panel instance can be alive at once — the bar
  // keeps a hidden one loaded next to the one in the popout — and only the
  // service is updated by every write. Seeding from a stale instance would hand
  // a later edit back an older entry and quietly drop an earlier one.
  function setSetting(key, value) {
    var base = root.service && root.service.settings ? root.service.settings : root.settings
    var entry = { id: root.moduleName }
    if (base) for (var k in base) if (k !== "id") entry[k] = base[k]
    entry[key] = value
    root.settings = entry
    if (root.service) root.service.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // The server names the user has switched off, straight out of the settings
  // object the service also reads, so a row's switch and the glyph's verdict
  // can never disagree about who is muted.
  //
  // Duck-typed, never Array.isArray(), for the reason given in Service.qml: the
  // array crosses a JS realm boundary on its way in from the shell, and isArray
  // answers false for a real array. The two copies of this guard have to agree
  // or a switch stops matching its own row.
  function mutedList() {
    var raw = root.settings ? root.settings.mutedServers : undefined
    if (!raw || typeof raw.length !== "number") return []
    var names = []
    for (var i = 0; i < raw.length; i++) names.push(String(raw[i]))
    return names
  }

  // The list the next write is built from. The service copy is authoritative
  // for the same reason setSetting seeds from it: this instance's own settings
  // can be a write behind, and toggling off a stale list would put a server
  // back on that another panel had just switched off.
  function storedMutedList() {
    var raw = root.service && root.service.settings ? root.service.settings.mutedServers : undefined
    if (!raw && root.settings) raw = root.settings.mutedServers
    if (!raw || typeof raw.length !== "number") return []
    var names = []
    for (var i = 0; i < raw.length; i++) names.push(String(raw[i]))
    return names
  }

  // Read per row rather than carried on the polled server list, so a switch
  // moves the instant it is clicked instead of a poll later. The poll it waits
  // for only has to catch the counts and the verdict up.
  function isMuted(name) {
    return root.mutedList().indexOf(name) !== -1
  }

  // Copy before editing. The stored array is the same object the service holds
  // and, in a binding, the one QML compares references on -- splicing it in
  // place would rewrite the stored value and never notify anything.
  //
  // The refresh is forced for the same reason resuming from a pause forces
  // one: the glyph is currently showing a verdict computed over a set the user
  // has just changed, and leaving that on screen until the interval expires
  // would mean showing a fleet the plugin has stopped watching. Mid-poll the
  // service ignores this and the next poll settles it anyway.
  function toggleMonitored(name) {
    var list = root.storedMutedList()
    var index = list.indexOf(name)
    if (index === -1) list.push(name)
    else list.splice(index, 1)
    root.setSetting("mutedServers", list)
    if (root.service) root.service.lastPollAt = 0
  }


  FileView {
    id: paletteFile
    path: Color.home + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
  }

  readonly property var palette: Theme.parsePalette(paletteFile.text())

  readonly property color greenColor: Theme.pick(palette,
    ["green", "bright_green", "color2", "color10", "color42"], "green", "#26a269")
  readonly property color orangeColor: Theme.pick(palette,
    ["orange", "bright_orange", "accent", "yellow", "bright_yellow", "color3", "color11", "color214"], "orange", "#e69138")
  readonly property color redColor: Theme.pick(palette,
    ["red", "bright_red", "color1", "color9", "color88"], "red", "#dc3545")

  // A server with reported problems reads amber, not red: it is still up.
  //
  // Muted is checked first and is the only case that claims nothing at all.
  // Paused is checked before stale and deliberately takes the server name's
  // own colour. A coloured dot beside the word "paused" would be a state claim
  // the panel has withdrawn, so the whole row goes neutral: dot, status and
  // name all in barForeground. Nothing on screen can then be misread as live.
  function colorForState(state, muted) {
    if (muted) return root.dimmed
    if (root.paused) return bar.barForeground
    if (root.stale) return root.dimmed
    if (state === "online") return root.greenColor
    if (state === "issues") return root.orangeColor
    return root.redColor
  }

  // The panel never claims a freshness it does not have. A failed poll and a
  // paused poll both mean the counts below are last-known rather than current,
  // so both are said out loud instead of being shown as a live reading.
  // Muting every server is the same kind of claim to refuse: the poll worked,
  // and the answer is that nothing is being watched.
  function subtitle() {
    if (root.onlineCount < 0)
      return root.hasReading ? "No servers monitored" : "Waiting for first update"
    var counts = root.onlineCount + " of " + root.totalCount
      + (root.anyMuted ? " monitored" : "") + " servers online"
    if (root.paused) return "Polling paused - " + counts
    if (root.stale) return "Could not reach esoserverstatus.net"
    return counts
  }

  function textForState(state, muted) {
    if (muted) return "muted"
    if (root.paused) return "paused"
    if (root.stale) return "unknown"
    if (state === "online") return "online"
    if (state === "issues") return "ongoing issues"
    return "offline"
  }

  readonly property color dimmed: Qt.rgba(barForeground.r, barForeground.g, barForeground.b, 0.45)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)



    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
    }

    Column {
      id: body
      // Track the card's inset content area rather than the raw card width.
      // contentHolder is already inset by the popup padding and the border, so
      // using panel.contentWidth here overflows to the right and lets the
      // border cut through the text.
      width: parent.width
      spacing: Style.space(10)

      // Header
      Column {
        width: parent.width
        spacing: Style.space(2)

        Text {
          text: "ESO Server Status"
          color: bar.barForeground
          font.family: Style.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
        }

        Text {
          text: root.subtitle()
          // Accent when the count is a real reading, dimmed when it is not:
          // a stale or paused fleet has no count worth drawing attention to,
          // and tinting "could not reach esoserverstatus.net" would dress a
          // failure up as a result.
          color: (root.stale || root.paused || root.onlineCount < 0)
            ? Qt.rgba(bar.barForeground.r, bar.barForeground.g, bar.barForeground.b, 0.65)
            : Color.accent
          font.family: Style.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: bar.barForeground
      }

      // Tab pills, built the same way as the network panel's DNS provider row
      // so the two panels read as the same kind of control: equal-width cells,
      // outlined, with the current one filled.
      Row {
        id: tabRow
        width: parent.width
        spacing: Style.space(6)

        readonly property int count: root.tabs.length
        readonly property real cellWidth: (width - spacing * (count - 1)) / count

        Button {
          text: root.tabs[0]
          width: tabRow.cellWidth
          active: root.tab === 0
          bordered: true
          foreground: bar.barForeground
          fontFamily: Style.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          onClicked: root.tab = 0
        }

        Button {
          text: root.tabs[1]
          width: tabRow.cellWidth
          active: root.tab === 1
          bordered: true
          foreground: bar.barForeground
          fontFamily: Style.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          onClicked: root.tab = 1
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: bar.barForeground
      }

      Column {
        id: serversTab
        width: parent.width
        spacing: Style.space(10)
        visible: root.tab === 0

        // One row per server, coloured by its own state rather than the fleet's.
        //
        // The trailing switch is the row's own control, so the row owns the
        // click and the switch is marked non-interactive: one input, one place
        // that flips a server. Hover fill matches the site link below, so the
        // clickable half of the tab looks the same in both places.
        Repeater {
          model: root.serverRows

          delegate: Rectangle {
            id: serverRow
            required property var modelData
            required property int index

            readonly property bool heading: modelData.heading === true
            readonly property bool muted: !serverRow.heading
              && root.isMuted(modelData.server.name)
            // A heading row carries no server, so its state reads as absent.
            // Every binding below uses this instead of reaching into
            // modelData.server directly: an undefined read is a QML error on
            // every heading, and errors on rows nobody is looking at still
            // fill the journal.
            readonly property string rowState: serverRow.heading
              ? "" : modelData.server.state

            // Server rows sit inside their region's heading rather than
            // beside it, so the grouping reads as nesting instead of as two
            // columns that happen to line up. Roughly four spaces at the body
            // size, and on the theme's spacing scale so a roomier theme gets a
            // roomier indent. Headings keep the flush-left edge they already
            // had: they are the thing being indented away from.
            readonly property int indent: serverRow.heading ? 0 : Style.space(14)

            width: serversTab.width
            // A heading is a label for the rows under it, so it is shorter
            // than a row and the column's own spacing gives it the air.
            height: serverRow.heading ? Style.space(16) : Style.space(30)
            radius: Style.cornerRadius
            color: !serverRow.heading && rowHover.hovered
              ? Style.hoverFillFor(bar.barForeground, Color.accent)
              : "transparent"

            // Only a server row is clickable: a heading has no server behind
            // it to toggle, and swallowing the click would silently do nothing.
            HoverHandler {
              id: rowHover
              enabled: !serverRow.heading
            }

            TapHandler {
              enabled: !serverRow.heading
              onTapped: root.toggleMonitored(serverRow.modelData.server.name)
            }

            // The heading: the region name, plus a hairline to separate it from the
            // group above. Sits flush left so it lines up with the server
            // names rather than with the dots.
            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(2)
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(1)
              visible: serverRow.heading
              // Plain text, never rich: a heading is a region name taken
              // straight from the payload, and Qt's default (AutoText) would
              // let the endpoint hand us markup. A <img src="..."> in a name
              // is not inert -- Qt's rich-text loader fetches it, which is an
              // outbound request to a host of the endpoint's choosing, once per
              // poll. Servers.plain() is the second line of defence; this is
              // the one that actually holds.
              textFormat: Text.PlainText
              text: modelData.label
              elide: Text.ElideRight
              // The theme's accent, not the status colour: a heading is
              // structure, not a verdict, and a green heading next to a green
              // "online" row would read as a server that is up.
              color: Color.accent
              font.family: Style.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              font.capitalization: Font.AllUppercase
              font.letterSpacing: 0.6
            }

            Rectangle {
              id: dot
              visible: !serverRow.heading
              width: Style.space(8)
              height: Style.space(8)
              radius: width / 2
              anchors.left: parent.left
              anchors.leftMargin: Style.space(2) + serverRow.indent
              anchors.verticalCenter: parent.verticalCenter
              color: root.colorForState(serverRow.rowState, serverRow.muted)
            }

            ToggleSwitch {
              id: monitorSwitch
              visible: !serverRow.heading
              anchors.right: parent.right
              anchors.rightMargin: serverRow.indent
              anchors.verticalCenter: parent.verticalCenter
              checked: !serverRow.muted
              // The row handles the click; the switch only reports the value.
              interactive: false
              foreground: bar.barForeground
            }

            // Right-aligned, sitting clear of the switch by the gap the
            // settings rows use between a label and its control. The name is
            // bounded by the status rather than the row edge, so the two cannot
            // overlap when the label is the longer of the pair ("ongoing
            // issues").
            //
            // A heading states nothing, so it renders no status at all -- and
            // not merely a hidden one. textForState falls through to "offline"
            // for a state it does not recognise, so a heading that only set
            // `visible: false` would still evaluate to "offline" beside NA and
            // EU. Nothing draws it today, but the row would be one binding
            // change away from claiming a server is down.
            Text {
              id: statusText
              visible: !serverRow.heading
              anchors.right: monitorSwitch.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: serverRow.heading
                ? "" : root.textForState(serverRow.rowState, serverRow.muted)
              color: root.colorForState(serverRow.rowState, serverRow.muted)
              font.family: Style.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: !serverRow.heading
              anchors.left: dot.right
              anchors.leftMargin: Style.space(10)
              anchors.right: statusText.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              // The display name, not the payload key: the panel reads
              // region-first while the settings still store the site's name.
              // Plain text for the same reason as the heading above: this is
              // the label a hostile endpoint controls most directly, since any
              // string with no usable region reaches label() verbatim.
              textFormat: Text.PlainText
              text: modelData.label
              elide: Text.ElideRight
              color: serverRow.muted ? root.dimmed : bar.barForeground
              font.family: Style.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: bar.barForeground
        }

        // Reachable without leaving the panel, since left click no longer opens
        // the site directly.
        Rectangle {
          id: siteLink
          width: parent.width
          height: Style.space(24)
          radius: Style.cornerRadius
          color: siteHover.hovered
            ? Style.hoverFillFor(bar.barForeground, Color.accent)
            : "transparent"

          HoverHandler {
            id: siteHover
          }

Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Open esoserverstatus.net"
            color: bar.barForeground
            font.family: Style.fontFamily
            font.pixelSize: Style.font.caption
            font.underline: siteHover.hovered
          }

          TapHandler {
            onTapped: {
              Quickshell.execDetached(["omarchy-launch-browser", "https://esoserverstatus.net/"])
              root.close()
            }
          }
        }
      }

      // ---- Settings tab ----
      Column {
        id: settingsTab
        width: parent.width
        spacing: Style.space(4)
        visible: root.tab === 1

        // Pause sits above the intervals on purpose: while it is on, the two
        // intervals below describe a poll that is not happening. Resuming forces
        // a refresh in Service.qml, so this is not a mute-then-wait switch.
        Item {
          width: parent.width
          height: Style.spacing.controlHeight

          ToggleSwitch {
            id: pauseSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.paused
            foreground: bar.barForeground
            onToggled: root.setSetting("paused", !root.paused)
          }

          Text {
            anchors.left: parent.left
            anchors.right: pauseSwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "Pause polling"
            elide: Text.ElideRight
            color: bar.barForeground
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        // Each row is an Item, not a Row: a Row positions its children itself
        // and rejects anchors, which is what puts the control on the trailing
        // edge. Labels are bounded by the control and elide, so a longer
        // label or a larger theme font can never overlap the control.
        //
        // Numeric ranges mirror the clamps in Service.qml, so a value cannot be
        // set that the service would silently override.
        Item {
          width: parent.width
          height: Style.spacing.controlHeight

          NumberField {
            id: healthyField
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: ""
            from: 120
            to: 3600
            stepSize: 30
            value: root.intSetting("healthyInterval", 300)
            foreground: bar.barForeground
            fontFamily: Style.fontFamily
            fontSize: Style.font.bodySmall
            onModified: function(v) { root.setSetting("healthyInterval", v) }
          }

          Text {
            anchors.left: parent.left
            anchors.right: healthyField.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "Healthy poll (s)"
            elide: Text.ElideRight
            color: bar.barForeground
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Item {
          width: parent.width
          height: Style.spacing.controlHeight

          NumberField {
            id: alertField
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: ""
            from: 30
            to: 1800
            stepSize: 30
            value: root.intSetting("alertInterval", 60)
            foreground: bar.barForeground
            fontFamily: Style.fontFamily
            fontSize: Style.font.bodySmall
            onModified: function(v) { root.setSetting("alertInterval", v) }
          }

          Text {
            anchors.left: parent.left
            anchors.right: alertField.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "Incident poll (s)"
            elide: Text.ElideRight
            color: bar.barForeground
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Item {
          width: parent.width
          height: Style.spacing.controlHeight

          ToggleSwitch {
            id: recoverySwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.boolSetting("notifyRecovery", true)
            foreground: bar.barForeground
            onToggled: root.setSetting("notifyRecovery", !root.boolSetting("notifyRecovery", true))
          }

          Text {
            anchors.left: parent.left
            anchors.right: recoverySwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "Notify on recovery"
            elide: Text.ElideRight
            color: bar.barForeground
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Item {
          width: parent.width
          height: Style.spacing.controlHeight

          ToggleSwitch {
            id: detailSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.boolSetting("detail", false)
            foreground: bar.barForeground
            onToggled: root.setSetting("detail", !root.boolSetting("detail", false))
          }

          Text {
            anchors.left: parent.left
            anchors.right: detailSwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "Count in tooltip"
            elide: Text.ElideRight
            color: bar.barForeground
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
