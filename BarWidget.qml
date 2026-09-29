import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Theme.js" as Theme

BarWidget {
  id: root
  moduleName: "murankar.eso-server-status"

  readonly property string icon: ""

  // All networking lives in the service, so the cost is one request per
  // interval for the whole shell rather than one per bar surface.
  readonly property var service: {
    var api = root.bar ? root.bar.shell : null
    return api ? api.serviceFor("murankar.eso-server-status") : null
  }

  readonly property string status: service ? service.status : ""
  readonly property int onlineCount: service ? service.onlineCount : -1
  readonly property int totalCount: service ? service.totalCount : 0
  readonly property bool stale: service ? service.stale : false

  // Paused outranks the count: "polling paused" is the honest reading even
  // with detail on, because the count is last-known rather than current.
  readonly property string statusSuffix: service && service.paused
    ? "polling paused"
    : (setting("detail", false) && root.onlineCount >= 0
      ? root.onlineCount + "/" + root.totalCount + " online"
      : "")

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

  // One handler per signal, so the service-arrival path is centralised here:
  // settings get pushed into the service, and the panel is re-injected so it
  // picks up the same object.
  function onServiceArrived() {
    pushSettings()
    injectPanel()
  }

  onSettingsChanged: pushSettings()
  onServiceChanged: onServiceArrived()
  Component.onCompleted: onServiceArrived()

  // The panel is a view onto the service, so hand it the live object rather
  // than letting it reach for one. That keeps the service the single owner of
  // state and of the network.
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("service" in target) target.service = root.service
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    // The panel writes settings back under this id.
    if ("moduleName" in target) target.moduleName = root.moduleName
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing: the bar identifies a
  // panel by the bar-widget root, so it needs open/close/opened here.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item && panelLoader.item.closeForPopoutSwitch) panelLoader.item.closeForPopoutSwitch()
  }

  onBarChanged: injectPanel()

  FileView {
    id: paletteFile
    path: Color.home + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
    onStatusChanged: {
      if (status === Loader.Ready) {
        root.injectPanel()
        Qt.callLater(root.injectPanel)
      }
    }
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
    tooltipText: root.statusSuffix.length > 0
      ? "ESO Server Status - " + root.statusSuffix
      : "ESO Server Status"
    // Left opens the per-server panel, right still opens the site, middle
    // forces a re-poll. The panel carries its own link so nothing is lost.
    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        if (root.service) root.service.lastPollAt = 0
      } else if (b === Qt.RightButton) {
        Quickshell.execDetached(["omarchy-launch-browser", "https://esoserverstatus.net/"])
      } else {
        root.togglePanel()
      }
    }
  }
}
