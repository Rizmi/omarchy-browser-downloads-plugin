import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.rizmi.browser-downloads"

  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property bool hideWhenIdle: setting("hideWhenIdle", false)
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color activeColor: barForeground
  readonly property color dimColor: Qt.darker(barForeground, 1.55)

  readonly property DownloadManager downloadManager: dlManager

  DownloadManager {
    id: dlManager
    settings: root.settings
  }

  // Panel plumbing
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.opened
    useActiveColor: false

    visible: !root.hideWhenIdle || dlManager.isDownloading || dlManager.hasCompleted || root.opened

    text: dlManager.isDownloading
      ? ("\uf019 " + dlManager.barText)
      : "\uf019"

    foreground: dlManager.isDownloading
      ? root.activeColor
      : (dlManager.hasCompleted ? "#a6e3a1" : root.dimColor)

    tooltipText: dlManager.barTooltip

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        dlManager.openDownloadsFolder()
      } else {
        root.toggle()
      }
    }
  }
}
