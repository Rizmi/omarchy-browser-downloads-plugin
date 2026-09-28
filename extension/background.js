const NATIVE_HOST = "browser_download_streamer";
let nativePort = null;
let isNativeConnected = false;
let reconnectTimer = null;

// Download ID -> { lastBytes, lastTime, speed }
const downloadStats = new Map();
let pollInterval = null;
let cachedDownloads = [];
let emptyPollCount = 0;

function connectNative() {
  if (nativePort) return;

  try {
    console.log("[Streamer] Connecting to native host:", NATIVE_HOST);
    nativePort = browser.runtime.connectNative(NATIVE_HOST);

    nativePort.onMessage.addListener(async (msg) => {
      if (!msg || !msg.action || !msg.id) return;
      const id = Number(msg.id);
      try {
        if (msg.action === "cancel") {
          console.log("[Streamer] Cancelling download:", id);
          await browser.downloads.cancel(id);
        } else if (msg.action === "pause") {
          console.log("[Streamer] Pausing download:", id);
          await browser.downloads.pause(id);
        } else if (msg.action === "resume") {
          console.log("[Streamer] Resuming download:", id);
          await browser.downloads.resume(id);
        }
        await updateActiveDownloads();
      } catch (err) {
        console.warn("[Streamer] Command error:", msg.action, err);
      }
    });

    nativePort.onDisconnect.addListener(() => {
      const err = browser.runtime.lastError;
      console.warn("[Streamer] Native port disconnected:", err ? err.message : "normal disconnect");
      nativePort = null;
      isNativeConnected = false;
      if (downloadStats.size > 0 && !reconnectTimer) {
        reconnectTimer = setTimeout(() => {
          reconnectTimer = null;
          connectNative();
        }, 3000);
      }
    });

    isNativeConnected = true;
    console.log("[Streamer] Connected to native host successfully.");
  } catch (err) {
    console.error("[Streamer] Error connecting to native host:", err);
    nativePort = null;
    isNativeConnected = false;
  }
}

function sendToNative(payload) {
  connectNative();
  if (nativePort && isNativeConnected) {
    try {
      nativePort.postMessage(payload);
    } catch (err) {
      console.error("[Streamer] Failed to postMessage:", err);
      nativePort = null;
      isNativeConnected = false;
    }
  }
}

let isPolling = false;

