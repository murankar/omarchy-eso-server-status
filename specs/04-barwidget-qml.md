# 04 — BarWidget.qml (Status Icon & Input)

## Purpose

Renders a **single status glyph** in the Omarchy bar. Reads from the shared Service object, colours itself based on fleet health, and handles mouse input for:

- **Left-click:** toggle the per-server popout panel
- **Right-click:** open `https://esoserverstatus.net/` in browser
- **Middle-click:** force immediate re-poll

## Source File

**Path:** `/home/uri/Projects/plugins/omarchy/omarchy-eso-server-status/BarWidget.qml`  
**Size:** 6,790 chars | **177 lines**

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Theme.js" as Theme

BarWidget {
    id: root
    
    // Module metadata for plugin discovery
    readonly property string moduleName: "murankar.eso-server-status"
    
    // Status glyph (Nerd Font icon)
    readonly property string icon: "\ueb50"  // the  character
    
    //--------------------------------------------------------------
    // Live service access via Quickshell service registry
    //--------------------------------------------------------------
    readonly property var service: {
        if (!root.bar) return null
        var shell = root.bar.shell
        return shell ? shell.serviceFor("murankar.eso-server-status") : null
    }
    
    exposedStatus: root.status
    
    // Reactive properties sourced from the shared Service object above.
    readonly property string status: service ? service.status : ""
    readonly property int onlineCount: service ? service.onlineCount : -1
    readonly property int totalCount: service ? service.totalCount : 0
    readonly property bool stale: service ? service.stale : false
    readonly property bool paused: service ? service.paused : false
    // Whether a poll has landed at least once, regardless of what it said.
    readonly property bool hasReading: service ? service.hasReading : false
    // True when the service reports nothing is being monitored (muted all).
    readonly property bool nothingMonitored: root.hasReading && !root.paused && root.totalCount === 0
    
    //--------------------------------------------------------------
    // Tooltip suffix logic.
    // Priority order (highest first):
    // 1. paused → "polling paused"
    // 2. nothing monitored → "no servers monitored"  
    // 3. detail enabled AND we have a count → "N/M online"
    // 4. empty → generic title only
    readonly property string statusSuffix: root.paused
        ? "polling paused"
        : (root.nothingMonitored
            ? "no servers monitored"
            : (setting("detail", false) && root.onlineCount >= 0
                ? root.onlineCount + "/" + root.totalCount + " online"
                : ""))
    
    // Tooltip text: always starts with "ESO Server Status"; suffix appended.
    readonly property string tooltipText: root.statusSuffix.length > 0
        ? "ESO Server Status - " + root.statusSuffix
        : "ESO Server Status"
    
    // Palette parsing: read from Omarchy's active theme file and parse into
    // a plain JS object keyed by colour name → hex value.
    readonly property var palette: Theme.parsePalette(paletteFile.text())
    
    //--------------------------------------------------------------
    // Colour helpers — pick hue-correct colours from the current theme.
    // If a suitable named palette entry is found (hue within band), use it;
    // otherwise fall back to a fixed colour literal.  This is needed because
    // several official themes map non-semantic names onto their green / orange
    // keys (e.g. lumon has blue under "green", matte-black has amber).
    //--------------------------------------------------------------
    readonly property color greenColor: Theme.pick(
        palette, ["green","bright_green","color2","color10","color42"], 
        "green", "#26a269")
    
    readonly property color orangeColor: Theme.pick(
        palette, ["orange","bright_orange","accent","yellow","bright_yellow",
                  "color3","color11","color214"], 
        "orange", "#e69138")
    
    readonly property color redColor: Theme.pick(
        palette, ["red","bright_red","color1","color9","color88"], 
        "red", "#dc3545")
    
    // The active glyph colour on the bar.  Stale / paused readings drop to the
    // neutral foreground so they never mislead.
    readonly property color statusColor: (stale || paused || nothingMonitored)
        ? (bar ? bar.barForeground : Color.foreground)
        : status === "green" ? greenColor
        : status === "red" ? redColor
        : status === "orange" ? orangeColor
        : (bar ? bar.barForeground : Color.foreground)
    
    // The widget is hidden until it has something to say, so the bar is never
    // blank during startup.
    visible: root.hasReading
    
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    
    //--------------------------------------------------------------
    // Settings sync — push panel → service, pull service → panel.
    // Called whenever either changes to keep them in lock-step.
    //--------------------------------------------------------------
    function onServiceChanged() {
        if (root.service) root.service.settings = root.settings
        injectPanel()
    }
    
    function onSettingsChanged() {
        if (root.service) root.service.settings = root.settings
    }
    
    Component.onCompleted: onServiceChanged()
    
    //--------------------------------------------------------------
    // Panel injection — pass the live service object and other bindings into
    // the injected Panel so it has its own copy to read. 
    //--------------------------------------------------------------
    function injectPanel() {
        var target = panelLoader.item   // Loader that loads Panel.qml
        if (!target) return
        
        // Pass through the bindings the panel expects:
        "bar" in target && (target.bar = root.bar)
        "settings" in target && (target.settings = root.settings)
        "service" in target && (target.service = root.service)
        "anchorItem" in target && (target.anchorItem = button)
        "hostWidget" in target && (target.hostWidget = root)
        "moduleName" in target && (target.moduleName = root.moduleName)
    }
    
    function togglePanel() {
        if (panelLoader.item && panelLoader.item.toggle)
            panelLoader.item.toggle()
    }
    
    // Open / close contract so the shell can manage panels uniformly:
    readonly property bool opened: panelLoader.item ? (panelLoader.item.opened === true) : false
    function open() {
        if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
    }
    function close() {
        if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
    }
    
    onBarChanged: injectPanel()
    
    // Watcher for the active theme's colour palette so Panel.qml and here both
    // pick up the new colours when the theme changes.
    FileView {
        id: paletteFile
        path: Color.home + "/.local/state/omarchy/current/theme/colors.toml"
        watchChanges: true
        printErrors: false
    }
    
    // Loader that brings Panel.qml into this widget's scene when the user
    // first opens it.  The file is a sibling of BarWidget.qml so Qt.resolvedUrl
    // resolves correctly regardless of where the plugin is installed.
    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        
        onLoaded: root.injectPanel()
        onStatusChanged: {
            if (status === Loader.Ready) {
                root.injectPanel()
                // Ensure bindings propagate after the panel receives its own copy.
                Qt.callLater(root.injectPanel)
            }
        }
    }
    
    //--------------------------------------------------------------
    // The clickable icon element, styled by the current status colour.  All of
    // the real work is done in this file; Panel.qml stays out of it.
    //--------------------------------------------------------------
    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.icon               // the Nerd Font glyph: "\ueb50" ("")
        slotSize: Style.bar.statusSlot
        activeColor: root.statusColor  // driven by statusColor binding above
        useActiveColor: true           // tell BarIconButton to render with it
        active: true                   // visible even when idle
        
        tooltipText: root.tooltipText  // read above; depends on detail setting
        onPressed: function(b) {
            if (b === Qt.MiddleButton) {
                // Force an immediate re-poll.
                if (root.service) root.service.lastPollAt = 0
            } else if (b === Qt.RightButton) {
                Quickshell.execDetached([
                    "omarchy-launch-browser",
                    "https://esoserverstatus.net/"
                ])
            } else {
                // Left click is the *open / toggle* path.
                root.togglePanel()
            }
        }
    }
}
