import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Theme.js" as Theme

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
  readonly property int onlineCount: service ? service.onlineCount : -1
  readonly property int totalCount: service ? service.totalCount : 0
  readonly property bool stale: service ? service.stale : false
  // The service owns the real switch, so the toggle reflects what actually
  // gates the polls rather than just what is in the settings object.
  readonly property bool paused: service ? service.paused : root.boolSetting("paused", false)

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
  function setSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.service) root.service.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
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
  // Paused is checked before stale and deliberately takes the server name's
  // own colour. A coloured dot beside the word "paused" would be a state claim
  // the panel has withdrawn, so the whole row goes neutral: dot, status and
  // name all in barForeground. Nothing on screen can then be misread as live.
  function colorForState(state) {
    if (root.paused) return bar.barForeground
    if (root.stale) return root.dimmed
    if (state === "online") return root.greenColor
    if (state === "issues") return root.orangeColor
    return root.redColor
  }

  // The panel never claims a freshness it does not have. A failed poll and a
  // paused poll both mean the counts below are last-known rather than current,
  // so both are said out loud instead of being shown as a live reading.
  function subtitle() {
    if (root.onlineCount < 0) return "Waiting for first update"
    var counts = root.onlineCount + " of " + root.totalCount + " servers online"
    if (root.paused) return "Polling paused - " + counts
    if (root.stale) return "Could not reach esoserverstatus.net"
    return counts
  }

  function textForState(state) {
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
          color: (root.stale || root.paused) ? root.dimmed : Qt.rgba(bar.barForeground.r, bar.barForeground.g, bar.barForeground.b, 0.65)
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
        Repeater {
          model: root.servers

          delegate: Rectangle {
            required property var modelData
            required property int index

            width: serversTab.width
            height: Style.space(26)
            radius: Style.cornerRadius
            color: "transparent"

            Rectangle {
              id: dot
              width: Style.space(8)
              height: Style.space(8)
              radius: width / 2
              anchors.left: parent.left
              anchors.leftMargin: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              color: root.colorForState(modelData.state)
            }

            // Right-aligned, sitting clear of the border by the content inset
            // plus this margin. The name is bounded by the status rather than
            // the row edge, so the two cannot overlap when the label is the
            // longer of the pair ("ongoing issues").
            Text {
              id: statusText
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: root.textForState(modelData.state)
              color: root.colorForState(modelData.state)
              font.family: Style.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.left: dot.right
              anchors.leftMargin: Style.space(10)
              anchors.right: statusText.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name
              elide: Text.ElideRight
              color: bar.barForeground
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
            anchors.left: parent.left
            anchors.leftMargin: Style.space(2)
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
