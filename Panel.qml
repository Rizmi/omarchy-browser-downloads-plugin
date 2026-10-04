import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.rizmi.browser-downloads"
  ipcTarget: "io.github.rizmi.browser-downloads"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool inSettingsView: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property DownloadManager downloadManager: hostWidget ? hostWidget.downloadManager : null
  readonly property var barIdentity: hostWidget || root

  property int spinTrigger: 0

  function setting(key, fallback) {
    var s = (hostWidget && hostWidget.settings) ? hostWidget.settings : (root.settings || {})
    var val = s[key]
    return val === undefined || val === null ? fallback : val
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    var current = (hostWidget && hostWidget.settings) ? hostWidget.settings : (root.settings || {})
    for (var existing in current) if (existing !== "id") entry[existing] = current[existing]
    for (var k in values) entry[k] = values[k]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    }
  }

  function toggleSetting(key, fallback) {
    var current = setting(key, fallback)
    var upd = {}
    upd[key] = !current
    persistSettings(upd)
  }

  function toggleSettingsView() {
    root.inSettingsView = !root.inSettingsView
  }

  function triggerRefresh() {
    if (downloadManager) downloadManager.refresh()
    root.spinTrigger++
  }

  onOpenedChanged: {
    if (opened) {
      root.inSettingsView = false
      if (downloadManager) downloadManager.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.opened && !root.inSettingsView
    onTriggered: if (downloadManager) downloadManager.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.triggerRefresh(); return "ok" }
    function status(): string { return downloadManager ? downloadManager.summaryText : "" }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: fmInput.activeFocus
      onCloseRequested: {
        if (root.inSettingsView) {
          root.inSettingsView = false
        } else {
          root.close()
        }
      }
      onTextKey: function(t) {
        if (!downloadManager) return
        if (t === "s" || t === "S") {
          root.toggleSettingsView()
        } else if (t === "r" || t === "R") {
          root.triggerRefresh()
        } else if (t === "o" || t === "O") {
          downloadManager.openDownloadsFolder()
          root.close()
        } else if (t === "z" || t === "Z") {
          downloadManager.openBrowserLibrary()
          root.close()
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)

        PanelHero {
          id: hero
          width: parent.width
          title: root.inSettingsView ? "Settings" : "Downlink"
          meta: root.inSettingsView ? "Customize status bar display" : (downloadManager ? downloadManager.summaryText : "Checking status...")
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: downloadManager && downloadManager.isDownloading ? 1.0 : 0.6
          iconComponent: Component {
            Text {
              text: root.inSettingsView ? "\uf013" : "\uf019"
              color: (downloadManager && downloadManager.isDownloading) || root.inSettingsView ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            Row {
              spacing: Style.space(6)

              // Open Folder button (only in downloads view)
              Rectangle {
                visible: !root.inSettingsView
                width: Style.space(28)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: folderMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15) : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: "\uf07c"
                  color: folderMouse.containsMouse ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: folderMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (downloadManager) downloadManager.openDownloadsFolder()
                    root.close()
                  }
                }

                PanelToolTip {
                  visible: folderMouse.containsMouse
                  text: "Open Downloads folder [O]"
                  fontFamily: hero.fontFamily
                }
              }

              // Settings Gear button
              Rectangle {
                width: Style.space(28)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: root.inSettingsView || settingsMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15) : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: "\uf013"
                  color: root.inSettingsView || settingsMouse.containsMouse ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: settingsMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleSettingsView()
                }

                PanelToolTip {
                  visible: settingsMouse.containsMouse
                  text: root.inSettingsView ? "Back to Downloads [S]" : "Widget Settings [S]"
                  fontFamily: hero.fontFamily
                }
              }

              // Refresh button (only in downloads view)
              Rectangle {
                visible: !root.inSettingsView
                width: Style.space(28)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: refreshMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15) : "transparent"

                Text {
                  id: refreshIcon
                  anchors.centerIn: parent
                  text: "\udb81\udc50"
                  color: refreshMouse.containsMouse ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body

                  NumberAnimation {
                    id: spinAnimation
                    target: refreshIcon
                    property: "rotation"
                    from: 0
                    to: 360
                    duration: 500
                    easing.type: Easing.OutCubic
                  }

                  Connections {
                    target: root
                    function onSpinTriggerChanged() { spinAnimation.restart() }
                  }
                }

                MouseArea {
                  id: refreshMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.triggerRefresh()
                }

                PanelToolTip {
                  visible: refreshMouse.containsMouse
                  text: "Refresh status [R]"
                  fontFamily: hero.fontFamily
                }
              }
            }
          }
        }

        // ================= SETTINGS VIEW =================
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.inSettingsView

          PanelSectionHeader {
            width: parent.width
            text: "STATUS BAR DISPLAY"
            foreground: root.foreground
          }

          Toggle {
            width: parent.width
            label: "Hide When Idle"
            description: "Only show widget on bar when downloading"
            checked: root.setting("hideWhenIdle", false)
            foreground: root.foreground
            accent: bar && bar.urgent ? bar.urgent : Color.accent
            onClicked: root.toggleSetting("hideWhenIdle", false)
          }

          Toggle {
            width: parent.width
            label: "Show Download Speed"
            description: "Display transfer speed (e.g. 1.5 MB/s) on bar"
            checked: root.setting("showSpeed", true)
            foreground: root.foreground
            accent: bar && bar.urgent ? bar.urgent : Color.accent
            onClicked: root.toggleSetting("showSpeed", true)
          }

          Toggle {
            width: parent.width
            label: "Show Percentage"
            description: "Display progress percentage (e.g. 45%) on bar"
            checked: root.setting("showPercent", true)
            foreground: root.foreground
            accent: bar && bar.urgent ? bar.urgent : Color.accent
            onClicked: root.toggleSetting("showPercent", true)
          }

          PanelSectionHeader {
            width: parent.width
            text: "FILE MANAGER COMMAND"
            foreground: root.foreground
          }

          Rectangle {
            width: parent.width
            implicitHeight: fmCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
            border.color: fmInput.activeFocus ? (bar && bar.urgent ? bar.urgent : Color.accent) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
            border.width: 1

            Column {
              id: fmCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(6)

              Text {
                text: "Command to open folders"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: root.dim
              }

              TextField {
                id: fmInput
                width: parent.width
                text: root.setting("fileManagerCommand", "nautilus")
                placeholderText: "nautilus"
                foreground: root.foreground
                accent: bar && bar.urgent ? bar.urgent : Color.accent
                onEditingFinished: {
                  var cmd = text.trim() || "nautilus"
                  root.persistSettings({ fileManagerCommand: cmd })
                }
              }
            }
          }
        }

        // ================= DOWNLOADS VIEW =================
        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: !root.inSettingsView

          PanelSectionHeader {
            width: parent.width
            text: "ACTIVE TRANSFERS"
            foreground: root.foreground
          }

          // Empty state
          Item {
            width: parent.width
            implicitHeight: Style.space(110)
            height: implicitHeight
            visible: !downloadManager || downloadManager.downloads.length === 0

            Column {
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\uf019"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.space(24)
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No active downloads"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Downloads from your browser will show here"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // Active downloads list
          Flickable {
            id: dlFlick
            width: parent.width
            implicitHeight: Math.min(dlListCol.implicitHeight, Style.space(280))
            height: implicitHeight
            contentWidth: width
            contentHeight: dlListCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            visible: downloadManager && downloadManager.downloads.length > 0

            Column {
              id: dlListCol
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: downloadManager ? downloadManager.downloads : []

                delegate: Rectangle {
                  id: card
                  width: dlListCol.width
                  implicitHeight: cardContent.implicitHeight + Style.space(16)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                  border.width: 1

                  Column {
                    id: cardContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Style.space(8)
                    spacing: Style.space(6)

                    // Header: File name and percentage/state
                    RowLayout {
                      width: parent.width

                      Text {
                        text: "\uf15b"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        color: modelData.state === "complete" ? "#a6e3a1" : root.foreground
                      }

                      Text {
                        Layout.fillWidth: true
                        text: modelData.filename || "download"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        color: root.foreground
                        elide: Text.ElideMiddle
                      }

                      Text {
                        text: modelData.state === "complete"
                          ? "Done"
                          : (modelData.paused
                             ? "Paused"
                             : (modelData.percent !== null && modelData.percent !== undefined
                                ? (modelData.percent + "%")
                                : "Downloading"))
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        color: modelData.state === "complete"
                          ? "#a6e3a1"
                          : (modelData.paused ? "#f9e2af" : root.foreground)
                      }

                      // Action buttons: 2 slots
                      // Slot 1: Pause/Resume (when active) OR Open Folder (when complete)
                      // Slot 2: Cancel (when active) OR Clear/Dismiss (when complete)
                      Row {
                        spacing: Style.space(4)

                        // Button 1: Pause/Resume OR Open File Location
                        Rectangle {
                          width: Style.space(20)
                          height: Style.space(20)
                          radius: Style.space(4)
                          color: b1Mouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15) : "transparent"

                          Text {
                            anchors.centerIn: parent
                            text: modelData.state === "complete"
                              ? "\uf07c"
                              : (modelData.paused ? "\uf04b" : "\uf04c")
                            font.family: root.fontFamily
                            font.pixelSize: Style.space(10)
                            color: root.foreground
                          }

                          MouseArea {
                            id: b1Mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              if (!downloadManager) return
                              if (modelData.state === "complete") {
                                downloadManager.openFileLocation(modelData.full_path)
                              } else if (modelData.paused) {
                                downloadManager.resumeDownload(modelData.id)
                              } else {
                                downloadManager.pauseDownload(modelData.id)
                              }
                            }
                          }

                          PanelToolTip {
                            visible: b1Mouse.containsMouse
                            text: modelData.state === "complete"
                              ? "Open file location"
                              : (modelData.paused ? "Resume download" : "Pause download")
                            fontFamily: root.fontFamily
                          }
                        }

                        // Button 2: Cancel OR Clear / Dismiss
                        Rectangle {
                          width: Style.space(20)
                          height: Style.space(20)
                          radius: Style.space(4)
                          color: b2Mouse.containsMouse
                            ? (modelData.state === "complete" ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15) : Qt.rgba(1.0, 0.3, 0.3, 0.2))
                            : "transparent"

                          Text {
                            anchors.centerIn: parent
                            text: "\uf00d"
                            font.family: root.fontFamily
                            font.pixelSize: Style.space(10)
                            color: b2Mouse.containsMouse
                              ? (modelData.state === "complete" ? root.foreground : (bar && bar.urgent ? bar.urgent : "#f38ba8"))
                              : root.dim
                          }

                          MouseArea {
                            id: b2Mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              if (!downloadManager) return
                              if (modelData.state === "complete") {
                                downloadManager.dismissDownload(modelData.id)
                              } else {
                                downloadManager.cancelDownload(modelData.id)
                              }
                            }
                          }

                          PanelToolTip {
                            visible: b2Mouse.containsMouse
                            text: modelData.state === "complete" ? "Clear from list" : "Cancel download"
                            fontFamily: root.fontFamily
                          }
                        }
                      }
                    }

                    // Progress Bar
                    Rectangle {
                      width: parent.width
                      height: Style.space(6)
                      radius: Style.space(3)
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                      clip: true

                      Rectangle {
                        height: parent.height
                        radius: Style.space(3)
                        width: {
                          if (modelData.state === "complete") return parent.width
                          if (modelData.percent !== null && modelData.percent !== undefined) {
                            return Math.max(parent.height, (Math.min(100, modelData.percent) / 100) * parent.width)
                          }
                          return parent.width
                        }
                        color: modelData.state === "complete"
                          ? "#a6e3a1"
                          : (modelData.paused ? root.urgent : (bar && bar.urgent ? bar.urgent : "#89b4fa"))

                        Behavior on width {
                          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                      }
                    }

                    // Progress details row
                    RowLayout {
                      width: parent.width

                      Text {
                        Layout.fillWidth: true
                        text: {
                          var dlStr = downloadManager ? downloadManager.formatBytes(modelData.downloaded_bytes) : ""
                          var totStr = (modelData.total_bytes && downloadManager) ? downloadManager.formatBytes(modelData.total_bytes) : "?"
                          var leftStr = (modelData.bytes_left !== null && modelData.bytes_left !== undefined && downloadManager)
                            ? " (" + downloadManager.formatBytes(modelData.bytes_left) + " left)"
                            : ""
                          return dlStr + " / " + totStr + leftStr
                        }
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        color: root.dim
                        elide: Text.ElideRight
                      }

                      Text {
                        text: {
                          if (modelData.state === "complete") return "Completed"
                          if (modelData.paused) return "Paused"
                          var spd = downloadManager ? downloadManager.formatSpeed(modelData.speed_bps) : ""
                          var eta = downloadManager ? downloadManager.formatEta(modelData.eta_seconds) : ""
                          return spd + " • ETA: " + eta
                        }
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        color: root.dim
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
