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
//
// Muting a server changes what a poll is judged on, never how many polls
// happen: the endpoint returns the whole fleet in one document, so there is no
// cheaper request to make and no reason to pretend otherwise.
Item {
  id: root

  // Injected by the shell's service loader.
  property var shell: null

  readonly property string apiUrl: "https://esoserverstatus.net/api/refresh"

  // "" until the first successful response, then "green" | "red" | "orange".
  // Also "" once a response has been read but every server is muted: there is
  // a real reading and nothing to report, which `hasReading` distinguishes.
  property string status: ""
  property int onlineCount: -1
  // Counted over the monitored servers only, so it is the denominator the
  // user actually asked about rather than the size of the whole fleet.
  property int totalCount: 0

  // Per-server detail for the bar panel, one entry per server the site
  // reports. Reassigned wholesale rather than mutated, because a QML property
  // holding an array only notifies bindings when the reference itself changes.
  //
  // Carries no mute flag: the settings object is the only source of truth for
  // that, and a copy made here would be a poll behind the switch the user just
  // clicked.
  property var serverList: []

  // True when the last fetch failed. The last known status is kept so the bar
  // can still render something, but the widget shows it neutrally rather than
  // claiming a freshness we no longer have.
  property bool stale: false

  // User-facing poll switch. While paused the last known status is held rather
  // than refreshed, which is the point: the user asked to spend no requests.
  // Resuming forces a fetch instead of waiting out the interval that was left
  // over, so the panel never presents pre-pause data as current.
  readonly property bool paused: !!setting("paused", false)

  onPausedChanged: {
    if (!paused) lastPollAt = 0
  }

  // Pushed in by whichever bar widget carries the user's settings.
  property var settings: ({})

  property int failures: 0
  property bool settled: false
  property bool everReported: false
  property double lastPollAt: 0

  // The verdict as it stood when the in-flight poll was *started*.
  //
  // settle() cannot read `status` to answer "were we down a moment ago",
  // because apply() assigns the new status at the end of its own run and
  // onStreamFinished evaluates root.settle(root.apply(text)) -- so apply()
  // finishes first and `status` already holds the answer. Comparing the new
  // verdict against itself made the recovery check fire on the way *down* and
  // stay silent on the way up. Snapshot taken before the fetch starts.
  property string statusBeforePoll: ""

  // The question settle() actually has to answer: was the fleet down the last
  // time we looked? Read off the snapshot, because by the time settle() runs
  // apply() has already put the *new* verdict in `status` -- reading that
  // instead compared the answer with itself, which announced recovery on the
  // way down and stayed quiet on the way up.
  readonly property bool wasDown: everReported
    && statusBeforePoll !== "" && statusBeforePoll !== "green"

  // True once a response has parsed, whatever it said. Distinct from a
  // non-empty `status`, which is also false when every server is muted: the
  // bar stays on screen and says "no servers monitored" rather than
  // disappearing and taking the panel's own switch row with it.
  property bool hasReading: false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return (value === undefined || value === null) ? fallback : value
  }

  // The servers the user has switched off, as a deny-list of names.
  //
  // A deny-list rather than an allow-list for two reasons: an install that
  // predates the setting has no entry at all and keeps watching the whole
  // fleet, and a server the site adds later arrives monitored rather than
  // silently unmonitored by a list that never mentioned it.
  //
  // Duck-typed on purpose, never Array.isArray(). The array is built in the
  // shell's JS realm, and a cross-realm array answers isArray() === false
  // while still being a perfectly good array with a length and indexOf --
  // which would silently mute nothing at all, with no error anywhere. Copying
  // the names out also normalises them to strings, which is what comparing
  // them against the payload's keys needs. Read as a function rather than a
  // binding because the panel replaces the whole settings object on every
  // write, and only a poll and the panel's own rows care about the answer.
  function mutedList() {
    var raw = settings ? settings.mutedServers : undefined
    if (!raw || typeof raw.length !== "number") return []
    var names = []
    for (var i = 0; i < raw.length; i++) names.push(String(raw[i]))
    return names
  }

  function healthySeconds() {
    return Math.max(120, Number(setting("healthyInterval", 300)) || 300)
  }

  function alertSeconds() {
    return Math.max(30, Number(setting("alertInterval", 60)) || 60)
  }

  // The rare cadence is the default and the frequent one is the exception, so
  // the exception is named rather than the default: only a fleet that is
  // actually broken earns the fast poll. Muting everything is not a broken
  // fleet, it is nothing to watch, and nothing to watch is the quiet case.
  function nextIntervalSeconds() {
    if (failures > 0) {
      var backoff = 60 * Math.pow(2, Math.min(failures - 1, 10))
      return Math.min(backoff, 600)
    }
    if (status === "red" || status === "orange") return alertSeconds()
    return healthySeconds()
  }

  function maybePoll() {
    if (paused || settled || fetch.running) return
    if (Date.now() / 1000 - lastPollAt < nextIntervalSeconds()) return
    lastPollAt = Date.now() / 1000
    statusBeforePoll = status
    settled = true
    fetch.running = true
  }

  // Single funnel for both outcomes: curl's exit signal and its stdout
  // completion race each other, and one fetch must never be counted twice.
  function settle(ok) {
    if (!settled) return
    settled = false

    if (ok) {
      failures = 0
      stale = false
      if (root.wasDown && setting("notifyRecovery", true)) announceRecovery()
      everReported = true
    } else {
      failures++
      stale = true
    }
  }

  // A server counts as online only on a literal boolean true. The site also
  // uses 2 for "ongoing issues", which is deliberately not online so a partial
  // outage reads orange rather than green.
  //
  // Muted servers stay in serverList so the panel can keep listing them, but
  // they are left out of the counts and out of the verdict: a fleet the user
  // is not watching must not paint their glyph.
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

    var muted = mutedList()
    var online = 0
    var monitored = 0
    var list = []
    for (var i = 0; i < names.length; i++) {
      var name = names[i]
      var value = servers[name]
      var isMuted = muted.indexOf(name) !== -1
      list.push({
        name: name,
        state: value === true ? "online" : (value === 2 ? "issues" : "offline")
      })
      if (isMuted) continue
      monitored++
      if (value === true) online++
    }

    hasReading = true
    // -1 already means "nothing to say about a count" to the bar and the
    // panel, which is exactly what an all-muted fleet is, so an all-muted
    // fleet needs no new state of its own.
    onlineCount = monitored === 0 ? -1 : online
    totalCount = monitored
    serverList = list
    status = monitored === 0 ? "" : (online === monitored ? "green" : (online === 0 ? "red" : "orange"))
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
