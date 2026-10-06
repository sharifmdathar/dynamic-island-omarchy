import QtQuick
import qs.Commons
import qs.Ui
import "IslandModel.js" as Model

// Right-click options menu. Owns row models, delegates, and the label
// marquee; the island owns settings state and only receives action strings
// back through actionRequested.
PopupCard {
  id: menu

  property string labelMode: "artistTitle"
  property bool hideWhenPaused: false
  property bool showEqualizer: true
  property bool showHoverControls: true
  property bool showNotifications: true
  property bool showUnreadBadge: true
  property string pinnedPlayer: ""
  property var players: []

  // Now-playing info for the header.
  property string mediaTitle: ""
  property string mediaArtist: ""
  property string mediaAlbum: ""
  property string mediaArt: ""
  property string playerName: ""

  // Track progress (seconds). Written by the island from MprisPlayer;
  // length <= 0 or canSeek false hides the seek bar.
  property double position: 0
  property double length: 0
  property bool canSeek: false

  // Playback modes. Both rows disappear when the player supports neither.
  property bool canShuffle: false
  property bool shuffleOn: false
  property bool canLoop: false
  property int loopMode: 0
  property string loopLabel: "Repeat"
  readonly property var modeRows: {
    var rows = []
    if (menu.canShuffle)
      rows.push({ label: "Shuffle", checked: menu.shuffleOn, action: "mode|shuffle" })
    if (menu.canLoop)
      rows.push({ label: menu.loopLabel, checked: menu.loopMode !== 0, action: "mode|repeat" })
    return rows
  }

  // Settings sections start collapsed; the header expands them.
  property bool settingsExpanded: false
  onOpenChanged: if (!open) settingsExpanded = false

  signal actionRequested(string action)
  signal seekRequested(double position)
  signal raiseRequested()

  // Media chrome (header, seek bar, playback rows) disappears when nothing
  // is playing, so the card can open onto the inbox alone.
  property bool hasMedia: true

  // Notification archive: newest-first rows of { file, app, summary, body,
  // execArgv, timestamp }, read by the island from the service's history.
  property var inboxRows: []
  property int unread: 0
  // Last time the island counted the archive as read; rows after it are new.
  // real, not int: a millisecond epoch does not fit in 32 bits.
  property real seenAt: 0

  signal inboxInvoke(int index)
  signal inboxDismiss(int index)
  signal inboxClear()

  // Relative ages, refreshed by the island while the card is open. The
  // clock lives there: this card's default property takes items only.
  property real nowMs: Date.now()
  readonly property var inboxList: Array.isArray(menu.inboxRows) ? menu.inboxRows : []

  contentWidth: menu.fittedContentWidth(Style.space(240))
  contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

  readonly property var labelModeRows: [
    { label: "Title only",             checked: menu.labelMode === "title",            action: "label|title" },
    { label: "Artist - Title",         checked: menu.labelMode === "artistTitle",      action: "label|artistTitle" },
    { label: "Title · Album",          checked: menu.labelMode === "titleAlbum",       action: "label|titleAlbum" },
    { label: "Artist - Title · Album", checked: menu.labelMode === "artistTitleAlbum", action: "label|artistTitleAlbum" }
  ]
  readonly property var behaviorRows: [
    { label: "Equalizer animation", checked: menu.showEqualizer, action: "opt|showEqualizer" },
    { label: "Hover controls", checked: menu.showHoverControls, action: "opt|showHoverControls" },
    { label: "Show notifications", checked: menu.showNotifications, action: "opt|showNotifications" },
    { label: "Unread badge", checked: menu.showUnreadBadge, action: "opt|showUnreadBadge" },
    { label: "Hide when paused", checked: menu.hideWhenPaused, action: "opt|hideWhenPaused" }
  ]
  readonly property var pinnedPlayerRows: [{ label: "Automatic", checked: menu.pinnedPlayer === "", action: "pin|" }].concat(
    menu.players.map(function(p) {
      var key = Model.playerKey(p)
      return { label: Model.playerLabel(p), checked: menu.pinnedPlayer !== "" && menu.pinnedPlayer === key, action: "pin|" + key }
    })
  )

  property Component menuHeader: Text {
    text: modelData
    color: Color.bar.text
    opacity: 0.55
    font.family: Style.font.family
    font.pixelSize: 10
    font.weight: Font.Medium
  }
  property Component menuDivider: Rectangle {
    width: parent.width
    height: 1
    color: Color.bar.text
    opacity: 0.15
  }
  property Component menuRow: Item {
      width: parent.width
      height: 28
      // Selection chrome follows the house pattern (CursorSurface): hover
      // and selected fills derived from foreground + accent. bar.active is
      // the attention/urgent color (red on Nord) — wrong semantics here.
      Rectangle {
        anchors.fill: parent
        radius: 6
        color: rowMouse.containsMouse
          ? Style.hoverFillFor(Color.bar.text, Color.accent)
          : (modelData.checked ? Style.selectedFillFor(Color.bar.text, Color.accent) : "transparent")
      }
      // Label clip: fits the row; when the text overflows (e.g. the long
      // album row at fixed menu width) it marquee-scrolls on hover.
      Item {
        id: labelClip
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: checkGlyph.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        height: 18
        clip: true
        Text {
          id: rowLabel
          text: modelData.label
          color: Color.bar.text
          font.family: Style.font.family
          font.pixelSize: 12
        }
        SequentialAnimation {
          id: marquee
          loops: Animation.Infinite
          running: rowMouse.containsMouse && rowLabel.contentWidth > labelClip.width
          onRunningChanged: if (!running) rowLabel.x = 0
          PauseAnimation { duration: 600 }
          NumberAnimation {
            target: rowLabel
            property: "x"
            from: 0
            to: -(rowLabel.contentWidth - labelClip.width)
            duration: Math.max(800, (rowLabel.contentWidth - labelClip.width) * 15)
            easing.type: Easing.Linear
          }
          PauseAnimation { duration: 600 }
          NumberAnimation { target: rowLabel; property: "x"; to: 0; duration: 400 }
        }
      }
      Text {
        id: checkGlyph
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: "✓"
        color: Color.accent
        font.pixelSize: 12
        visible: modelData.checked
      }
      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: menu.actionRequested(modelData.action)
      }
    }

  // Inbox row: sender · summary on one line, age and a dismiss cross on the
  // right. The row itself runs the notification's own click action.
  //
  // Hovering unfolds the row in place: the body wraps out under the headline
  // so a long notification is readable without leaving the card. Only the
  // bottom edge moves — the row's top stays put, which is what keeps the
  // cursor inside it while it grows and the rows below slide down.
  property Component inboxRow: Item {
      id: inboxRowItem
      width: parent.width
      // Two independent hover sources: the row's MouseArea (which already
      // drives the selection highlight) and a passive HoverHandler, so the
      // unfold still works where a MouseArea's hover gets eaten by a sibling.
      readonly property bool rowHovered: inboxRowMouse.containsMouse || rowHover.hovered
      // Something the one-line form is hiding: a body to unfold, or a headline
      // the row is currently eliding. Rows with neither stay one line high.
      readonly property bool hasMore: String(modelData.body || "") !== ""
        || (headlineText.width > 0 && headlineMetrics.advanceWidth > headlineText.width + 1)
      readonly property bool expanded: rowHovered && hasMore
      // contentHeight is the height of the *wrapped* layout; implicitHeight is
      // measured against the unwrapped natural width, so it reports one line
      // for a paragraph. Floored at one line and capped at eight so a runaway
      // notification cannot push the card off screen; `elide` marks the cut.
      readonly property real bodyHeight: Math.max(14, Math.min(bodyText.contentHeight, 8 * 15))
      height: expanded ? Math.ceil(32 + bodyHeight) : 28
      clip: true

      Behavior on height {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }

      Rectangle {
        anchors.fill: parent
        radius: 6
        color: Style.hoverFillFor(Color.bar.text, Color.accent)
        opacity: (inboxRowMouse.containsMouse || inboxCrossMouse.containsMouse) ? 1 : 0
      }
      // New since the last look; read rows just sit dimmer. Pinned to the
      // headline line so an unfolded row does not drag it to its middle.
      Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.top: parent.top
        anchors.topMargin: 11
        width: 5
        height: 5
        radius: 2.5
        color: Color.accent
        visible: modelData.timestamp > menu.seenAt
      }
      // Headline line: app · summary, age, dismiss cross — one fixed band at
      // the top of the row, so all three hold their place as it unfolds.
      Item {
        id: headlineLine
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.top: parent.top
        anchors.topMargin: 6
        height: 16
        Text {
          id: headlineText
          anchors.left: parent.left
          anchors.right: inboxAge.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: (modelData.app !== "" ? modelData.app + " · " : "") + (modelData.summary !== "" ? modelData.summary : modelData.body)
          color: Color.bar.text
          opacity: modelData.timestamp > menu.seenAt ? 1 : 0.62
          font.family: Style.font.family
          font.pixelSize: 12
          textFormat: Text.PlainText
          elide: Text.ElideRight
          maximumLineCount: 1
        }
        Text {
          id: inboxAge
          anchors.right: inboxCross.left
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          text: Model.relTime(modelData.timestamp, menu.nowMs)
          color: Color.bar.text
          opacity: 0.45
          font.family: Style.font.family
          font.pixelSize: 10
          textFormat: Text.PlainText
        }
        Text {
          id: inboxCross
          anchors.right: parent.right
          anchors.rightMargin: 4
          anchors.verticalCenter: parent.verticalCenter
          text: "✕"
          color: Color.bar.text
          opacity: inboxCrossMouse.containsMouse ? 1 : 0.45
          font.pixelSize: 11
        }
      }
      // The notification body, unfolded only while expanded.
      Text {
        id: bodyText
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.top: headlineLine.bottom
        anchors.topMargin: 2
        text: modelData.body
        visible: inboxRowItem.expanded
        color: Color.bar.text
        opacity: 0.72
        font.family: Style.font.family
        font.pixelSize: 11
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        maximumLineCount: 8
        elide: Text.ElideRight
      }
      // Width of the headline unwrapped, for the hasMore test. Reading it off
      // headlineText would flip the moment the row unfolds and that text
      // re-lays-out, so measure the string separately.
      TextMetrics {
        id: headlineMetrics
        font.family: Style.font.family
        font.pixelSize: 12
        text: headlineText.text
      }
      // Passive: keeps the unfold working even if the MouseArea's hover is
      // taken by the dismiss strip. Never consumes clicks.
      HoverHandler { id: rowHover }
      MouseArea {
        id: inboxRowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: menu.inboxInvoke(index)
      }
      // Declared after the row so the cross keeps the strip it covers.
      MouseArea {
        id: inboxCrossMouse
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.top: parent.top
        width: 22
        height: 28
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: menu.inboxDismiss(index)
      }
    }

  Column {
    id: menuColumn
    anchors.fill: parent
    spacing: 2

    // Now-playing header: large artwork with title / artist / album on
    // separate lines. Clicking it raises the player app; the Settings
    // button below expands the settings sections.
    Item {
      width: parent.width
      height: 68
      visible: menu.hasMedia
      Rectangle {
        anchors.fill: parent
        radius: 6
        color: Style.hoverFillFor(Color.bar.text, Color.accent)
        opacity: headerMouse.containsMouse ? 1 : 0
      }
      // Big artwork tile.
      Item {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 52
        height: 52
        Rectangle {
          anchors.fill: parent
          radius: 8
          color: Color.bar.background
          visible: menu.mediaArt === ""
        }
        Text {
          anchors.centerIn: parent
          text: "♪"
          color: Color.bar.text
          font.pixelSize: 20
          visible: menu.mediaArt === ""
        }
        Image {
          anchors.fill: parent
          source: menu.mediaArt
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize: Qt.size(104, 104)
          visible: menu.mediaArt !== ""
        }
      }
      Column {
        anchors.left: parent.left
        anchors.leftMargin: 68
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
          width: parent.width
          text: menu.mediaTitle !== "" ? menu.mediaTitle : menu.mediaArtist
          color: Color.bar.text
          font.family: Style.font.family
          font.pixelSize: 13
          font.weight: Font.Medium
          textFormat: Text.PlainText
          elide: Text.ElideRight
          maximumLineCount: 1
        }
        Text {
          width: parent.width
          text: (menu.mediaTitle !== "" && menu.mediaArtist !== "")
            ? menu.mediaArtist : menu.playerName
          color: Color.bar.text
          opacity: 0.75
          font.family: Style.font.family
          font.pixelSize: 12
          textFormat: Text.PlainText
          elide: Text.ElideRight
          maximumLineCount: 1
          visible: text !== ""
        }
        Text {
          width: parent.width
          text: menu.mediaAlbum
          color: Color.bar.text
          opacity: 0.6
          font.family: Style.font.family
          textFormat: Text.PlainText
          font.pixelSize: 11
          elide: Text.ElideRight
          maximumLineCount: 1
          visible: menu.mediaAlbum !== ""
        }
      }
      MouseArea {
        id: headerMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: menu.raiseRequested()
      }
    }

    // Seek bar: elapsed + clickable progress + total. Drag previews
    // locally; the target position commits on release.
    Item {
      id: seekBox
      width: parent.width
      height: 26
      visible: menu.hasMedia && menu.canSeek && menu.length > 0
      property bool scrubbing: false
      property double scrubPos: 0
      readonly property double shownPos: scrubbing ? scrubPos : Math.max(0, Math.min(menu.position, menu.length))
      function clampToTrack(x, w) {
        if (!(w > 0) || !(menu.length > 0))
          return 0
        var r = x / w
        if (r < 0) r = 0
        if (r > 1) r = 1
        return r * menu.length
      }
      Row {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: 36
          text: Model.formatTime(seekBox.shownPos)
          color: Color.bar.text
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: 10
          horizontalAlignment: Text.AlignRight
        }
        Item {
          id: seekTrack
          width: parent.width - 36 - 36 - 16
          height: 16
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 4
            radius: 2
            color: Color.bar.text
            opacity: 0.2
          }
          Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: menu.length > 0 ? parent.width * (seekBox.shownPos / menu.length) : 0
            height: 4
            radius: 2
            color: Color.accent
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: (menu.length > 0 ? parent.width * (seekBox.shownPos / menu.length) : 0) - 5
            width: 10
            height: 10
            radius: 5
            color: Color.accent
            visible: seekMouse.containsMouse || seekBox.scrubbing
          }
          MouseArea {
            id: seekMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            onPressed: function(mouse) {
              seekBox.scrubbing = true
              seekBox.scrubPos = seekBox.clampToTrack(mouse.x, seekTrack.width)
            }
            onPositionChanged: function(mouse) {
              if ((seekMouse.pressedButtons & Qt.LeftButton) && seekBox.scrubbing)
                seekBox.scrubPos = seekBox.clampToTrack(mouse.x, seekTrack.width)
            }
            onReleased: function(mouse) {
              if (seekBox.scrubbing) {
                seekBox.scrubbing = false
                menu.seekRequested(seekBox.scrubPos)
              }
            }
            onCanceled: seekBox.scrubbing = false
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: 36
          text: Model.formatTime(menu.length)
          color: Color.bar.text
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: 10
        }
      }
    }

    // Playback modes: shuffle and repeat toggles straight under the seek
    // bar. Tapping one keeps the menu open so the row flips in place.
    Column {
      width: parent.width
      spacing: 2
      visible: menu.hasMedia && menu.modeRows.length > 0
      Rectangle {
        width: parent.width
        height: 1
        color: Color.bar.text
        opacity: 0.15
      }
      Repeater { model: ["Playback"]; delegate: menuHeader }
      Repeater { model: menu.modeRows; delegate: menuRow }
    }

    // Notification archive, newest first. A row runs the notification's own
    // click action and leaves the archive; the cross drops it without
    // acting. Capped so a full archive cannot push the card off screen.
    Column {
      width: parent.width
      spacing: 2
      visible: menu.showNotifications && menu.inboxList.length > 0
      Rectangle {
        width: parent.width
        height: 1
        color: Color.bar.text
        opacity: 0.15
      }
      Item {
        width: parent.width
        height: 20
        Text {
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          text: "Notifications" + (menu.unread > 0 ? " · " + menu.unread + " new" : "")
          color: Color.bar.text
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: 10
          font.weight: Font.Medium
          textFormat: Text.PlainText
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          text: "Clear all"
          color: Color.accent
          opacity: inboxClearMouse.containsMouse ? 1 : 0.7
          font.family: Style.font.family
          font.pixelSize: 10
          textFormat: Text.PlainText
        }
        MouseArea {
          id: inboxClearMouse
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 64
          height: 20
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: menu.inboxClear()
        }
      }
      Repeater { model: menu.inboxList.slice(0, 8); delegate: menu.inboxRow }
    }

    // Explicit Settings button; expands/collapses the sections below.
    Item {
      width: parent.width
      height: 30
      Rectangle {
        anchors.fill: parent
        radius: 6
        color: Style.hoverFillFor(Color.bar.text, Color.accent)
        opacity: settingsMouse.containsMouse ? 1 : 0
      }
      Text {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: "⚙  Settings"
        color: Color.bar.text
        font.family: Style.font.family
        font.pixelSize: 12
        font.weight: Font.Medium
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: menu.settingsExpanded ? "▾" : "▸"
        color: Color.bar.text
        opacity: 0.6
        font.pixelSize: 11
      }
      MouseArea {
        id: settingsMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: menu.settingsExpanded = !menu.settingsExpanded
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Color.bar.text
      opacity: 0.15
    }

    Column {
      width: parent.width
      spacing: 2
      visible: menu.settingsExpanded

      Repeater { model: ["Label"]; delegate: menuHeader }
      Repeater { model: menu.labelModeRows; delegate: menuRow }

      Repeater { model: [0]; delegate: menuDivider }

      Repeater { model: ["Behavior"]; delegate: menuHeader }
      Repeater { model: menu.behaviorRows; delegate: menuRow }

      Repeater { model: [0]; delegate: menuDivider }

      Repeater { model: ["Player"]; delegate: menuHeader }
      Repeater { model: menu.pinnedPlayerRows; delegate: menuRow }
    }
  }
}