async function updateActiveDownloads() {
  if (isPolling) return;
  isPolling = true;

  try {
    const allItems = await browser.downloads.search({
      limit: 20,
      orderBy: ["-startTime"]
    });

    const now = Date.now();
    // Keep in-progress and paused downloads
    const activeItems = (allItems || []).filter(item => {
      if (item.state === "in_progress") return true;
      if (item.paused) return true;
      if (item.state === "interrupted" && item.canResume) return true;
      return false;
    });

    if (activeItems.length === 0) {
      emptyPollCount++;
      if (emptyPollCount >= 4) {
        stopPolling();
      }
      if (cachedDownloads.length > 0) {
        cachedDownloads = [];
        sendToNative({
          timestamp: now,
          active_count: 0,
          paused_count: 0,
          downloads: []
        });
      }
      return;
    }

    emptyPollCount = 0;
    const currentList = [];

    for (const item of activeItems) {
      const isPaused = item.paused || (item.state === "interrupted" && item.canResume);
      let stats = downloadStats.get(item.id);

      if (!stats) {
        stats = {
          lastBytes: item.bytesReceived,
          lastTime: now,
          speed: 0
        };
        downloadStats.set(item.id, stats);
      } else if (!isPaused) {
        const timeDelta = (now - stats.lastTime) / 1000;
        if (timeDelta >= 0.3) {
          const bytesDelta = item.bytesReceived - stats.lastBytes;
          const instantSpeed = Math.max(0, bytesDelta / timeDelta);
          stats.speed = stats.speed === 0 ? instantSpeed : Math.round(0.6 * stats.speed + 0.4 * instantSpeed);
          stats.lastBytes = item.bytesReceived;
          stats.lastTime = now;
        }
      } else {
        stats.speed = 0;
      }

      // Calculate ETA
      let eta = null;
      if (!isPaused) {
        if (item.estimatedEndTime) {
          const diffMs = new Date(item.estimatedEndTime).getTime() - now;
          eta = diffMs > 0 ? Math.round(diffMs / 1000) : 0;
        } else if (item.totalBytes > 0 && stats.speed > 0) {
          const remaining = Math.max(0, item.totalBytes - item.bytesReceived);
          eta = Math.round(remaining / stats.speed);
        }
      }

      // Calculate percent and bytes left
      let percent = null;
      let bytesLeft = null;
      if (item.totalBytes && item.totalBytes > 0) {
        percent = Math.min(100, Number(((item.bytesReceived / item.totalBytes) * 100).toFixed(1)));
        bytesLeft = Math.max(0, item.totalBytes - item.bytesReceived);
      }

      currentList.push({
        id: item.id,
        filename: item.filename ? item.filename.split(/[\\/]/).pop() : "download",
        full_path: item.filename || "",
        downloaded_bytes: item.bytesReceived,
        total_bytes: item.totalBytes > 0 ? item.totalBytes : null,
        bytes_left: bytesLeft,
        percent: percent,
        speed_bps: isPaused ? 0 : stats.speed,
        eta_seconds: eta,
        state: isPaused ? "paused" : item.state,
        paused: isPaused
      });
    }

    cachedDownloads = currentList;

    // Send payload to native host
    sendToNative({
      timestamp: now,
      active_count: currentList.filter(d => !d.paused).length,
      paused_count: currentList.filter(d => d.paused).length,
      downloads: currentList
    });

    // Cleanup finished stats
    const activeIds = new Set(activeItems.map(i => i.id));
    for (const id of downloadStats.keys()) {
      if (!activeIds.has(id)) {
        downloadStats.delete(id);
      }
    }
  } catch (err) {
    console.error("[Streamer] Download poll error:", err);
  } finally {
    isPolling = false;
  }
}

function startPolling() {
  emptyPollCount = 0;
  if (pollInterval) return;
  updateActiveDownloads();
  pollInterval = setInterval(updateActiveDownloads, 250);
}

function stopPolling() {
  if (pollInterval) {
    clearInterval(pollInterval);
    pollInterval = null;
  }
}

// Download event listeners
browser.downloads.onCreated.addListener((item) => {
  console.log("[Streamer] Download created:", item.id, item.filename);
  startPolling();
});

browser.downloads.onChanged.addListener(async (delta) => {
  if (delta.state) {
    const state = delta.state.current;
    console.log("[Streamer] Download state changed:", delta.id, state);
    if (state === "complete") {
      try {
        const [item] = await browser.downloads.search({ id: delta.id });
        if (item) {
          const completedItem = {
            id: item.id,
            filename: item.filename ? item.filename.split(/[\\/]/).pop() : "download",
            full_path: item.filename || "",
            downloaded_bytes: item.totalBytes > 0 ? item.totalBytes : item.bytesReceived,
            total_bytes: item.totalBytes > 0 ? item.totalBytes : item.bytesReceived,
            bytes_left: 0,
            percent: 100,
            speed_bps: 0,
            eta_seconds: 0,
            state: "complete",
            paused: false
          };

          sendToNative({
            timestamp: Date.now(),
            active_count: 0,
            paused_count: 0,
            downloads: [completedItem]
          });

          setTimeout(() => {
            updateActiveDownloads();
          }, 3000);
        }
      } catch (e) {}
    } else {
      startPolling();
    }
  } else {
    startPolling();
  }
});

// Check on launch for active downloads
connectNative();
browser.downloads.search({}).then((items) => {
  const hasActive = (items || []).some(d => d.state === "in_progress" || d.paused || (d.state === "interrupted" && d.canResume));
  if (hasActive) {
    startPolling();
  }
});

// Support popup UI
browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.type === "GET_STATUS") {
    connectNative();
    sendResponse({
      nativeConnected: isNativeConnected,
      downloads: cachedDownloads
    });
  }
  return true;
});
