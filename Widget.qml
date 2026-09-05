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
    tooltipText: "OmaStage"

    iconComponent: Component {
      Item {
        readonly property color ink: button.foreground

        // macOS-style Stage Manager glyph: one central stage and three stacked thumbnails
        Rectangle {
          x: Style.spaceReal(7.5)
          y: Style.spaceReal(2.5)
          width: Style.spaceReal(8)
          height: Style.spaceReal(11)
          radius: Style.spaceReal(1.8)
          color: "transparent"
          border.width: Math.max(1, Style.spaceReal(1.2))
          border.color: parent.ink
        }

        Repeater {
          model: 3

          Rectangle {
            required property int index
            x: Style.spaceReal(1.2)
            y: Style.spaceReal(3 + index * 3.8)
            width: Style.spaceReal(4.4)
            height: Style.spaceReal(2.4)
            radius: height / 2
            color: parent.ink
            opacity: 0.88 - index * 0.12
          }
        }
      }
    }

    onPressed: function(buttonCode) {
      if (!root.bar || buttonCode !== Qt.LeftButton) return
      root.bar.run("omarchy-shell shell toggle dorneles.omastage '{}'")
    }
  }
}
