import QtQuick
import qs.Commons

// Prev / play-pause / next buttons revealed on pill hover. Dumb by design:
// the island owns player state, this only reports presses as signals.
//
// Hit bands are gapless and span the full pill height, so a slightly
// off-target click lands on a button instead of falling through to the pill
// behind it (which would toggle playback). Icons grow on hover.
Row {
  id: root
  property var player: null
  property bool playing: false
  // Vertical band each button occupies. The caller binds this to the pill's
  // content height so a click anywhere in the slot hits a button.
  property real slotHeight: 20
  // Gapless slot width; the caller keeps its width reservation at 3 * slotWidth.
  readonly property real slotWidth: 31

  signal prevRequested()
  signal toggleRequested()
  signal nextRequested()
  signal raiseRequested()
  // Wheel over a button band never reaches the pill's volume handler, so
  // forward it to the island.
  signal volumeUp()
  signal volumeDown()

  // The bands sit above the pill's own MouseArea, so hover can be delivered
  // to them instead of the pill. The island ORs this with its own hover.
  readonly property bool bandHovered:
    bandPrev.containsMouse || bandToggle.containsMouse || bandNext.containsMouse

  spacing: 0

  Item {
    width: root.slotWidth
    height: root.slotHeight
    Item {
      anchors.centerIn: parent
      scale: bandPrev.containsMouse ? 1.22 : 1
      Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Text {
        anchors.centerIn: parent
        text: "◀◀"
        color: Color.bar.text
        font.pixelSize: 11
        opacity: root.player && root.player.canGoPrevious ? 1 : 0.35
      }
    }
    MouseArea {
      id: bandPrev
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      property int pressModifiers: 0
      onPressed: function(mouse) { pressModifiers = mouse.modifiers }
      onWheel: function(wheel) {
        var d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
        if (d > 0) { root.volumeUp(); wheel.accepted = true }
        else if (d < 0) { root.volumeDown(); wheel.accepted = true }
      }
      onClicked: {
        if (pressModifiers & Qt.ShiftModifier) root.raiseRequested()
        else root.prevRequested()
      }
    }
  }

  Item {
    width: root.slotWidth
    height: root.slotHeight
    Item {
      anchors.centerIn: parent
      scale: bandToggle.containsMouse ? 1.22 : 1
      Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      opacity: (root.playing && root.player && !root.player.canPause
        || !root.playing && root.player && !root.player.canPlay) ? 0.35 : 1
      Text {
        anchors.centerIn: parent
        text: "▶"
        color: Color.bar.text
        font.pixelSize: 13
        visible: !root.playing
      }
      // Drawn bars instead of the ❚❚ glyph: glyph metrics sit it above
      // the text baseline, while rectangles stay exactly centered.
      Row {
        anchors.centerIn: parent
        spacing: 3
        visible: root.playing
        Repeater {
          model: 2
          Rectangle {
            width: 3
            height: 11
            radius: 1
            color: Color.bar.text
          }
        }
      }
    }
    MouseArea {
      id: bandToggle
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      property int pressModifiers: 0
      onPressed: function(mouse) { pressModifiers = mouse.modifiers }
      onWheel: function(wheel) {
        var d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
        if (d > 0) { root.volumeUp(); wheel.accepted = true }
        else if (d < 0) { root.volumeDown(); wheel.accepted = true }
      }
      onClicked: {
        if (pressModifiers & Qt.ShiftModifier) root.raiseRequested()
        else root.toggleRequested()
      }
    }
  }

  Item {
    width: root.slotWidth
    height: root.slotHeight
    Item {
      anchors.centerIn: parent
      scale: bandNext.containsMouse ? 1.22 : 1
      Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Text {
        anchors.centerIn: parent
        text: "▶▶"
        color: Color.bar.text
        font.pixelSize: 11
        opacity: root.player && root.player.canGoNext ? 1 : 0.35
      }
    }
    MouseArea {
      id: bandNext
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      property int pressModifiers: 0
      onPressed: function(mouse) { pressModifiers = mouse.modifiers }
      onWheel: function(wheel) {
        var d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
        if (d > 0) { root.volumeUp(); wheel.accepted = true }
        else if (d < 0) { root.volumeDown(); wheel.accepted = true }
      }
      onClicked: {
        if (pressModifiers & Qt.ShiftModifier) root.raiseRequested()
        else root.nextRequested()
      }
    }
  }
}
