import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Stage Manager"

    iconComponent: Component {
      Item {
        readonly property color ink: button.foreground

        // macOS-style Stage Manager glyph: one stage and three recent sets.
        Rectangle {
          x: Style.spaceReal(7.5)
          y: Style.spaceReal(2.5)
          width: Style.spaceReal(8)
          height: Style.spaceReal(11)
          radius: Style.spaceReal(1.6)
          color: "transparent"
          border.width: Math.max(1, Style.spaceReal(1.2))
          border.color: parent.ink
        }

        Repeater {
          model: 3

          Rectangle {
            required property int index
            x: Style.spaceReal(1.2)
            y: Style.spaceReal(3 + index * 4)
            width: Style.spaceReal(4.2)
            height: Style.spaceReal(2.5)
            radius: height / 2
            color: parent.ink
            opacity: 0.88
          }
        }
      }
    }

    onPressed: function(buttonCode) {
      if (!root.bar || buttonCode !== Qt.LeftButton) return
      root.bar.run("omarchy-shell shell toggle debba.stage-manager '{}'")
    }
  }
}
