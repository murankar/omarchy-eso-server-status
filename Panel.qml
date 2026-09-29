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
  function colorForState(state) {
    if (root.stale) return root.dimmed
    if (state === "online") return root.greenColor
    if (state === "issues") return root.orangeColor
    return root.redColor
  }

  function textForState(state) {
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
          text: root.stale
            ? "Could not reach esoserverstatus.net"
            : (root.onlineCount >= 0 ? root.onlineCount + " of " + root.totalCount + " servers online" : "Waiting for first update")
          color: root.stale ? root.dimmed : Qt.rgba(bar.barForeground.r, bar.barForeground.g, bar.barForeground.b, 0.65)
          font.family: Style.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: bar.barForeground
      }

      // One row per server, coloured by its own state rather than the fleet's.
      Repeater {
        model: root.servers

        delegate: Rectangle {
          required property var modelData
          required property int index

          width: body.width
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
  }
}
