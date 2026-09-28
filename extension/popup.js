function formatBytes(bytes) {
  if (!bytes || bytes <= 0) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
}

function formatSpeed(bytesPerSec) {
  if (!bytesPerSec || bytesPerSec <= 0) return "0 B/s";
  return formatBytes(bytesPerSec) + "/s";
}

function formatEta(seconds) {
  if (seconds === null || seconds === undefined || seconds < 0) return "--";
  if (seconds < 60) return `${seconds}s`;
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  if (m < 60) return `${m}m ${s}s`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m`;
}

let inSettings = false;

const btnSettings = document.getElementById("btn-settings-toggle");
const viewDownloads = document.getElementById("view-downloads");
const viewSettings = document.getElementById("view-settings");
const headerTitle = document.getElementById("header-title");

btnSettings.addEventListener("click", () => {
  inSettings = !inSettings;
  if (inSettings) {
    viewDownloads.classList.add("hidden");
    viewSettings.classList.remove("hidden");
    btnSettings.classList.add("active");
    headerTitle.textContent = "Stream Settings";
  } else {
    viewSettings.classList.add("hidden");
    viewDownloads.classList.remove("hidden");
    btnSettings.classList.remove("active");
    headerTitle.textContent = "Browser Downloads";
  }
});

function createDownloadCard(dl) {
  const fileName = dl.filename ? dl.filename.split(/[\\/]/).pop() : "File";
  const percent = dl.percent !== null && dl.percent !== undefined ? dl.percent : null;
  const progressWidth = percent !== null ? `${percent}%` : "100%";
  const downloadedBytes = dl.downloaded_bytes ?? dl.bytesReceived ?? 0;
  const totalBytes = dl.total_bytes ?? dl.totalBytes ?? 0;
  const speedBps = dl.speed_bps ?? dl.speed ?? 0;
  const etaSeconds = dl.eta_seconds ?? dl.eta;

  const card = document.createElement("div");
  card.className = "dl-card";

  // Header row
  const header = document.createElement("div");
  header.className = "dl-header";

  const nameSpan = document.createElement("span");
  nameSpan.className = "dl-name";
  nameSpan.title = fileName;
  nameSpan.textContent = fileName;

  const percentSpan = document.createElement("span");
  percentSpan.className = "dl-percent";
  percentSpan.textContent = percent !== null ? `${percent}%` : (dl.state || "downloading");

  header.appendChild(nameSpan);
  header.appendChild(percentSpan);

  // Progress bar
  const barBg = document.createElement("div");
  barBg.className = "progress-bar-bg";

  const barFill = document.createElement("div");
  barFill.className = "progress-bar-fill";
  barFill.style.width = progressWidth;

  barBg.appendChild(barFill);

  // Meta row
  const meta = document.createElement("div");
  meta.className = "dl-meta";

  const sizeSpan = document.createElement("span");
  const totalStr = totalBytes > 0 ? formatBytes(totalBytes) : "?";
  sizeSpan.textContent = `${formatBytes(downloadedBytes)} / ${totalStr}`;

  const speedEtaSpan = document.createElement("span");
  speedEtaSpan.textContent = `${formatSpeed(speedBps)} • ${formatEta(etaSeconds)}`;

  meta.appendChild(sizeSpan);
  meta.appendChild(speedEtaSpan);

  // Assemble
  card.appendChild(header);
  card.appendChild(barBg);
  card.appendChild(meta);

  return card;
}

function updateUI() {
  browser.runtime.sendMessage({ type: "GET_STATUS" }).then((res) => {
    if (!res) return;

    const hostBadge = document.getElementById("host-status");
    const nativeVal = document.getElementById("settings-native-status");

    if (res.nativeConnected) {
      hostBadge.textContent = "Host Active";
      hostBadge.className = "status-badge connected";
      if (nativeVal) {
        nativeVal.textContent = "Active";
        nativeVal.className = "val-badge";
      }
    } else {
      hostBadge.textContent = "Host Idle";
      hostBadge.className = "status-badge disconnected";
      if (nativeVal) {
        nativeVal.textContent = "Disconnected";
        nativeVal.className = "val-badge";
        nativeVal.style.color = "#f38ba8";
      }
    }

    if (inSettings) return;

    const container = document.getElementById("downloads-list");
    while (container.firstChild) {
      container.removeChild(container.firstChild);
    }

    const activeList = res.downloads || [];

    if (activeList.length === 0) {
      const emptyDiv = document.createElement("div");
      emptyDiv.className = "empty-state";
      emptyDiv.textContent = "No active downloads";
      container.appendChild(emptyDiv);
      return;
    }

    for (const dl of activeList) {
      container.appendChild(createDownloadCard(dl));
    }
  }).catch(() => {});
}

updateUI();
setInterval(updateUI, 500);
