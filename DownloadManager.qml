import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property bool showSpeed: setting("showSpeed", true)
  readonly property bool showPercent: setting("showPercent", true)
  readonly property string downloadsFolder: {
    var d = String(setting("downloadsFolder", "") || "").trim()
    if (d && d !== "") return d
    var home = Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")
    return home + "/Downloads"
  }
  readonly property string fileManagerCommand: setting("fileManagerCommand", "nautilus")

  property var downloads: []
  property var activeDownloads: []
  property var completedMap: ({})
  property var dismissedIds: ({})
  readonly property bool hasCompleted: Object.keys(completedMap).length > 0

  property int activeCount: 0
  property int pausedCount: 0
  property bool isDownloading: (activeCount > 0 || pausedCount > 0)
  property int totalSpeed: 0

  property string summaryText: "No active downloads"
  property string barText: ""
  property string barTooltip: "Browser Downloads: Idle"

  function formatBytes(bytes) {
    var b = Number(bytes)
    if (!isFinite(b) || b <= 0) return "0 B"
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = Math.floor(Math.log(b) / Math.log(1024))
    if (i >= units.length) i = units.length - 1
    return (b / Math.pow(1024, i)).toFixed(1) + " " + units[i]
  }

  function formatSpeed(bps) {
    var speed = Number(bps)
    if (!isFinite(speed) || speed <= 0) return "0 B/s"
    return formatBytes(speed) + "/s"
  }

  function formatEta(seconds) {
    var s = Number(seconds)
    if (!isFinite(s) || s < 0) return "--"
    if (s < 60) return Math.round(s) + "s"
    var m = Math.floor(s / 60)
    var remS = Math.round(s % 60)
    if (m < 60) return m + "m " + remS + "s"
    var h = Math.floor(m / 60)
    var remM = Math.round(m % 60)
    return h + "h " + remM + "m"
  }

  function dismissDownload(id) {
    var copy = Object.assign({}, root.completedMap)
    delete copy[id]
    root.completedMap = copy

    var dis = Object.assign({}, root.dismissedIds)
    dis[id] = true
    root.dismissedIds = dis

    var compList = []
    for (var k in copy) {
      compList.push(copy[k])
    }
    root.downloads = root.activeDownloads.concat(compList)
    root.updateDerivedStrings()
  }

  function loadRawData(raw) {
    try {
      if (!raw || String(raw).trim() === "") {
        root.updateDerivedStrings()
        return
      }

      var data = JSON.parse(raw)
      var incoming = data.downloads || []

      var activeList = []
      var compMap = Object.assign({}, root.completedMap)

      for (var i = 0; i < incoming.length; i++) {
        var d = incoming[i]
        if (root.dismissedIds[d.id]) {
          continue
        }

        if (d.state === "complete") {
          compMap[d.id] = d
        } else if (d.state === "in_progress" || d.state === "paused" || d.paused) {
          activeList.push(d)
        }
      }

      root.completedMap = compMap
      root.activeDownloads = activeList

      var compList = []
      for (var k in compMap) {
        compList.push(compMap[k])
      }

      // Combine: active/paused downloads first, then completed downloads
      root.downloads = activeList.concat(compList)

      var active = 0
      var paused = 0
      var speedSum = 0

      for (var j = 0; j < activeList.length; j++) {
        var it = activeList[j]
        if (it.paused || it.state === "paused") {
          paused++
        } else {
          active++
          speedSum += (it.speed_bps || 0)
        }
      }

      root.activeCount = active
      root.pausedCount = paused
      root.totalSpeed = speedSum
      root.isDownloading = (active > 0 || paused > 0)

      root.updateDerivedStrings()
    } catch (e) {
      // Ignored
    }
  }

  function updateDerivedStrings() {
    var compCount = Object.keys(root.completedMap).length

    if (root.activeCount === 0 && root.pausedCount === 0) {
      if (compCount > 0) {
        root.barText = compCount === 1 ? "1 Complete" : compCount + " Complete"
        root.summaryText = compCount === 1 ? "1 completed download" : compCount + " completed downloads"
        root.barTooltip = "Browser Downloads: " + compCount + " completed"
      } else {
        root.barText = ""
        root.summaryText = "No active downloads"
        root.barTooltip = "Browser Downloads: Idle\nRight-click to open Downloads folder"
      }
      return
    }

    if (root.activeCount === 0 && root.pausedCount > 0) {
      var pItem = root.activeDownloads[0]
      var pct = pItem && pItem.percent !== null ? Math.round(pItem.percent) + "%" : ""
      root.barText = "Paused" + (pct ? " (" + pct + ")" : "")
      root.summaryText = (pItem ? pItem.filename : "Download") + ": Paused"
      root.barTooltip = (pItem ? pItem.filename : "Download") + " [PAUSED]"
      return
    }

    if (root.activeCount === 1) {
      var item = root.activeDownloads.find(function(d) { return !d.paused && d.state === "in_progress" }) || root.activeDownloads[0]
      var pctStr = item.percent !== null && item.percent !== undefined ? (Math.round(item.percent) + "%") : ""
      var spdStr = root.formatSpeed(item.speed_bps)

      if (root.showPercent && root.showSpeed && pctStr !== "") {
        root.barText = pctStr + " " + spdStr
      } else if (root.showPercent && pctStr !== "") {
        root.barText = pctStr
      } else if (root.showSpeed) {
        root.barText = spdStr
      } else {
        root.barText = "Downloading"
      }

      var leftStr = item.bytes_left !== null && item.bytes_left !== undefined
        ? " (" + root.formatBytes(item.bytes_left) + " left)"
        : ""
      root.summaryText = "1 active download: " + item.filename
      root.barTooltip = item.filename + "\n" +
        root.formatBytes(item.downloaded_bytes) + " of " +
        (item.total_bytes ? root.formatBytes(item.total_bytes) : "?") + leftStr + "\n" +
        "Speed: " + spdStr + " • ETA: " + root.formatEta(item.eta_seconds)
    } else {
      root.barText = root.activeCount + " DL (" + root.formatSpeed(root.totalSpeed) + ")"
      root.summaryText = root.activeCount + " downloads in progress (" + root.formatSpeed(root.totalSpeed) + ")"

      var lines = [root.activeCount + " active downloads:"]
      for (var j = 0; j < root.activeDownloads.length; j++) {
        var it = root.activeDownloads[j]
        var status = it.paused ? "paused" : (root.formatSpeed(it.speed_bps))
        lines.push("• " + it.filename + ": " + (it.percent !== null ? it.percent + "%" : "") + " (" + status + ")")
      }
      root.barTooltip = lines.join("\n")
    }
  }

  function sendCommand(action, id) {
    var cmdScript = String(Qt.resolvedUrl("send-cmd.sh")).replace(/^file:\/\//, "")
    Quickshell.execDetached([
      "bash", "-lc",
      'exec bash "$1" "$2" "$3"',
      "bash",
      cmdScript,
      action,
      String(id)
    ])
  }

  function cancelDownload(id) { sendCommand("cancel", id) }
  function pauseDownload(id) { sendCommand("pause", id) }
  function resumeDownload(id) { sendCommand("resume", id) }

  function openFileLocation(filePath) {
    var scriptPath = String(Qt.resolvedUrl("open-folder.sh")).replace(/^file:\/\//, "")
    Quickshell.execDetached([
      "bash", "-lc",
      'exec bash "$1" "$2" "$3"',
      "bash",
      scriptPath,
      filePath || root.downloadsFolder,
      root.fileManagerCommand
    ])
  }

  function openDownloadsFolder() {
    openFileLocation(root.downloadsFolder)
  }

  function openBrowserLibrary() {
    Quickshell.execDetached([
      "bash", "-lc",
      'zen-browser about:downloads 2>/dev/null || firefox -P about:downloads 2>/dev/null || exec xdg-open "$1"',
      "bash",
      root.downloadsFolder
    ])
  }

  function refresh() {
    dataFile.reload()
    fallbackFile.reload()
  }

  // Periodic watch poll
  Timer {
    id: pollTimer
    interval: root.isDownloading ? 500 : 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  FileView {
    id: dataFile
    path: "/tmp/browser-downloads.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadRawData(text())
    onLoadFailed: fallbackFile.reload()
    onFileChanged: reload()
  }

  FileView {
    id: fallbackFile
    path: "/tmp/zen-downloads.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadRawData(text())
    onLoadFailed: root.loadRawData("{}")
    onFileChanged: reload()
  }
}
