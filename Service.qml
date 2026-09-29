import QtQuick
import Quickshell
import Quickshell.Io

// The single network owner for the ESO status plugin.
//
// One instance exists per shell process regardless of how many bar surfaces
// show the widget, so a multi-monitor setup costs one request per interval
// rather than one per monitor. Bar widgets are pure observers of the state
// published here and never touch the network themselves.
//
// The request budget is deliberately asymmetric. ESO outages are rare and
// long, so a healthy machine polls rarely and the frequent cadence is spent
// only while an incident is actually open -- which is the only window where a
// user genuinely wants freshness, because they are waiting on recovery.
// Transport failures back off exponentially so an offline network cannot turn
// this into a request flood either.
Item {
  id: root

  // Injected by the shell's service loader.
  property var shell: null

  readonly property string apiUrl: "https://esoserverstatus.net/api/refresh"

  // "" until the first successful response; then "green" | "red" | "orange".
  property string status: ""
  property int onlineCount: -1
  property int totalCount: 0

  // Per-server detail for the bar panel. Reassigned wholesale rather than
  // mutated, because a QML property holding an array only notifies bindings
  // when the reference itself changes.
  property var serverList: []

  // True when the last fetch failed. The last known status is kept so the bar
  // can still render something, but the widget shows it neutrally rather than
  // claiming a freshness we no longer have.
  property bool stale: false

  // Pushed in by whichever bar widget carries the user's settings.
  property var settings: ({})

  property int failures: 0
  property bool settled: false
  property bool everReported: false
  property double lastPollAt: 0

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return (value === undefined || value === null) ? fallback : value
  }

  function healthySeconds() {
    return Math.max(120, Number(setting("healthyInterval", 300)) || 300)
  }

  function alertSeconds() {
    return Math.max(30, Number(setting("alertInterval", 60)) || 60)
  }

  function nextIntervalSeconds() {
    if (failures > 0) {
      var backoff = 60 * Math.pow(2, Math.min(failures - 1, 10))
      return Math.min(backoff, 600)
    }
    return status === "green" ? healthySeconds() : alertSeconds()
  }

  function maybePoll() {
    if (settled || fetch.running) return
    if (Date.now() / 1000 - lastPollAt < nextIntervalSeconds()) return
    lastPollAt = Date.now() / 1000
    settled = true
    fetch.running = true
  }

  // Single funnel for both outcomes: curl's exit signal and its stdout
  // completion race each other, and one fetch must never be counted twice.
  function settle(ok) {
    if (!settled) return
    settled = false

    if (ok) {
      var wasDown = everReported && status !== "" && status !== "green"
      failures = 0
      stale = false
      if (wasDown && setting("notifyRecovery", true)) announceRecovery()
      everReported = true
    } else {
      failures++
      stale = true
    }
  }

  // A server counts as online only on a literal boolean true. The site also
  // uses 2 for "ongoing issues", which is deliberately not online so a partial
  // outage reads orange rather than green.
  function apply(raw) {
    var payload
    try {
      payload = JSON.parse(String(raw || "").trim())
    } catch (e) {
      return false
    }

    var servers = payload && payload.servers
    if (!servers || typeof servers !== "object") return false
    var names = Object.keys(servers)
    if (names.length === 0) return false

    var online = 0
    var list = []
    for (var i = 0; i < names.length; i++) {
      var value = servers[names[i]]
      if (value === true) online++
      list.push({
        name: names[i],
        state: value === true ? "online" : (value === 2 ? "issues" : "offline")
      })
    }

    totalCount = names.length
    onlineCount = online
    serverList = list
    status = online === names.length ? "green" : (online === 0 ? "red" : "orange")
    return true
  }

  function announceRecovery() {
    Quickshell.execDetached(["omarchy-notification-send",
      "-g", "",
      "ESO Server Status",
      "All " + totalCount + " servers are back online."])
  }

  Process {
    id: fetch
    running: false
    command: ["curl", "-fsS", "--max-time", "10",
      "-H", "X-Requested-With: XMLHttpRequest",
      "-H", "Accept: application/json",
      root.apiUrl]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.settle(root.apply(text))
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.settle(false)
    }
  }

  // Short cadence so a state change shows up promptly; the real request
  // interval is enforced by maybePoll(), which re-arms on each tick.
  Timer {
    id: pollTimer
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.maybePoll()
  }

  Component.onCompleted: root.lastPollAt = Date.now() / 1000 - 600
}
