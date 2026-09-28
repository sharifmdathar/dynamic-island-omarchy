import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "IslandModel.js" as Model

// Dynamic Island as a bar widget: compact pill living in the bar center.
// Idle (no media, no notification) it collapses to zero width.
//
// Module layout: this root owns media/notification state, persisted
// options, and actions. UI pieces live alongside it — IslandMenu.qml
// (right-click options), TransportControls.qml (hover buttons),
// EqualizerBars.qml (playing animation) — with pure helpers in
// IslandModel.js.
BarWidget {
  id: root
  moduleName: "sharifmdathar.dynamic-island"

  // ---------- media (MPRIS direct; multiple readers are fine) ----------
  readonly property var players: Mpris.players ? Mpris.players.values : []
  // Whoever played last wins: pausing Spotify must keep Spotify, not jump
  // to some older paused player that happens to sort first.
  readonly property var playingPlayer: {
    var first = null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || !p.isPlaying)
        continue
      if (!first)
        first = p
      if (root.lastKey !== "" && Model.playerKey(p) === root.lastKey)
        return p
    }
    return first
  }
  property string lastKey: ""
  onPlayingPlayerChanged: {
    if (root.playingPlayer)
      root.lastKey = Model.playerKey(root.playingPlayer)
  }
  readonly property var activePlayer: {
    // A pinned player wins over the auto-selection while it reports a track.
    if (root.pinnedPlayer !== "") {
      for (var i = 0; i < players.length; i++) {
        var pp = players[i]
        if (pp && Model.playerKey(pp) === root.pinnedPlayer && (pp.trackTitle || pp.trackArtist))
          return pp
      }
    }
    if (root.playingPlayer)
      return root.playingPlayer
    if (root.lastKey !== "") {
      for (var i = 0; i < players.length; i++) {
        var p = players[i]
        if (p && Model.playerKey(p) === root.lastKey && (p.trackTitle || p.trackArtist))
          return p
      }
    }
    var fallback = null
    for (var j = 0; j < players.length; j++) {
      var q = players[j]
      if (!q)
        continue
      if (!fallback && (q.trackTitle || q.trackArtist))
        fallback = q
    }
    return fallback
  }
  readonly property bool hasMedia: activePlayer !== null && !!((activePlayer.trackTitle || activePlayer.trackArtist))
  readonly property string mediaTitle: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string mediaArtist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string mediaArt: activePlayer ? (activePlayer.trackArtUrl || "") : ""
  readonly property string mediaAlbum: activePlayer ? (activePlayer.trackAlbum || "") : ""
  readonly property bool isPlaying: activePlayer ? !!activePlayer.isPlaying : false
  readonly property string activePlayerName: Model.playerLabel(activePlayer)

  // ---------- progress (MprisPlayer seconds; live value interpolated below) ----------
  readonly property double trackPosition: activePlayer ? activePlayer.position : 0
  readonly property double trackLength: activePlayer ? activePlayer.length : 0
  readonly property bool canSeek: activePlayer ? (!!activePlayer.canSeek && !!activePlayer.positionSupported) : false
  readonly property bool hasProgress: root.canSeek && !!activePlayer && !!activePlayer.lengthSupported && root.trackLength > 0
  // ---------- live position (interpolated) ----------
  // Some players never move MPRIS Position while playing, so anchor the
  // last reported value and count up on the wall clock. Any real update
  // (seek, track change, pause/resume) re-anchors to the truth.
  property double anchorPos: 0
  property double anchorAt: 0
  property int posTicks: 0
  readonly property double livePosition: {
    root.posTicks
    var base = root.anchorPos
    if (root.isPlaying && root.anchorAt > 0)
      base += (Date.now() - root.anchorAt) / 1000
    if (root.trackLength > 0)
      base = Math.min(base, root.trackLength)
    return Math.max(0, base)
  }
  function reanchor() {
    root.anchorPos = root.trackPosition
    root.anchorAt = Date.now()
  }
  onTrackPositionChanged: reanchor()
  onTrackLengthChanged: reanchor()
  onIsPlayingChanged: reanchor()
  onActivePlayerChanged: reanchor()
  Component.onCompleted: root.reanchor()

  // Ticks the interpolated position while playing (500ms = smooth bar).
  Timer {
    interval: 500
    running: root.showMedia && root.isPlaying && root.hasProgress
    repeat: true
    onTriggered: root.posTicks++
  }
  function seekTo(pos) {
    var p = root.activePlayer
    if (!p || !root.canSeek || !(root.trackLength > 0))
      return
    var t = Math.max(0, Math.min(Number(pos), root.trackLength))
    if (isFinite(t))
      p.position = t
  }
  function adjustVolume(delta) {
    var p = root.activePlayer
    if (!p || !p.volumeSupported)
      return
    var v = Math.max(0, Math.min(1, Number(p.volume) + Number(delta)))
    if (isFinite(v))
      p.volume = v
  }

  // ---------- options (persisted to the widget's shell.json layout entry) ----------
  readonly property string labelMode: root.setting("labelMode", "artistTitle")
  readonly property bool hideWhenPaused: root.setting("hideWhenPaused", false)
  readonly property bool showEqualizer: root.setting("showEqualizer", true)
  readonly property bool showHoverControls: root.setting("showHoverControls", true)
  readonly property bool showNotifications: root.setting("showNotifications", true)
  readonly property string pinnedPlayer: root.setting("pinnedPlayer", "")
  property bool menuOpen: false
  function setOption(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    // Applied locally first so the change lands on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }
  // Called by the popup card's outside-click dismissal.
  function close() {
    root.menuOpen = false
  }
  function menuAction(action) {
    var s = String(action || "")
    var i = s.indexOf("|")
    var kind = i < 0 ? s : s.slice(0, i)
    var arg = i < 0 ? "" : s.slice(i + 1)
    if (kind === "label") root.setOption("labelMode", arg)
    else if (kind === "pin") root.setOption("pinnedPlayer", arg)
    else if (kind === "opt") {
      if (arg === "hideWhenPaused") root.setOption(arg, !root.hideWhenPaused)
      else if (arg === "showEqualizer") root.setOption(arg, !root.showEqualizer)
      else if (arg === "showHoverControls") root.setOption(arg, !root.showHoverControls)
      else if (arg === "showNotifications") root.setOption(arg, !root.showNotifications)
    }
    root.menuOpen = false
  }
  readonly property string mediaText: Model.mediaTextFor(
    root.labelMode, mediaTitle, mediaArtist, mediaAlbum)

  // ---------- notifications (mirror of the daemon's live popup files) ----------
  readonly property string notifDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications/"
  property string notifApp: ""
  property string notifSummary: ""
  property string notifBody: ""

  function clearNotif() {
    notifApp = ""
    notifSummary = ""
    notifBody = ""
  }

  function handlePoll(output) {
    var t = String(output || "").trim()
    if (t === "") {
      clearNotif()
      return
    }
    parseNotif(t)
  }

  function parseNotif(raw) {
    try {
      var d = JSON.parse(raw || "{}")
      var s = String(d.summary || "")
      var b = Model.decodeNotifBody(d.body)
      if (s === "" && b === "") {
        clearNotif()
        return
      }
      notifApp = String(d.app || "")
      notifSummary = s
      notifBody = b
    } catch (e) {
      clearNotif()
    }
  }

  property int tickCount: 0
  Timer {
    interval: 800
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.tickCount++
      if (!pollProc.running)
        pollProc.running = true
    }
  }

  // Grace keeps controls visible briefly after the cursor leaves, so a
  // width change under the cursor can't start an enter/exit loop.
  Timer {
    id: hoverExitGrace
    interval: 350
    onTriggered: root.hovered = false
  }

  Process {
    id: pollProc
    command: ["sh", "-c", "f=$(ls -t \"" + root.notifDir + "\"*.json 2>/dev/null | head -n 1); if [ -n \"$f\" ] && [ -f \"$f\" ]; then cat \"$f\"; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handlePoll(text)
    }
  }

  // ---------- state ----------
  readonly property bool hasNotif: notifSummary !== "" || notifBody !== ""
  readonly property bool showNotif: root.showNotifications && hasNotif
  readonly property bool showMedia: !showNotif && hasMedia && (!root.hideWhenPaused || isPlaying)
  readonly property bool active: showNotif || showMedia || root.menuOpen
  readonly property bool showEq: showMedia && isPlaying && root.showEqualizer

  // Hover transport controls (media only): label + EQ swap for buttons.
  // Hover may land on the pill itself or on a control band that now covers
  // it, so both sources count.
  property bool hovered: false
  property bool forceControls: false
  readonly property bool controlsVisible: root.showHoverControls
    && (root.hovered || root.forceControls || transportControls.bandHovered)
    && root.showMedia && !root.vertical

  function doPrev() {
    if (root.activePlayer && root.activePlayer.canGoPrevious)
      root.activePlayer.previous()
  }
  // Middle-click action: raise the player window. No fallback — a player
  // that cannot raise simply ignores the gesture.
  function doRaise() {
    var p = root.activePlayer
    if (!p || !p.canRaise)
      return
    p.raise()
  }
  function togglePlayback() {
    var p = root.activePlayer
    if (!p)
      return
    if (p.isPlaying) {
      if (p.canPause)
        p.pause()
    } else if (p.canPlay) {
      p.play()
    }
  }
  function doNext() {
    if (root.activePlayer && root.activePlayer.canGoNext)
      root.activePlayer.next()
  }
  // Wheel over the pill: volume ±5% per notch. No-op on players
  // without volume support.
  readonly property string labelText: showNotif
    ? ((notifApp !== "" ? notifApp + " · " : "") + (notifSummary !== "" ? notifSummary : notifBody))
    : mediaText
  readonly property string tooltipText: showNotif
    ? (notifSummary !== "" && notifBody !== "" ? notifSummary + "\n" + notifBody : labelText)
    : (mediaText + (isPlaying ? "\nNow Playing" : "\nPaused"))

  // ---------- sizing ----------
  TextMetrics {
    id: labelMetrics
    font.family: Style.font.family
    font.pixelSize: 12
    font.weight: Font.Medium
    text: root.labelText
  }
  readonly property int artW: 20
  readonly property int labelW: Math.min(root.controlsVisible ? 150 : 240, Math.max(40, Math.ceil(labelMetrics.advanceWidth)))
  // Gapless full-height bands: the reservation must match the module's own
  // slot width exactly, so derive it instead of restating the number.
  readonly property int controlsW: transportControls.slotWidth * 3
  readonly property int pillW: 14 + artW + 8 + labelW + (root.controlsVisible ? 8 + controlsW : (root.showEq ? 8 + 16 : 0)) + 14

  visible: root.active
  implicitWidth: root.active ? (vertical ? barSize : pillW) : 0
  implicitHeight: barSize

  Behavior on implicitWidth {
    NumberAnimation {
      duration: 180
      easing.type: Easing.OutCubic
    }
  }

  // ---------- diagnostics ----------
  IpcHandler {
    target: "island"
    function state(): string {
      return JSON.stringify({
        active: root.active,
        ticks: root.tickCount,
        hovered: root.hovered,
        controlsVisible: root.controlsVisible,
        showNotif: root.showNotif,
        app: root.notifApp,
        summary: root.notifSummary,
        hasMedia: root.hasMedia,
        mediaText: root.mediaText,
        position: root.livePosition,
        length: root.trackLength,
        canSeek: root.hasProgress,
        labelMode: root.labelMode,
        hideWhenPaused: root.hideWhenPaused,
        pinnedPlayer: root.pinnedPlayer
      })
    }
    function ping(): string {
      return "ok"
    }
    function setOption(key: string, value: string): string {
      var v = value
      if (value === "true") v = true
      else if (value === "false") v = false
      root.setOption(key, v)
      return "ok"
    }
    function controls(enable: string): string {
      root.forceControls = (enable === "true" || enable === "1")
      return root.controlsVisible ? "shown" : "hidden"
    }
  }

  // ---------- pill ----------
  Rectangle {
    id: pillBg
    anchors.fill: parent
    anchors.topMargin: 4
    anchors.bottomMargin: 4
    radius: height / 2
    color: Color.bar.background
    border.color: Qt.rgba(1, 1, 1, 0.12)
    border.width: 1
    visible: root.active

    // Hover detection for the transport controls (bottom of stack; buttons sit above).
    // Left click toggles playback, middle click raises the player,
    // right click opens the options menu.
    // (Shift-click can't raise: the slot's press-grabber accepts every left
    // press for drag-reorder, so press modifiers always read empty here.)
    MouseArea {
      id: pillMouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: root.showMedia && !root.vertical
      // Modifiers are sampled on press: clicked fires on release, when
      // Shift may already be up again.
      property int pressModifiers: 0
      onPressed: function(mouse) {
        pressModifiers = mouse.modifiers
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          root.menuOpen = !root.menuOpen
          return
        }
        if (mouse.button === Qt.MiddleButton || (pressModifiers & Qt.ShiftModifier)) {
          root.doRaise()
          return
        }
        root.togglePlayback()
      }
      onWheel: function(wheel) {
        var p = root.activePlayer
        if (!p || !p.volumeSupported)
          return
        var d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
        if (d > 0) root.adjustVolume(0.05)
        else if (d < 0) root.adjustVolume(-0.05)
        else return
        wheel.accepted = true
      }
      onEnabledChanged: {
        if (!enabled) {
          hoverExitGrace.stop()
          root.hovered = false
        }
      }
      onEntered: {
        hoverExitGrace.stop()
        root.hovered = true
      }
      onExited: {
        hoverExitGrace.restart()
      }
    }

    // Vertical bars: artwork dot only — the pill is one slot wide.
    Item {
      anchors.centerIn: parent
      width: 18
      height: 18
      visible: root.vertical && root.active
      Rectangle {
        anchors.fill: parent
        radius: 9
        color: root.showNotif ? Color.bar.active : Color.bar.background
        visible: root.showNotif || root.mediaArt === ""
      }
      Image {
        anchors.fill: parent
        source: root.mediaArt
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(36, 36)
        visible: !root.showNotif && root.mediaArt !== ""
      }
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      spacing: 8
      visible: !root.vertical
      anchors.verticalCenter: parent.verticalCenter

      // Album art / note glyph, or green dot for notifications.
      Item {
        width: root.artW
        height: root.artW
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
          anchors.fill: parent
          radius: root.showNotif ? 4 : 10
          color: root.showNotif ? Color.bar.active : Color.bar.background
          visible: root.showNotif || root.mediaArt === ""
        }
        Text {
          anchors.centerIn: parent
          text: "♪"
          color: Color.bar.text
          font.pixelSize: 11
          visible: !root.showNotif && root.mediaArt === ""
        }
        Image {
          anchors.fill: parent
          source: root.mediaArt
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize: Qt.size(40, 40)
          visible: !root.showNotif && root.mediaArt !== ""
        }
      }

      Text {
        width: root.labelW
        anchors.verticalCenter: parent.verticalCenter
        text: root.labelText
        color: Color.bar.text
        font.family: labelMetrics.font.family
        font.pixelSize: 12
        font.weight: Font.Medium
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      EqualizerBars {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showEq && !root.controlsVisible
        playing: root.showEq && !root.vertical
      }

      TransportControls {
        id: transportControls
        anchors.verticalCenter: parent.verticalCenter
        visible: root.controlsVisible
        slotHeight: pillBg.height
        player: root.activePlayer
        playing: root.isPlaying
        onPrevRequested: root.doPrev()
        onToggleRequested: root.togglePlayback()
        onNextRequested: root.doNext()
        onRaiseRequested: root.doRaise()
        onVolumeUp: root.adjustVolume(0.05)
        onVolumeDown: root.adjustVolume(-0.05)
      }
    }
  }

  // ---------- options menu (right click) ----------
  IslandMenu {
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.menuOpen && root.showMedia && !root.vertical
    labelMode: root.labelMode
    hideWhenPaused: root.hideWhenPaused
    showEqualizer: root.showEqualizer
    showHoverControls: root.showHoverControls
    showNotifications: root.showNotifications
    pinnedPlayer: root.pinnedPlayer
    players: root.players
    mediaTitle: root.mediaTitle
    mediaArtist: root.mediaArtist
    mediaAlbum: root.mediaAlbum
    mediaArt: root.mediaArt
    playerName: root.activePlayerName
    position: root.livePosition
    length: root.trackLength
    canSeek: root.hasProgress
    onActionRequested: function(action) { root.menuAction(action) }
    onSeekRequested: function(pos) { root.seekTo(pos) }
    onRaiseRequested: function() { root.doRaise(); root.menuOpen = false }
  }
}
