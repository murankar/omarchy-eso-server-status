import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Theme.js" as Theme

BarWidget {
  id: root
  moduleName: "eso.server-status"

  readonly property string icon: ""

  // All networking lives in the service, so the cost is one request per
  // interval for the whole shell rather than one per bar surface.
  readonly property var service: {
    var api = root.bar ? root.bar.shell : null
    return api ? api.serviceFor("eso.server-status") : null
  }

  readonly property string status: service ? service.status : ""
  readonly property int onlineCount: service ? service.onlineCount : -1
  readonly property int totalCount: service ? service.totalCount : 0
  readonly property bool stale: service ? service.stale : false

  readonly property var palette: Theme.parsePalette(paletteFile.text())

  readonly property color greenColor: Theme.pick(palette,
    ["green", "bright_green", "color2", "color10", "color42"], "green", "#26a269")
  readonly property color orangeColor: Theme.pick(palette,
    ["orange", "bright_orange", "accent", "yellow", "bright_yellow", "color3", "color11", "color214"], "orange", "#e69138")
  readonly property color redColor: Theme.pick(palette,
    ["red", "bright_red", "color1", "color9", "color88"], "red", "#dc3545")

  // A stale reading falls back to the plain foreground rather than holding the
  // last known red/green, so a dead endpoint never reads as "all clear".
  readonly property color statusColor: stale ? (bar ? bar.barForeground : Color.foreground)
    : status === "green" ? greenColor
    : status === "red" ? redColor
    : status === "orange" ? orangeColor
    : (bar ? bar.barForeground : Color.foreground)

  visible: status !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function pushSettings() {
    if (root.service) root.service.settings = root.settings
  }

  onSettingsChanged: pushSettings()
  onServiceChanged: pushSettings()
  Component.onCompleted: pushSettings()

  FileView {
    id: paletteFile
    path: Color.home + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    slotSize: Style.bar.statusSlot
    activeColor: root.statusColor
    useActiveColor: true
    active: true
    tooltipText: setting("detail", false) && root.onlineCount >= 0
      ? "ESO Server Status - " + root.onlineCount + "/" + root.totalCount + " online"
      : "ESO Server Status"
    onPressed: function(b) {
      if (b === Qt.MiddleButton && root.service) root.service.lastPollAt = 0
      else Quickshell.execDetached(["omarchy-launch-browser", "https://esoserverstatus.net/"])
    }
  }
}
