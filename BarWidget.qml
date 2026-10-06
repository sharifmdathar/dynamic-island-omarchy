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

  // ---------- playback modes ----------
  // Quickshell exposes these as writable MPRIS properties; the capability
  // flags say whether the player honours them at all.
  readonly property bool canShuffle: activePlayer ? (!!activePlayer.shuffleSupported) : false
  readonly property bool shuffleOn: activePlayer ? (!!activePlayer.shuffle) : false
  readonly property bool canLoop: activePlayer ? (!!activePlayer.loopSupported) : false
  // MprisLoopState: None 0, Track 1, Playlist 2.
  readonly property int loopMode: {
    if (!activePlayer || !activePlayer.loopSupported)
      return 0
    var s = activePlayer.loopState
    if (s === MprisLoopState.Track)
      return 1
    if (s === MprisLoopState.Playlist)
      return 2
    return 0
  }
  readonly property string loopLabel: Model.loopLabel(root.loopMode)
  function toggleShuffle() {
    var p = root.activePlayer
    if (!p || !p.shuffleSupported)
      return false
    p.shuffle = !p.shuffle
    return true
  }
  // mode: "off" | "one" | "all" -> applied mode, -1 when unsupported.
  function setRepeat(mode) {
    var p = root.activePlayer
    if (!p || !p.loopSupported)
      return -1
    if (mode === "one") {
      p.loopState = MprisLoopState.Track
      return 1
    }
    if (mode === "all") {
      p.loopState = MprisLoopState.Playlist
      return 2
    }
    if (mode === "off") {
      p.loopState = MprisLoopState.None
      return 0
    }
    return -1
  }
  // Off -> One -> All -> Off.
  function cycleRepeat() {
    if (!root.canLoop)
      return -1
    return root.setRepeat(["off", "one", "all"][(root.loopMode + 1) % 3])
  }

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
  readonly property real mediaProgressRatio: (root.hasProgress && root.trackLength > 0)
    ? Math.max(0.0, Math.min(1.0, root.livePosition / root.trackLength))
    : 0.0
  function reanchor() {
    root.anchorPos = root.trackPosition
    root.anchorAt = Date.now()
  }
  onTrackPositionChanged: reanchor()
  onTrackLengthChanged: reanchor()
  onIsPlayingChanged: reanchor()
  onActivePlayerChanged: {
    reanchor()
    root.volFlash = -1
  }
  Component.onCompleted: {
    root.reanchor()
    root.refreshNotifs()
  }

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
      return -1
    var t = Math.max(0, Math.min(Number(pos), root.trackLength))
    if (!isFinite(t))
      return -1
    p.position = t
    return t
  }
  function adjustVolume(delta) {
    var p = root.activePlayer
    if (!p || !p.volumeSupported)
      return
    var v = Math.max(0, Math.min(1, Number(p.volume) + Number(delta)))
    if (isFinite(v)) {
      p.volume = v
      root.flashVolume(v)
    }
  }

  // ---------- volume readout ----------
  // The scroll gesture has no other feedback, so a change briefly replaces
  // the label with the new level. -1 hides it.
  property int volFlash: -1
  Timer {
    id: volFlashTimer
    interval: 1200
    onTriggered: root.volFlash = -1
  }
  function flashVolume(v) {
    var pct = Math.round(Math.max(0, Math.min(1, Number(v))) * 100)
    if (!isFinite(pct))
      return
    root.volFlash = pct
    volFlashTimer.restart()
  }

  // ---------- options (persisted to the widget's shell.json layout entry) ----------
  readonly property string labelMode: root.setting("labelMode", "artistTitle")
  readonly property bool hideWhenPaused: root.setting("hideWhenPaused", false)
  readonly property bool showEqualizer: root.setting("showEqualizer", true)
  readonly property bool showHoverControls: root.setting("showHoverControls", true)
  readonly property bool showProgressFill: root.setting("showProgressFill", true)
  readonly property bool showNotifications: root.setting("showNotifications", true)
  // The pill collapses to nothing when idle; this is what lets the archive
  // keep it open on its own, so it gets its own switch.
  readonly property bool showUnreadBadge: root.setting("showUnreadBadge", true)
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
  function toggleMenu() {
    root.menuOpen = !root.menuOpen
    if (root.menuOpen)
      root.refreshNotifs()
  }
  // The badge clears once the list has actually been looked at, not while it
  // is on screen — that window is what marks the rows as new.
  onMenuOpenChanged: {
    if (!root.menuOpen)
      root.markInboxSeen()
  }
  function menuAction(action) {
    var s = String(action || "")
    var i = s.indexOf("|")
    var kind = i < 0 ? s : s.slice(0, i)
    var arg = i < 0 ? "" : s.slice(i + 1)
    if (kind === "mode") {
      // A mode toggle keeps the menu open so the row flips in place.
      if (arg === "shuffle") root.toggleShuffle()
      else if (arg === "repeat") root.cycleRepeat()
      return
    }
    if (kind === "label") root.setOption("labelMode", arg)
    else if (kind === "pin") root.setOption("pinnedPlayer", arg)
    else if (kind === "opt") {
      if (arg === "hideWhenPaused") root.setOption(arg, !root.hideWhenPaused)
      else if (arg === "showEqualizer") root.setOption(arg, !root.showEqualizer)
      else if (arg === "showHoverControls") root.setOption(arg, !root.showHoverControls)
      else if (arg === "showProgressFill") root.setOption(arg, !root.showProgressFill)
      else if (arg === "showNotifications") root.setOption(arg, !root.showNotifications)
      else if (arg === "showUnreadBadge") root.setOption(arg, !root.showUnreadBadge)
    }
    root.menuOpen = false
  }
  readonly property string mediaText: Model.mediaTextFor(
    root.labelMode, mediaTitle, mediaArtist, mediaAlbum)

  // ---------- notifications ----------
  // The notification daemon keeps its state on disk: one file per live toast
  // in the popup directory (written as it appears, moved out as it leaves)
  // and one per archived entry under history/. Those directories are the
  // interface a third-party widget may use — the daemon's service object is
  // only proxied to full-bar plugins — so the island reads them directly.
  readonly property string notifDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications/"
  readonly property string notifHistoryDir: notifDir + "history/"
  readonly property string notifImagesDir: notifDir + "images/"

  // Newest live toast, which is what the pill previews.
  property var livePopup: null
  readonly property string notifApp: root.livePopup ? String(root.livePopup.app || "") : ""
  readonly property string notifSummary: root.livePopup ? String(root.livePopup.summary || "") : ""
  readonly property string notifBody: root.livePopup ? Model.decodeNotifBody(root.livePopup.body) : ""
  readonly property double liveNotifAt: root.livePopup ? Number(root.livePopup.timestamp) || 0 : 0

  // ---------- notification inbox (the archive) ----------
  property var inboxRows: []
  property var pendingRemoves: []
  property bool notifBusy: false
  property bool notifPending: false
  // Persisted so the badge stays cleared across restarts and monitors.
  // real, not int: a millisecond epoch does not fit in 32 bits.
  readonly property real inboxSeenAt: Number(root.setting("inboxSeenAt", 0)) || 0
  readonly property int unread: root.showNotifications
    ? Model.unreadCount(root.inboxRows, root.showNotif ? root.liveNotifAt : 0, root.inboxSeenAt)
    : 0

  // Inbox ages re-render while the card is open.
  property real inboxNowMs: Date.now()
  Timer {
    interval: 30000
    running: root.menuOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: root.inboxNowMs = Date.now()
  }

  // One job at a time: drop any queued archive files, then re-dump both
  // directories. File names arrive as positional parameters and the
  // directories as $1/$2, so nothing that came out of a notification is ever
  // interpolated into the script text. Image copies share the JSON's stem, so
  // each removal takes them with it — the same cleanup the daemon performs.
  readonly property string notifScript: "d=\"$1\"; i=\"$2\"; shift 2; for p in \"$@\"; do rm -f -- \"$d/history/$p\" \"$i/${p%.json}\"-*; done; for f in $(ls -t \"$d\"*.json 2>/dev/null); do printf '\\n@@ISLANDLIVE@@\\n'; cat \"$f\"; done; for f in $(ls -t \"$d/history\"/*.json 2>/dev/null); do printf '\\n@@ISLANDROW@@\\n'; cat \"$f\"; done"
  function runNotifJob(removeList) {
    root.notifBusy = true
    notifProc.command = ["bash", "-c", root.notifScript, "island",
      root.notifDir, root.notifImagesDir].concat(removeList)
    notifProc.running = true
  }
  function refreshNotifs() {
    if (root.notifDir === "" || !root.showNotifications)
      return
    if (root.notifBusy) {
      root.notifPending = true
      return
    }
    var rm = root.pendingRemoves
    root.pendingRemoves = []
    root.runNotifJob(rm)
  }
  function removeInboxRow(file) {
    // Only the daemon's own `<timestamp>-<id>.json` shape reaches `rm`.
    if (!/^[0-9]+-[0-9]+\.json$/.test(String(file || "")))
      return
    root.pendingRemoves = root.pendingRemoves.concat([String(file)])
    root.refreshNotifs()
  }
  function markInboxSeen() {
    if (root.unread > 0)
      root.setOption("inboxSeenAt", Date.now())
  }
  function clearInbox() {
    var rows = Array.isArray(root.inboxRows) ? root.inboxRows : []
    for (var i = 0; i < rows.length; i++)
      root.removeInboxRow(rows[i].file)
  }
  // Act on a row: run its click action when the sender supplied one, then
  // take it out of the archive. Both go through the same job queue.
  function invokeInboxRow(index) {
    var rows = Array.isArray(root.inboxRows) ? root.inboxRows : []
    var row = rows[index]
    if (!row)
      return
    var argv = Model.parseExecArgv(row.execArgv)
    if (argv !== null)
      Util.execArgv(argv)
    root.removeInboxRow(row.file)
  }

  // One read covers both directories: the live toast the pill previews and
  // the archive the inbox lists. It runs on a slow timer plus the immediate
  // kicks (hover, opening the card, a queued removal), so a toast lands on
  // the pill within two seconds and instantly once the pointer is on it.
  Process {
    id: notifProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyNotifDump(text)
    }
    onExited: {
      root.notifBusy = false
      if (root.notifPending) {
        root.notifPending = false
        root.refreshNotifs()
      }
    }
  }

  function applyNotifDump(raw) {
    // The archive is re-read on a timer and on every kick, but its contents
    // only change now and then. Handing the Repeater a fresh array anyway
    // would rebuild every inbox row, and a row that is unfolding under the
    // cursor would be destroyed mid-hover, so publish only real changes.
    var rows = Model.parseInboxRows(raw)
    if (JSON.stringify(rows) !== JSON.stringify(root.inboxRows))
      root.inboxRows = rows
    var live = Model.parseLiveRows(raw)
    root.livePopup = live.length > 0 ? live[0] : null
    // An archive that predates the badge is not "unread": baseline it once so
    // installing this never opens with a shout about old mail. With the
    // archive empty the mark stays unset, so a first real notification still
    // counts.
    if (root.inboxSeenAt === 0 && root.inboxRows.length > 0)
      root.setOption("inboxSeenAt", root.inboxRows[0].timestamp)
  }

  Timer {
    interval: 2000
    running: root.showNotifications
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshNotifs()
  }

  // Grace keeps controls visible briefly after the cursor leaves, so a
  // width change under the cursor can't start an enter/exit loop.
  Timer {
    id: hoverExitGrace
    interval: 350
    onTriggered: root.hovered = false
  }

  // ---------- state ----------
  readonly property bool hasNotif: notifSummary !== "" || notifBody !== ""
  readonly property bool showNotif: root.showNotifications && hasNotif
  readonly property bool showMedia: !showNotif && hasMedia && (!root.hideWhenPaused || isPlaying)
  // Unread archive entries keep the pill alive on their own: when nothing is
  // playing they are the only place the inbox can announce itself.
  readonly property bool showInbox: root.showUnreadBadge && root.unread > 0 && !root.showMedia && !root.showNotif
  readonly property bool active: showNotif || showMedia || root.menuOpen || root.showInbox
  readonly property bool showEq: showMedia && isPlaying && root.showEqualizer

  // Hover transport controls (media only): label + EQ swap for buttons.
  // Hover may land on the pill itself or on a control band that now covers
  // it, so both sources count.
  property bool hovered: false
  property bool forceControls: false
  readonly property bool controlsVisible: root.showHoverControls
    && (root.hovered || root.forceControls || transportControls.bandHovered)
    && root.showMedia && !root.vertical

  // Every action reports whether the player accepted it. MPRIS state lands
  // asynchronously, so the IPC verbs answer from this rather than reading
  // isPlaying back a moment after issuing the command.
  function doPrev() {
    var p = root.activePlayer
    if (!p || !p.canGoPrevious)
      return false
    p.previous()
    return true
  }
  // Middle-click action: raise the player window. No fallback — a player
  // that cannot raise simply ignores the gesture.
  function doRaise() {
    var p = root.activePlayer
    if (!p || !p.canRaise)
      return false
    p.raise()
    return true
  }
  // Returns the state the player was asked to move to, "" when it cannot.
  function togglePlayback() {
    var p = root.activePlayer
    if (!p)
      return ""
    if (p.isPlaying) {
      if (!p.canPause)
        return ""
      p.pause()
      return "paused"
    }
    if (!p.canPlay)
      return ""
    p.play()
    return "playing"
  }
  function doNext() {
    var p = root.activePlayer
    if (!p || !p.canGoNext)
      return false
    p.next()
    return true
  }
  function doPlay() {
    var p = root.activePlayer
    if (!p || !p.canPlay)
      return false
    p.play()
    return true
  }
  function doPause() {
    var p = root.activePlayer
    if (!p || !p.canPause)
      return false
    p.pause()
    return true
  }
  // Absolute level, clamped. Values above 1 are read as a percentage so
  // both `island volume 0.4` and `island volume 40` do what they say.
  function setVolume(v) {
    var p = root.activePlayer
    var n = Number(v)
    if (!p || !p.volumeSupported || !isFinite(n))
      return -1
    if (n > 1) n = n / 100
    var clamped = Math.max(0, Math.min(1, n))
    p.volume = clamped
    root.flashVolume(clamped)
    return Math.round(clamped * 100)
  }
  function nudgePosition(delta) {
    var d = Number(delta)
    if (!isFinite(d))
      return -1
    return root.seekTo(root.livePosition + d)
  }
  // Wheel over the pill: volume ±5% per notch. No-op on players
  // without volume support.
  readonly property string labelText: root.volFlash >= 0 && root.showMedia
    ? ("♪ " + root.volFlash + "%")
    : showNotif
      ? ((notifApp !== "" ? notifApp + " · " : "") + (notifSummary !== "" ? notifSummary : notifBody))
      : root.showMedia
        ? mediaText
        : Model.unreadLabel(root.showInbox ? root.unread : 0)
  readonly property string tooltipText: showNotif
    ? (notifSummary !== "" && notifBody !== "" ? notifSummary + "\n" + notifBody : labelText)
    : root.showMedia
      ? (mediaText + (isPlaying ? "\nNow Playing" : "\nPaused"))
      : (root.unread > 0 ? root.unread + " unread — click to open" : "")

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
        unread: root.unread,
        seenAt: root.inboxSeenAt,
        inbox: Array.isArray(root.inboxRows) ? root.inboxRows.length : 0,
        live: root.hasNotif,
        hovered: root.hovered,
        controlsVisible: root.controlsVisible,
        showNotif: root.showNotif,
        app: root.notifApp,
        summary: root.notifSummary,
        hasMedia: root.hasMedia,
        mediaText: root.mediaText,
        playing: root.isPlaying,
        player: root.activePlayerName,
        shuffle: root.shuffleOn,
        repeat: root.loopLabel,
        position: root.livePosition,
        length: root.trackLength,
        canSeek: root.hasProgress,
        volume: (root.activePlayer && root.activePlayer.volumeSupported) ? Number(root.activePlayer.volume) : null,
        volFlash: root.volFlash,
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
    function menu(enable: string): string {
      root.menuOpen = (enable === "true" || enable === "1")
      return root.menuOpen ? "open" : "closed"
    }
    // ---------- transport verbs (for keybinds and scripts) ----------
    // Each answers from what the player accepted, never from a state read
    // back right after the call: MPRIS replies asynchronously.
    function play(): string {
      return root.doPlay() ? "playing" : "unsupported"
    }
    function pause(): string {
      return root.doPause() ? "paused" : "unsupported"
    }
    function toggle(): string {
      return root.togglePlayback() || "unsupported"
    }
    function next(): string {
      return root.doNext() ? "ok" : "unsupported"
    }
    function prev(): string {
      return root.doPrev() ? "ok" : "unsupported"
    }
    function raise(): string {
      return root.doRaise() ? "ok" : "unsupported"
    }
    function seek(seconds: string): string {
      var t = root.seekTo(Number(seconds))
      return t < 0 ? "unsupported" : String(Math.round(t))
    }
    function seekBy(delta: string): string {
      var t = root.nudgePosition(delta)
      return t < 0 ? "unsupported" : String(Math.round(t))
    }
    function volume(value: string): string {
      var pct = root.setVolume(value)
      return pct < 0 ? "unsupported" : pct + "%"
    }
    function shuffle(): string {
      var was = root.shuffleOn
      return root.toggleShuffle() ? (was ? "off" : "on") : "unsupported"
    }
    function repeat(): string {
      var applied = root.cycleRepeat()
      return applied < 0 ? "unsupported" : ["off", "one", "all"][applied]
    }
    function setRepeat(mode: string): string {
      var applied = root.setRepeat(String(mode || "").toLowerCase())
      return applied < 0 ? "unsupported" : ["off", "one", "all"][applied]
    }
    // ---------- notification inbox ----------
    function inbox(): string {
      return JSON.stringify(root.inboxRows)
    }
    function inboxRow(index: string): string {
      var i = Number(index)
      var rows = Array.isArray(root.inboxRows) ? root.inboxRows : []
      if (!isFinite(i) || i < 0 || i >= rows.length)
        return "out of range"
      return JSON.stringify(rows[i])
    }
    function inboxInvoke(index: string): string {
      var i = Number(index)
      if (!isFinite(i) || i < 0 || i >= root.inboxRows.length)
        return "out of range"
      root.invokeInboxRow(i)
      return "ok"
    }
    function inboxDismiss(index: string): string {
      var i = Number(index)
      var rows = Array.isArray(root.inboxRows) ? root.inboxRows : []
      if (!isFinite(i) || i < 0 || i >= rows.length)
        return "out of range"
      root.removeInboxRow(rows[i].file)
      return "ok"
    }
    function inboxSeen(): string {
      root.markInboxSeen()
      return String(root.inboxSeenAt)
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

    // Subtle background progress fill for active media
    Rectangle {
      id: mediaProgressFill
      anchors.fill: parent
      anchors.margins: 1
      radius: Math.max(0, pillBg.radius - 1)
      visible: !root.vertical && root.showMedia && root.showProgressFill && root.mediaProgressRatio > 0
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.20) }
        GradientStop { position: root.mediaProgressRatio; color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.20) }
        GradientStop { position: Math.min(1.0, root.mediaProgressRatio + 0.001); color: "transparent" }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }

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
      enabled: !root.vertical && (root.showMedia || root.showInbox)
      // Modifiers are sampled on press: clicked fires on release, when
      // Shift may already be up again.
      property int pressModifiers: 0
      onPressed: function(mouse) {
        pressModifiers = mouse.modifiers
      }
      onClicked: function(mouse) {
        if (!root.showMedia) {
          // Nothing playing, so the pill is the inbox badge: opening the
          // menu is the only action it has.
          root.toggleMenu()
          return
        }
        if (mouse.button === Qt.RightButton) {
          root.toggleMenu()
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
        // Hover is when the pill's content matters most, so re-read rather
        // than wait for the next tick.
        root.refreshNotifs()
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
        color: root.showNotif || root.showInbox ? Color.bar.active : Color.bar.background
        visible: root.showNotif || root.showInbox || root.mediaArt === ""
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
          radius: (root.showNotif || root.showInbox) ? 4 : 10
          color: (root.showNotif || root.showInbox) ? Color.bar.active : Color.bar.background
          visible: root.showNotif || root.showInbox || root.mediaArt === ""
        }
        Text {
          anchors.centerIn: parent
          text: "♪"
          color: Color.bar.text
          font.pixelSize: 11
          visible: !root.showNotif && !root.showInbox && root.mediaArt === ""
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

    // Unread badge. The label carries the count when the inbox is all there
    // is to show; this is for when media owns the label.
    Rectangle {
      anchors.right: parent.right
      anchors.rightMargin: 5
      anchors.top: parent.top
      anchors.topMargin: 3
      width: 7
      height: 7
      radius: 3.5
      color: Color.bar.active
      visible: root.showUnreadBadge && root.unread > 0 && root.showMedia
    }
  }

  // ---------- options menu (right click) ----------
  IslandMenu {
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.menuOpen && !root.vertical
    hasMedia: root.showMedia
    labelMode: root.labelMode
    hideWhenPaused: root.hideWhenPaused
    showEqualizer: root.showEqualizer
    showHoverControls: root.showHoverControls
    showProgressFill: root.showProgressFill
    showNotifications: root.showNotifications
    showUnreadBadge: root.showUnreadBadge
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
    canShuffle: root.canShuffle
    shuffleOn: root.shuffleOn
    canLoop: root.canLoop
    loopMode: root.loopMode
    loopLabel: root.loopLabel
    inboxRows: root.inboxRows
    unread: root.unread
    seenAt: root.inboxSeenAt
    nowMs: root.inboxNowMs
    onActionRequested: function(action) { root.menuAction(action) }
    onSeekRequested: function(pos) { root.seekTo(pos) }
    onRaiseRequested: function() { root.doRaise(); root.menuOpen = false }
    onInboxInvoke: function(index) { root.invokeInboxRow(index) }
    onInboxDismiss: function(index) {
      var row = Array.isArray(root.inboxRows) ? root.inboxRows[index] : null
      if (row)
        root.removeInboxRow(row.file)
    }
    onInboxClear: function() { root.clearInbox() }
  }
}
