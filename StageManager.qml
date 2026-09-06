import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool revealed: false
  property bool focusPrimed: false
  property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  property int targetMonitorId: -1
  property string targetMonitorName: ""
  property var groups: []
  property var flatWindows: []
  property string selectedAddress: ""
  property bool keyboardNavActive: false
  property bool hideActive: true // Default: hide active window on stage (macOS faithful)

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color accentColor: Color.accent || Color.menu.selectedText
  readonly property var activeWindowBorderSpec: Border.hyprlandActiveSpec(borderColor, Style.space(2))
  readonly property string fontFamily: Style.font.menuFamily
  readonly property real screenWidth: targetScreen ? targetScreen.width : 1280
  readonly property real screenHeight: targetScreen ? targetScreen.height : 1080
  readonly property int railWidth: Math.round(Math.max(Style.space(216), Math.min(Style.space(248), screenWidth * 0.175)))
  readonly property int panelGap: Style.gapsOut

  // Dynamic vertical scaling so all groups fit within viewport without scrolling
  readonly property int availableStageHeight: Math.max(Style.space(300), Math.round((panel.height > 0 ? panel.height : screenHeight) - Style.space(72)))
  readonly property int groupCount: Math.max(1, groups.length)
  readonly property int groupSpacing: Math.max(Style.space(6), Math.min(Style.space(16), Math.round(availableStageHeight * 0.02)))
  readonly property int maxGroupHeight: Math.floor((availableStageHeight - (groupCount - 1) * groupSpacing) / groupCount)
  readonly property int dynMaxThumbHeight: Math.max(Style.space(42), maxGroupHeight - Style.space(28))
  readonly property int maxThumbnailWidth: railWidth - Style.space(24)
  readonly property int maxThumbnailHeight: Math.min(Math.round(maxThumbnailWidth * 0.72), dynMaxThumbHeight)
  readonly property int minThumbnailHeight: Math.max(Style.space(34), Math.min(maxThumbnailHeight, Math.round(maxThumbnailHeight * 0.55)))
  readonly property int minThumbnailWidth: Math.round(maxThumbnailWidth * 0.38)
  readonly property real cardRadius: Math.max(Style.space(8), Math.min(Style.space(16), maxThumbnailHeight * 0.14))

  function screenByName(name) {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name) === String(name)) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function normalize(value) {
    return String(value || "").trim().toLowerCase()
  }

  function friendlyName(value) {
    var text = String(value || "Application")
      .replace(/^org\./i, "")
      .replace(/^com\./i, "")
      .replace(/[._-]+/g, " ")
      .trim()
    if (text === "") return "Application"
    return text.split(/\s+/).map(function(word) {
      return word.charAt(0).toUpperCase() + word.slice(1)
    }).join(" ")
  }

  function desktopEntryFor(values) {
    var applications = DesktopEntries.applications.values || []
    var candidates = []
    for (var i = 0; i < values.length; i++) {
      var candidate = normalize(values[i])
      if (candidate !== "" && candidates.indexOf(candidate) === -1) candidates.push(candidate)
    }

    for (var c = 0; c < candidates.length; c++) {
      var exact = DesktopEntries.byId(candidates[c])
      if (exact) return exact
    }

    for (var a = 0; a < applications.length; a++) {
      var entry = applications[a]
      var entryId = normalize(entry.id)
      var startupClass = normalize(entry.startupClass)
      for (var k = 0; k < candidates.length; k++) {
        var needle = candidates[k]
        if (entryId === needle || startupClass === needle || entryId === needle + ".desktop") return entry
      }
    }

    for (var h = 0; h < candidates.length; h++) {
      var heuristic = DesktopEntries.heuristicLookup(candidates[h])
      if (heuristic) return heuristic
    }
    return null
  }

  function iconSource(icon) {
    var name = String(icon || "")
    if (name.indexOf("file://") === 0 || name.indexOf("image://") === 0) return name
    if (name.charAt(0) === "/") return "file://" + name
    var resolved = name !== "" ? Quickshell.iconPath(name, true) : ""
    if (resolved !== "") return resolved
    return Quickshell.iconPath("application-x-executable", true)
  }

  function isSameStructure(nextGroups) {
    if (!root.groups || root.groups.length !== nextGroups.length) return false
    for (var g = 0; g < nextGroups.length; g++) {
      var og = root.groups[g]
      var ng = nextGroups[g]
      if (og.key !== ng.key || og.windows.length !== ng.windows.length) return false
      for (var w = 0; w < ng.windows.length; w++) {
        if (og.windows[w].address !== ng.windows[w].address) return false
        if (og.windows[w].workspaceId !== ng.windows[w].workspaceId) return false
      }
    }
    return true
  }

  function rebuild(initialSort) {
    var values = Hyprland.toplevels.values || []
    var buckets = ({})
    var activeAddress = Hyprland.activeToplevel ? String(Hyprland.activeToplevel.address || "") : ""

    for (var i = 0; i < values.length; i++) {
      var toplevel = values[i]
      var ipc = toplevel.lastIpcObject || ({})
      var monitorId = toplevel.monitor ? Number(toplevel.monitor.id) : Number(ipc.monitor)
      var workspaceId = toplevel.workspace ? Number(toplevel.workspace.id)
        : Number(ipc.workspace && ipc.workspace.id)
      var mapped = ipc.mapped === undefined ? true : ipc.mapped === true

      if (!mapped || workspaceId <= 0 || monitorId !== root.targetMonitorId) continue

      var address = String(toplevel.address || ipc.address || "")

      // Hide currently active window (faithful macOS Stage Manager behavior)
      if (root.hideActive && address === activeAddress) continue

      var initialClass = String(ipc.initialClass || "")
      var currentClass = String(ipc.class || "")
      var appId = toplevel.wayland ? String(toplevel.wayland.appId || "") : ""
      var rawTitle = String(toplevel.title || ipc.title || "")

      // Filter out utility popups, Picture-in-Picture, screen sharing indicators
      if (rawTitle.indexOf("Picture-in-Picture") !== -1 ||
          rawTitle.indexOf("Picture in picture") !== -1 ||
          rawTitle === "pip" ||
          rawTitle.indexOf("Sharing Indicator") !== -1) {
        continue
      }

      var winW = 1920
      var winH = 1080
      if (ipc.size && Array.isArray(ipc.size) && ipc.size.length >= 2) {
        if (Number(ipc.size[0]) > 0) winW = Number(ipc.size[0])
        if (Number(ipc.size[1]) > 0) winH = Number(ipc.size[1])
      }

      // Ignore microscopic popups
      if (winW < 120 && winH < 120) continue

      var history = Number(ipc.focusHistoryID)
      if (!isFinite(history) || history < 0) history = 1000000

      var wsName = String(toplevel.workspace ? toplevel.workspace.name
        : (ipc.workspace && ipc.workspace.name) || workspaceId)

      var entry = root.desktopEntryFor([initialClass, currentClass, appId])
      var appDisplayName = entry ? String(entry.name || root.friendlyName(initialClass || currentClass || appId))
        : root.friendlyName(initialClass || currentClass || appId)
      var appIconSrc = root.iconSource(entry ? entry.icon : (appId || currentClass || initialClass))

      var key = normalize(initialClass || currentClass || appId || address)

      if (!buckets[key]) {
        buckets[key] = {
          key: key,
          name: appDisplayName,
          icon: appIconSrc,
          windows: [],
          recency: 1000000
        }
      }

      var record = {
        address: address,
        title: rawTitle || appDisplayName,
        workspaceId: workspaceId,
        workspaceName: wsName,
        recency: history,
        active: address === activeAddress,
        toplevel: toplevel,
        wayland: toplevel.wayland || null,
        icon: appIconSrc,
        appName: appDisplayName,
        winWidth: winW,
        winHeight: winH
      }

      buckets[key].windows.push(record)
      buckets[key].recency = Math.min(buckets[key].recency, history)
    }

    var nextGroups = []
    for (var k in buckets) {
      buckets[k].windows.sort(function(left, right) { return left.recency - right.recency })
      nextGroups.push(buckets[k])
    }

    // Freeze order during open session; sort MRU when opening freshly
    if (initialSort || root.groups.length === 0) {
      nextGroups.sort(function(left, right) { return left.recency - right.recency })
    } else {
      // Preserve existing group order to avoid cards shifting under the cursor
      var orderMap = ({})
      for (var og = 0; og < root.groups.length; og++) {
        orderMap[root.groups[og].key] = og
      }
      nextGroups.sort(function(left, right) {
        var oL = orderMap[left.key] !== undefined ? orderMap[left.key] : (1000 + left.recency)
        var oR = orderMap[right.key] !== undefined ? orderMap[right.key] : (1000 + right.recency)
        return oL - oR
      })
    }

    var nextFlat = []
    for (var g = 0; g < nextGroups.length; g++) {
      for (var w = 0; w < nextGroups[g].windows.length; w++) nextFlat.push(nextGroups[g].windows[w])
    }

    // In-place update if window topology hasn't changed to eliminate flickering
    if (!initialSort && root.isSameStructure(nextGroups)) {
      for (var sg = 0; sg < nextGroups.length; sg++) {
        root.groups[sg].name = nextGroups[sg].name
        root.groups[sg].icon = nextGroups[sg].icon
        for (var sw = 0; sw < nextGroups[sg].windows.length; sw++) {
          root.groups[sg].windows[sw].title = nextGroups[sg].windows[sw].title
          root.groups[sg].windows[sw].active = nextGroups[sg].windows[sw].active
        }
      }
      root.flatWindows = nextFlat
    } else {
      root.groups = nextGroups
      root.flatWindows = nextFlat
    }

    var selectedStillExists = false
    for (var f = 0; f < nextFlat.length; f++) {
      if (nextFlat[f].address === root.selectedAddress) selectedStillExists = true
    }

    if (initialSort) {
      root.selectedAddress = nextFlat.length > 0 ? nextFlat[0].address : ""
    } else if (!selectedStillExists) {
      root.selectedAddress = activeAddress || (nextFlat.length > 0 ? nextFlat[0].address : "")
    }
  }

  Timer {
    id: closeTimer
    interval: 280
    repeat: false
    onTriggered: {
      root.opened = false
      if (root.shell && typeof root.shell.hide === "function" && typeof root.shell.isPluginOpen === "function" && root.shell.isPluginOpen("dorneles.omastage")) {
        root.shell.hide("dorneles.omastage")
      }
    }
  }

  function open(payloadJson) {
    closeTimer.stop()
    var monitor = Hyprland.focusedMonitor
    root.targetMonitorId = monitor ? Number(monitor.id) : 0
    root.targetMonitorName = monitor ? String(monitor.name || "") : ""
    root.targetScreen = root.screenByName(root.targetMonitorName)
    root.selectedAddress = Hyprland.activeToplevel ? String(Hyprland.activeToplevel.address || "") : ""
    root.rebuild(true)
    root.focusPrimed = false
    root.revealed = false
    root.opened = true
    root.keyboardNavActive = false
    focusPrimeTimer.restart()
    Qt.callLater(function() {
      root.revealed = true
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    if (!root.opened && !root.revealed && !closeTimer.running) return
    focusPrimeTimer.stop()
    root.focusPrimed = false
    root.revealed = false
    root.keyboardNavActive = false
    closeTimer.restart()
  }

  function toggle() {
    if (root.opened && root.revealed && !closeTimer.running) root.close()
    else root.open("{}")
  }

  function status(arg) {
    return JSON.stringify({
      opened: root.opened && root.revealed,
      monitor: root.targetMonitorName,
      groups: root.groups.length,
      windows: root.flatWindows.length,
      reservedWidth: (root.opened && root.revealed && panel.exclusionMode !== ExclusionMode.Ignore) ? panel.implicitWidth : 0
    })
  }

  function selectedIndex() {
    for (var i = 0; i < root.flatWindows.length; i++) {
      if (root.flatWindows[i].address === root.selectedAddress) return i
    }
    return -1
  }

  function select(delta) {
    if (root.flatWindows.length === 0) return
    var current = root.selectedIndex()
    if (current < 0) current = delta < 0 ? 0 : -1
    var next = (current + delta + root.flatWindows.length) % root.flatWindows.length
    root.selectedAddress = root.flatWindows[next].address
  }

  function cycleGroupWindow(delta) {
    if (root.groups.length === 0) return
    for (var g = 0; g < root.groups.length; g++) {
      var group = root.groups[g]
      for (var w = 0; w < group.windows.length; w++) {
        if (group.windows[w].address === root.selectedAddress) {
          if (group.windows.length > 1) {
            var nextW = (w + delta + group.windows.length) % group.windows.length
            root.selectedAddress = group.windows[nextW].address
          }
          return
        }
      }
    }
  }

  function revealGroup(item) {
    if (!item || !appFlick) return
    var top = groupsColumn.y + item.y
    var bottom = top + item.height
    if (top < appFlick.contentY) appFlick.contentY = top
    else if (bottom > appFlick.contentY + appFlick.height)
      appFlick.contentY = Math.min(Math.max(0, appFlick.contentHeight - appFlick.height), bottom - appFlick.height)
  }

  function activate(record) {
    if (!record) return
    var wayland = record.wayland
    var address = String(record.address || "")
    root.close()
    Qt.callLater(function() {
      if (wayland && typeof wayland.activate === "function") {
        wayland.activate()
      } else if (/^0x[0-9a-fA-F]+$/.test(address)) {
        Quickshell.execDetached(["hyprctl", "eval", 'hl.dispatch(hl.dsp.exec_cmd("focuswindow address:' + address + '"))'])
      }
    })
  }

  function activateSelected() {
    var index = root.selectedIndex()
    if (index >= 0) root.activate(root.flatWindows[index])
  }

  Timer {
    id: focusPrimeTimer
    interval: 80
    repeat: false
    onTriggered: {
      root.focusPrimed = true
      keyCatcher.forceActiveFocus()
    }
  }

  Timer {
    id: rebuildTimer
    interval: 80
    repeat: false
    onTriggered: if (root.opened && root.revealed) root.rebuild(false)
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      if (root.opened && root.revealed) rebuildTimer.restart()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var structural = [
        "openwindow", "closewindow", "movewindow", "movewindowv2",
        "workspace", "workspacev2", "focusedmon", "changefloatingmode"
      ]
      if (root.opened && root.revealed && structural.indexOf(event.name) !== -1) rebuildTimer.restart()
    }
  }

  HyprlandFocusGrab {
    active: root.opened && root.revealed
    windows: panel.visible ? [panel] : []
    onCleared: if (root.opened && root.revealed) root.close()
  }

  PanelWindow {
    id: panel

    visible: root.opened
    screen: root.targetScreen
    color: "transparent"
    implicitWidth: root.railWidth + root.panelGap * 2
    exclusionMode: ExclusionMode.Ignore
    surfaceFormat.opaque: false

    anchors {
      top: true
      bottom: true
      left: true
    }

    WlrLayershell.namespace: "omastage"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: (root.opened && root.revealed)
      ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      z: 20

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
          root.keyboardNavActive = true
          root.select(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
          root.keyboardNavActive = true
          root.select(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          root.keyboardNavActive = true
          root.cycleGroupWindow(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          root.keyboardNavActive = true
          root.cycleGroupWindow(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          root.activateSelected()
          event.accepted = true
        }
      }
    }

    // Translucent blurred glass backdrop with soft curved horizontal wash
    Rectangle {
      anchors.fill: parent
      opacity: root.revealed ? 1 : 0

      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
          position: 0.0
          color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.58)
        }
        GradientStop {
          position: 0.65
          color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.35)
        }
        GradientStop {
          position: 0.90
          color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.12)
        }
        GradientStop {
          position: 1.0
          color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.0)
        }
      }

      Behavior on opacity {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
      }
    }

    // Soft glass rim on outer right boundary
    Rectangle {
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      width: 1
      opacity: root.revealed ? 0.30 : 0

      gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.2; color: Qt.rgba(1, 1, 1, 0.10) }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.20) }
        GradientStop { position: 0.8; color: Qt.rgba(1, 1, 1, 0.10) }
        GradientStop { position: 1.0; color: "transparent" }
      }

      Behavior on opacity {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
      }
    }

    HoverHandler { id: panelHover }

    Item {
      id: stageRail
      x: root.revealed ? root.panelGap : -Math.round(root.railWidth * 0.35)
      y: 0
      width: root.railWidth
      height: panel.height
      opacity: root.revealed ? 1 : 0

      Behavior on x {
        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
      }

      Behavior on opacity {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
      }

      // Close button (Top Right)
      Rectangle {
        id: closeButton
        z: 1000
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.space(8)
        anchors.rightMargin: Style.space(6)
        width: Style.space(22)
        height: width
        radius: width / 2
        opacity: panelHover.hovered || closeMouse.containsMouse ? 1 : 0
        scale: closeMouse.containsMouse ? 1.08 : 1.0
        color: closeMouse.pressed
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.26)
          : (closeMouse.containsMouse
            ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
            : Qt.rgba(root.background.r, root.background.g, root.background.b, 0.74))
        border.width: 1
        border.color: closeMouse.containsMouse
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.32)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "✕"
          color: root.foreground
          opacity: 0.82
          font.family: root.fontFamily
          font.pixelSize: Style.space(9.5)
          font.bold: true
        }

        MouseArea {
          id: closeMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.close()
        }
      }

      Flickable {
        id: appFlick
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        anchors.topMargin: Style.space(20)
        anchors.bottomMargin: Style.space(26)
        contentWidth: width
        contentHeight: Math.max(height, groupsColumn.y + groupsColumn.implicitHeight + Style.space(10))
        clip: false
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Behavior on contentY {
          NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }

        Column {
          id: groupsColumn
          y: Math.max(0, (appFlick.height - implicitHeight) / 2)
          width: appFlick.width
          spacing: root.groupSpacing

          Repeater {
            model: root.groups

            delegate: AppGroup {
              required property var modelData
              width: groupsColumn.width
              groupData: modelData
            }
          }
        }
      }

      // Keyboard & navigation hints footer
      Item {
        id: keyboardHint
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottomMargin: Style.space(6)
        height: Style.space(18)
        opacity: (root.keyboardNavActive || panelHover.hovered) && root.flatWindows.length > 0 ? 0.70 : 0

        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        Row {
          anchors.centerIn: parent
          spacing: Style.space(4)

          Text {
            textFormat: Text.PlainText
            text: "↑↓ Navigate"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(8.5)
            opacity: 0.75
          }
          Text {
            textFormat: Text.PlainText
            text: "•"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(7.5)
            opacity: 0.4
          }
          Text {
            textFormat: Text.PlainText
            text: "←→ Window"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(8.5)
            opacity: 0.75
          }
          Text {
            textFormat: Text.PlainText
            text: "•"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(7.5)
            opacity: 0.4
          }
          Text {
            textFormat: Text.PlainText
            text: "↵ Focus"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(8.5)
            opacity: 0.75
          }
          Text {
            textFormat: Text.PlainText
            text: "•"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(7.5)
            opacity: 0.4
          }
          Text {
            textFormat: Text.PlainText
            text: "Esc Close"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(8.5)
            opacity: 0.75
          }
        }
      }

      Column {
        anchors.centerIn: parent
        width: parent.width - Style.space(24)
        spacing: Style.spacing.md
        visible: root.flatWindows.length === 0

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.space(56)
          height: width
          radius: width / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "󰕰"
            color: root.foreground
            opacity: 0.52
            font.family: Style.font.family
            font.pixelSize: Style.space(24)
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(3)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "No Windows"
            color: root.foreground
            opacity: 0.82
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "No background windows on this stage"
            color: root.foreground
            opacity: 0.48
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  component AppGroup: Item {
    id: appGroup

    property var groupData: null
    property int currentIndex: initialIndex()
    readonly property int windowCount: groupData ? groupData.windows.length : 0
    readonly property int stackDepth: Math.min(2, Math.max(0, windowCount - 1))
    readonly property bool hovered: groupHover.hovered
    readonly property bool selected: currentRecord && root.selectedAddress === currentRecord.address
    readonly property var currentRecord: groupData && windowCount > 0
      ? groupData.windows[Math.max(0, Math.min(currentIndex, windowCount - 1))] : null

    readonly property real stackOffsetX: appGroup.hovered ? Style.space(8) : Style.space(5)
    readonly property real stackOffsetY: appGroup.hovered ? Style.space(7) : Style.space(4)
    readonly property real availableWidth: root.maxThumbnailWidth - appGroup.stackDepth * stackOffsetX

    readonly property real currentAspect: {
      if (mainPreview && mainPreview.captureHasContent && mainPreview.sourceWidth > 0 && mainPreview.sourceHeight > 0) {
        return mainPreview.sourceWidth / mainPreview.sourceHeight
      }
      if (currentRecord && currentRecord.winWidth > 0 && currentRecord.winHeight > 0) {
        return currentRecord.winWidth / currentRecord.winHeight
      }
      return 16.0 / 10.0
    }

    readonly property real cardWidth: {
      var maxW = availableWidth
      var maxH = root.maxThumbnailHeight
      if (currentAspect >= (maxW / maxH)) {
        return maxW
      }
      return Math.max(root.minThumbnailWidth, Math.min(maxW, maxH * currentAspect))
    }

    readonly property real cardHeight: {
      var maxW = availableWidth
      var maxH = root.maxThumbnailHeight
      if (currentAspect >= (maxW / maxH)) {
        return Math.max(root.minThumbnailHeight, Math.min(maxH, cardWidth / currentAspect))
      }
      return maxH
    }

    readonly property real totalStackWidth: cardWidth + stackDepth * stackOffsetX

    function initialIndex() {
      if (!groupData || !groupData.windows) return 0
      for (var i = 0; i < groupData.windows.length; i++) {
        if (groupData.windows[i].address === root.selectedAddress) return i
      }
      return 0
    }

    function selectWindow(index) {
      if (!groupData || index < 0 || index >= groupData.windows.length) return
      currentIndex = index
      root.selectedAddress = groupData.windows[index].address
    }

    function syncSelection() {
      if (!groupData || !groupData.windows || !root) return
      for (var i = 0; i < groupData.windows.length; i++) {
        if (groupData.windows[i].address === root.selectedAddress) {
          currentIndex = i
          root.revealGroup(appGroup)
          return
        }
      }
    }

    function stackedRecord(layerIndex) {
      if (!groupData || windowCount < 2) return null
      return groupData.windows[(currentIndex + layerIndex + 1) % windowCount]
    }

    function selectorLabel(index) {
      if (!groupData || index < 0 || index >= groupData.windows.length) return ""
      var record = groupData.windows[index]
      var duplicates = 0
      for (var i = 0; i < groupData.windows.length; i++) {
        if (groupData.windows[i].workspaceName === record.workspaceName) duplicates++
      }
      return record.workspaceName + (duplicates > 1 ? "·" + (index + 1) : "")
    }

    implicitHeight: previewStack.height + Style.space(22)
    z: hovered ? 100 : 0
    transformOrigin: Item.Center
    scale: hovered ? 1.025 : 1

    Behavior on scale {
      NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    onGroupDataChanged: syncSelection()

    Connections {
      target: root
      function onSelectedAddressChanged() { appGroup.syncSelection() }
    }

    HoverHandler { id: groupHover }

    // Scroll wheel handler to cycle through windows of this application
    WheelHandler {
      id: groupWheel
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) {
        if (appGroup.windowCount <= 1) return
        if (event.angleDelta.y < 0) {
          appGroup.selectWindow((appGroup.currentIndex + 1) % appGroup.windowCount)
        } else if (event.angleDelta.y > 0) {
          appGroup.selectWindow((appGroup.currentIndex - 1 + appGroup.windowCount) % appGroup.windowCount)
        }
      }
    }

    Item {
      id: groupBoundingContainer
      anchors.horizontalCenter: parent.horizontalCenter
      width: appGroup.totalStackWidth
      height: appGroup.implicitHeight

      Item {
        id: previewStack
        width: parent.width
        height: appGroup.cardHeight + appGroup.stackDepth * appGroup.stackOffsetY

        Behavior on height {
          NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

        Repeater {
          model: appGroup.stackDepth

          StackLayer {
            required property int index
            x: (index + 1) * appGroup.stackOffsetX
            y: (index + 1) * appGroup.stackOffsetY
            width: appGroup.cardWidth
            height: appGroup.cardHeight
            z: index + 1
            record: appGroup.stackedRecord(index)
            layerIndex: index
            groupHovered: appGroup.hovered

            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
          }
        }

        WindowPreview {
          id: mainPreview
          x: 0
          y: 0
          width: appGroup.cardWidth
          height: appGroup.cardHeight
          z: 10
          record: appGroup.currentRecord
          hoveredState: appGroup.hovered
          onHovered: if (appGroup.currentRecord) root.selectedAddress = appGroup.currentRecord.address
          onActivated: if (appGroup.currentRecord) root.activate(appGroup.currentRecord)

          Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }
      }

      // App Icon (Free floating)
      Item {
        id: appIcon
        x: Style.space(2)
        y: previewStack.height - Style.space(10)
        width: Math.max(Style.space(20), Math.min(Style.space(28), appGroup.cardHeight * 0.35))
        height: width
        z: 30

        Image {
          anchors.fill: parent
          source: appGroup.groupData ? appGroup.groupData.icon : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
        }

        Rectangle {
          visible: appGroup.windowCount > 1
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: -Style.space(2)
          anchors.rightMargin: -Style.space(2)
          width: Math.max(Style.space(14), badgeText.implicitWidth + Style.space(5))
          height: Style.space(14)
          radius: height / 2
          color: root.accentColor
          border.width: 1.5
          border.color: root.background
          z: 2

          Text {
            id: badgeText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: appGroup.windowCount
            color: root.background
            font.family: root.fontFamily
            font.pixelSize: Style.space(8)
            font.bold: true
          }
        }
      }

      // Title and window selector bar bounded strictly within thumbnail width
      Item {
        id: metaContainer
        anchors.left: appIcon.right
        anchors.leftMargin: Style.space(5)
        anchors.right: groupBoundingContainer.right
        anchors.rightMargin: Style.space(2)
        y: previewStack.height + Style.space(2)
        height: Style.space(18)

        Text {
          id: appLabel
          anchors.left: parent.left
          anchors.right: windowSelectors.visible ? windowSelectors.left : parent.right
          anchors.rightMargin: windowSelectors.visible ? Style.space(4) : 0
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: {
            if (!appGroup.groupData) return ""
            if (appGroup.hovered && appGroup.currentRecord) {
              return appGroup.currentRecord.title
            }
            if (appGroup.windowCount === 1 && appGroup.currentRecord) {
              return appGroup.groupData.name + "  •  " + appGroup.currentRecord.workspaceName
            }
            return appGroup.groupData.name
          }
          color: root.foreground
          opacity: appGroup.hovered || appGroup.selected ? 0.95 : 0.65
          font.family: root.fontFamily
          font.pixelSize: appGroup.cardHeight < Style.space(60) ? Style.space(9) : Style.font.caption
          font.bold: appGroup.selected || appGroup.hovered
          elide: Text.ElideRight

          Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }

        Row {
          id: windowSelectors
          visible: appGroup.windowCount > 1
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Math.max(Style.space(14), Style.space(16))
          spacing: Style.space(2)
          z: 40

          Repeater {
            model: appGroup.groupData ? appGroup.groupData.windows : []

            Rectangle {
              id: selector
              required property var modelData
              required property int index
              readonly property bool current: index === appGroup.currentIndex

              width: Math.max(height, selectorText.implicitWidth + Style.space(7))
              height: parent.height
              radius: height / 2
              scale: selectorMouse.containsMouse ? 1.06 : 1.0
              color: current
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.90)
                : (selectorMouse.containsMouse
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08))
              border.width: current ? 0 : 1
              border.color: selectorMouse.containsMouse
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

              Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
              Behavior on color { ColorAnimation { duration: 180 } }

              Text {
                id: selectorText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: appGroup.selectorLabel(selector.index)
                color: selector.current ? root.background : root.foreground
                opacity: selector.current ? 1 : 0.72
                font.family: root.fontFamily
                font.pixelSize: Style.space(8)
                font.bold: selector.current
              }

              MouseArea {
                id: selectorMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  root.keyboardNavActive = false
                  appGroup.selectWindow(selector.index)
                }
                onClicked: root.activate(selector.modelData)
              }
            }
          }
        }
      }
    }
  }

  component StackLayer: Item {
    id: stackLayer

    property var record: null
    property int layerIndex: 0
    property bool groupHovered: false
    readonly property real radius: root.cardRadius

    opacity: layerIndex === 0 ? (groupHovered ? 0.95 : 0.88) : (groupHovered ? 0.88 : 0.74)
    Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    Rectangle {
      id: stackMask
      anchors.fill: parent
      radius: stackLayer.radius
      color: "black"
      visible: false
      layer.enabled: true
    }

    Item {
      id: stackVisual
      anchors.fill: parent
      layer.enabled: true
      layer.smooth: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: stackMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.02
      }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.96)
      }

      Image {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.40, parent.height * 0.50)
        height: width
        source: stackLayer.record ? stackLayer.record.icon : ""
        fillMode: Image.PreserveAspectFit
        opacity: stackCapture.hasContent ? 0 : 0.54
        asynchronous: true
        smooth: true
      }

      ScreencopyView {
        id: stackCapture
        captureSource: stackLayer.record ? stackLayer.record.wayland : null
        live: root.opened && stackLayer.visible
        paintCursor: false
        anchors.fill: parent
        opacity: hasContent ? 0.88 : 0

        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, layerIndex === 0 ? 0.12 : 0.22)
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: stackLayer.radius
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.12)
    }

    BorderOverlay {
      anchors.fill: parent
      radius: parent.radius
      borderSpec: Border.withWidth(root.activeWindowBorderSpec, 1)
      opacity: 0.35
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (stackLayer.record) root.activate(stackLayer.record)
    }
  }

  component WindowPreview: Item {
    id: preview

    property var record: null
    property bool hoveredState: false
    readonly property bool isCurrentActive: record && record.active
    readonly property bool selected: record && root.selectedAddress === record.address
    readonly property bool keyboardFocused: root.keyboardNavActive && selected
    readonly property bool captureHasContent: capture.hasContent
    readonly property real sourceWidth: capture.sourceSize.width
    readonly property real sourceHeight: capture.sourceSize.height
    readonly property real radius: root.cardRadius
    signal hovered()
    signal activated()

    Rectangle {
      id: cardMask
      anchors.fill: parent
      radius: preview.radius
      color: "black"
      visible: false
      layer.enabled: true
    }

    Item {
      id: cardVisual
      anchors.fill: parent
      layer.enabled: true
      layer.smooth: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: cardMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.02
      }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.92)
      }

      Image {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.40, parent.height * 0.50)
        height: width
        source: preview.record ? preview.record.icon : ""
        fillMode: Image.PreserveAspectFit
        opacity: capture.hasContent ? 0 : 0.65
        asynchronous: true
        smooth: true
      }

      ScreencopyView {
        id: capture
        captureSource: preview.record ? preview.record.wayland : null
        live: root.opened && preview.visible
        paintCursor: false
        anchors.fill: parent
        opacity: hasContent ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      }

      Rectangle {
        anchors.fill: parent
        color: preview.hoveredState ? Qt.rgba(1, 1, 1, 0.055) : "transparent"
        Behavior on color { ColorAnimation { duration: 180 } }
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: preview.radius
      color: "transparent"
      border.width: 1
      border.color: preview.selected || preview.hoveredState
        ? Qt.rgba(1, 1, 1, 0.22)
        : Qt.rgba(1, 1, 1, 0.10)
      z: 15

      Behavior on border.color { ColorAnimation { duration: 180 } }
    }

    BorderOverlay {
      anchors.fill: parent
      z: 20
      radius: parent.radius
      borderSpec: Border.withWidth(
        root.activeWindowBorderSpec,
        preview.selected ? Style.space(2) : 1
      )
      opacity: preview.keyboardFocused ? 1.0 : (preview.selected ? 0.95 : (preview.hoveredState ? 0.55 : 0.30))

      Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    Rectangle {
      visible: opacity > 0
      anchors.fill: parent
      anchors.margins: -Style.space(2)
      radius: preview.radius + Style.space(2)
      color: "transparent"
      border.width: Style.space(2)
      border.color: root.accentColor
      z: 22
      opacity: preview.keyboardFocused ? 0.85 : 0

      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    MouseArea {
      anchors.fill: parent
      z: 30
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.keyboardNavActive = false
        preview.hovered()
      }
      onClicked: preview.activated()
    }
  }
}
