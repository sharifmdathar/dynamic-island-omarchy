// Pure helpers for the Dynamic Island widget, kept Qt-free and stateless.
// Imported by BarWidget.qml and IslandMenu.qml alike.

// Stable identity for an MPRIS player across track changes.
function playerKey(p) {
  if (!p)
    return ""
  return String(p.dbusName || p.desktopEntry || p.identity || "")
}

// Human-readable name for the player picker menu.
function playerLabel(p) {
  if (!p)
    return ""
  return String(p.identity || p.desktopEntry || p.dbusName || "")
}

// Pill label for a label mode. Album modes fall back gracefully when the
// player reports no album.
function mediaTextFor(mode, title, artist, album) {
  var t = title || artist
  if (mode === "title")
    return t
  if (mode === "artistTitleAlbum") {
    var s = (artist && title) ? artist + " - " + title : t
    return album !== "" ? s + " · " + album : s
  }
  if (mode === "titleAlbum") {
    if (title !== "")
      return album !== "" ? title + " · " + album : title
    return artist
  }
  if (artist && title)
    return artist + " - " + title
  return t
}

// Strip notification HTML to plain text: <br> becomes a space, other tags
// are dropped, entities are decoded.
function decodeNotifBody(raw) {
  return String(raw || "")
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/<[^>]*>/g, "")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&apos;/g, "'")
}

// Repeat mode label for the menu row: 0 Off, 1 Track, 2 Playlist.
function loopLabel(mode) {
  if (mode === 1)
    return "Repeat · One"
  if (mode === 2)
    return "Repeat · All"
  return "Repeat · Off"
}

// ---------- notifications ----------
//
// The notification daemon keeps one JSON file per live toast and one per
// archived entry, named `<timestamp>-<originalId>.json` after the image
// copies that share its stem.

// The archive file name a row came from. Derived only from the daemon's own
// integer fields, and "" for anything else: the name feeds an `rm` target,
// so a tampered or malformed entry must never contribute a path.
function notifFileName(entry) {
  if (!entry)
    return ""
  var t = Number(entry.timestamp)
  var id = Number(entry.originalId)
  if (!isFinite(t) || t <= 0 || Math.floor(t) !== t)
    return ""
  if (!isFinite(id) || id < 0 || Math.floor(id) !== id)
    return ""
  return t + "-" + id + ".json"
}

// Parse one section of the island's notification dump. Every entry is
// preceded by `marker`; anything that fails to parse is dropped, so a
// malformed file can never take the rest of the read with it.
function parseRows(raw, marker) {
  var parts = String(raw || "").split(marker)
  var rows = []
  var seen = {}
  // parts[0] is whatever preceded the first marker — never an entry.
  for (var i = 1; i < parts.length; i++) {
    var d = null
    try {
      d = JSON.parse(parts[i])
    } catch (e) {
      d = null
    }
    if (!d || typeof d !== "object")
      continue
    var summary = String(d.summary || "")
    var body = decodeNotifBody(d.body)
    if (summary === "" && body === "")
      continue
    var file = notifFileName(d)
    if (file !== "" && seen[file])
      continue
    if (file !== "")
      seen[file] = true
    rows.push({
      file: file,
      app: String(d.app || ""),
      summary: summary,
      body: body,
      execArgv: String(d.execArgv || ""),
      timestamp: Number(d.timestamp) || 0
    })
  }
  rows.sort(function (a, b) { return b.timestamp - a.timestamp })
  return rows
}

// Archived rows, newest first.
function parseInboxRows(raw) {
  return parseRows(raw, "@@ISLANDROW@@")
}

// Live toast rows, newest first. The archive section is cut off first: it
// would otherwise ride along on the last live entry's chunk.
function parseLiveRows(raw) {
  var text = String(raw || "")
  var cut = text.indexOf("@@ISLANDROW@@")
  if (cut >= 0)
    text = text.slice(0, cut)
  return parseRows(text, "@@ISLANDLIVE@@")
}

// Validate a persisted `omarchy-exec-argv` into a runnable argv, or null.
// Mirrors the daemon's structural check: a non-empty array of strings whose
// first entry is not an option. Run through Util.execArgv, never a shell.
function parseExecArgv(value) {
  var text = String(value || "")
  if (text === "")
    return null
  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return null
  }
  if (!Array.isArray(parsed) || parsed.length === 0)
    return null
  for (var i = 0; i < parsed.length; i++)
    if (typeof parsed[i] !== "string")
      return null
  if (!parsed[0] || parsed[0].charAt(0) === "-")
    return null
  return parsed
}

// Pill label for the inbox badge.
function unreadLabel(n) {
  var c = Number(n)
  if (!(c > 0))
    return ""
  return c === 1 ? "1 unread" : c + " unread"
}

// Rows newer than the last-seen mark, plus the live toast if it is newer.
function unreadCount(rows, liveTimestamp, seenAt) {
  var n = 0
  var list = Array.isArray(rows) ? rows : []
  for (var i = 0; i < list.length; i++)
    if (Number(list[i].timestamp) > Number(seenAt))
      n++
  if (Number(liveTimestamp) > Number(seenAt))
    n++
  return n
}

// Compact age for an inbox row: 45s, 12m, 3h, 4d.
function relTime(ts, now) {
  var t = Number(ts)
  if (!isFinite(t) || t <= 0)
    return ""
  var secs = Math.floor((Number(now) - t) / 1000)
  if (secs < 0)
    secs = 0
  if (secs < 60)
    return secs + "s"
  if (secs < 3600)
    return Math.floor(secs / 60) + "m"
  if (secs < 86400)
    return Math.floor(secs / 3600) + "h"
  return Math.floor(secs / 86400) + "d"
}

// Format track seconds as m:ss (or h:mm:ss past an hour). NaN/negative
// guard to "--:--" so unsupported players never show garbage.
function formatTime(secs) {
  var s = Math.floor(Number(secs))
  if (!isFinite(s) || s < 0)
    return "--:--"
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var rest = s % 60
  var ss = (rest < 10 ? "0" : "") + rest
  if (h > 0) {
    var mm = (m < 10 ? "0" : "") + m
    return h + ":" + mm + ":" + ss
  }
  return m + ":" + ss
}
