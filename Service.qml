import QtQuick
import Quickshell
import Quickshell.Io
import "Schedule.js" as Schedule

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/omarchy/auto-wallpaper"
  readonly property string configPath: configDir + "/config.json"
  readonly property string themeNamePath: home + "/.local/state/omarchy/current/theme.name"
  readonly property string currentBgLink: home + "/.local/state/omarchy/current/background"
  readonly property string catalogScriptPath: decodeURIComponent(
    String(Qt.resolvedUrl("WallpaperCatalog.sh")).replace(/^file:\/\//, ""))

  // Watched config (mirrors Schedule.DEFAULTS). Core defaults are literal so
  // fresh installs work even if a theme event arrives before config loading.
  property bool loaded: false
  property bool enabled: true
  property string scheduleType: Schedule.DEFAULTS.scheduleType
  property int intervalMinutes: 30
  property string mode: Schedule.DEFAULTS.mode
  property int lastChangeEpoch: Schedule.DEFAULTS.lastChangeEpoch
  property var cycle: []
  property int cycleIndex: 0
  property string cycleTheme: ""
  property var dailyEntries: []
  property string lastHandledBoundary: ""

  // Live theme + wallpaper state.
  property string currentTheme: ""
  property string currentThemeDisplay: "Unknown"
  property var catalogPaths: []
  property var wallpaperList: []
  property string currentWallpaper: ""
  property int nowEpoch: 0
  property bool catalogReady: false
  property bool currentReady: false

  // Action state.
  property bool busy: false
  property string pendingWallpaper: ""
  property var pendingNext: null
  property string pendingBoundaryToken: ""
  property string pendingScheduleType: ""
  property string lastError: ""
  property string lastAction: ""

  readonly property bool shuffle: root.mode === Schedule.MODE_SHUFFLE

  function currentConfig() {
    return {
      enabled: root.enabled,
      scheduleType: root.scheduleType,
      intervalMinutes: root.intervalMinutes,
      mode: root.mode,
      lastChangeEpoch: root.lastChangeEpoch,
      cycle: root.cycle,
      cycleIndex: root.cycleIndex,
      cycleTheme: root.cycleTheme,
      dailyEntries: root.dailyEntries,
      lastHandledBoundary: root.lastHandledBoundary
    }
  }

  // Public-facing state for the panel and bar.
  function currentWallpaperDisplay() {
    return Schedule.wallpaperName(root.currentWallpaper)
  }

  function applyConfig(text) {
    var parsed = {}
    try { parsed = text && text.trim() ? JSON.parse(text) : {} }
    catch (error) { root.lastError = "Invalid config.json: " + error }
    var config = Schedule.normalize(parsed)
    // A brand-new config has lastChangeEpoch 0; without this, the very first
    // load would be "due" immediately and switch the wallpaper right after
    // install. Start the clock now so the first change waits one full interval.
    if (config.enabled && config.scheduleType === Schedule.SCHEDULE_INTERVAL
        && config.lastChangeEpoch <= 0) config.lastChangeEpoch = Date.now()
    root.enabled = config.enabled
    root.scheduleType = config.scheduleType
    root.intervalMinutes = config.intervalMinutes
    root.mode = config.mode
    root.lastChangeEpoch = config.lastChangeEpoch
    root.cycle = config.cycle
    root.cycleIndex = config.cycleIndex
    root.cycleTheme = config.cycleTheme
    root.dailyEntries = config.dailyEntries
    root.lastHandledBoundary = config.lastHandledBoundary
    root.loaded = true
    root.nowEpoch = Date.now()
    Qt.callLater(root.reconcile)
  }

  function saveConfig(patch) {
    var config = root.currentConfig()
    for (var key in patch) config[key] = patch[key]
    config = Schedule.normalize(config)
    var text = JSON.stringify(config, null, 2) + "\n"
    configFile.setText(text)
    root.applyConfig(text)
  }

  function setEnabled(value) {
    var on = value === true
    var patch = { enabled: on }
    if (on && root.scheduleType === Schedule.SCHEDULE_DAILY)
      patch.lastHandledBoundary = ""
    root.saveConfig(patch)
    if (on) Qt.callLater(root.applyNow)
    else root.lastAction = "Automatic switching disabled"
  }

  function updateSchedule(patch) {
    var next = {}
    for (var key in patch) next[key] = patch[key]
    var targetType = "scheduleType" in patch
      ? Schedule.scheduleType(patch.scheduleType) : root.scheduleType
    if (targetType === Schedule.SCHEDULE_DAILY
        && (targetType !== root.scheduleType
          || "dailyEntries" in patch))
      next.lastHandledBoundary = ""
    if (targetType === Schedule.SCHEDULE_INTERVAL && targetType !== root.scheduleType)
      next.lastChangeEpoch = Date.now()
    root.saveConfig(next)
    root.lastAction = "Schedule saved"
    root.lastError = ""
    Qt.callLater(root.reconcile)
  }

  function saveDailyEntry(index, time, wallpaper) {
    var at = Schedule.minute(time, -1)
    var path = Schedule.wallpaperPath(wallpaper)
    if (at < 0) {
      root.lastError = "Enter a valid hour and minute."
      return false
    }
    if (!path) {
      root.lastError = "Choose a wallpaper for this time."
      return false
    }
    if (root.catalogPaths.indexOf(path) < 0) {
      root.lastError = "Choose a wallpaper from the active theme."
      return false
    }

    var targetIndex = Schedule.integer(index, -1)
    var entries = root.dailyEntries.slice()
    for (var i = 0; i < entries.length; i++) {
      if (i !== targetIndex && entries[i].time === at) {
        root.lastError = "A schedule already exists at " + Schedule.clockLabel(at) + "."
        return false
      }
    }

    var entry = { time: at, wallpaper: path }
    if (targetIndex >= 0 && targetIndex < entries.length) entries[targetIndex] = entry
    else entries.push(entry)
    root.updateSchedule({ dailyEntries: entries })
    root.lastAction = "Schedule time saved"
    return true
  }

  function removeDailyEntry(index) {
    var targetIndex = Schedule.integer(index, -1)
    if (targetIndex < 0 || targetIndex >= root.dailyEntries.length) return
    var entries = root.dailyEntries.slice()
    entries.splice(targetIndex, 1)
    root.updateSchedule({ dailyEntries: entries })
    root.lastAction = "Schedule time removed"
  }

  // Cheap vs. expensive listing. The default path only reads wallpaper
  // paths/thumbnails from disk (needed for scheduling) and performs no cache
  // generation. Thumbnail generation (vips) is deferred until the panel is
  // actually opened so an idle/closed plugin spends ~no resources.
  function refreshCatalog(ensureThumbs) {
    if (ensureThumbs === true) {
      if (!cacheProc.running) cacheProc.running = true
      return
    }
    if (!catalogProc.running) catalogProc.running = true
  }

  function updateCurrent() {
    if (!currentProc.running) currentProc.running = true
  }

  function peekNext() {
    if (!root.enabled) return ""
    var result = Schedule.pickNext(root.currentConfig(), root.catalogPaths,
                                    root.currentWallpaper, root.currentTheme, Math.random)
    return result.path
  }

  function nextText() {
    if (!root.enabled) return "Automatic switching is off"
    if (root.scheduleType === Schedule.SCHEDULE_DAILY)
      return Schedule.nextSwitchText(new Date(root.nowEpoch || Date.now()), root.currentConfig())
    var target = root.peekNext()
    if (!target) return "No other wallpaper to show"
    var minutes = Schedule.minutesUntil(root.currentConfig(), root.nowEpoch)
    var prefix = minutes > 0 ? minutes + " min" : "now"
    return "Next in " + prefix + " · " + Schedule.wallpaperName(target)
  }

  function statusText() {
    return "Theme: " + root.currentThemeDisplay
      + " · " + root.catalogPaths.length + " wallpaper"
      + (root.catalogPaths.length === 1 ? "" : "s") + " · "
      + (root.scheduleType === Schedule.SCHEDULE_DAILY
          ? "Daily times" : Schedule.modeLabel(root.mode))
  }

  function applyNow() {
    if (root.scheduleType === Schedule.SCHEDULE_DAILY) root.applyDaily(true)
    else root.applyNext()
  }

  function applyNext() {
    if (root.busy) return
    var result = Schedule.pickNext(root.currentConfig(), root.catalogPaths,
                                    root.currentWallpaper, root.currentTheme, Math.random)
    if (result.changed && result.path) {
      root.pendingWallpaper = result.path
      root.switchTo(result.path, result)
    } else {
      root.lastAction = root.catalogPaths.length > 0
        ? "Already showing the only wallpaper" : "No wallpapers for this theme"
      root.saveConfig({ lastChangeEpoch: Date.now() })
    }
  }

  function setWallpaper(path) {
    if (root.busy || !path) return
    var token = root.scheduleType === Schedule.SCHEDULE_DAILY
      ? Schedule.boundaryToken(new Date(), root.currentConfig()) : ""
    root.switchTo(path, null, token)
  }

  function applyDaily(force) {
    if (root.busy || !root.catalogReady || !root.currentReady) return
    var now = new Date(root.nowEpoch || Date.now())
    var config = root.currentConfig()
    var target = Schedule.desiredWallpaper(now, config)
    if (!target) {
      root.lastAction = "Add at least one daily schedule time"
      root.lastError = ""
      return
    }
    var token = Schedule.boundaryToken(now, config)
    if (!force && token === config.lastHandledBoundary) return
    if (root.catalogPaths.indexOf(target) < 0) {
      root.lastError = "The scheduled wallpaper is not available in "
        + root.currentThemeDisplay + ". Choose another wallpaper."
      return
    }
    if (target === root.currentWallpaper) {
      root.saveConfig({ lastHandledBoundary: token })
      root.lastAction = "Scheduled wallpaper already active"
      root.lastError = ""
      return
    }
    root.switchTo(target, null, token)
  }

  function switchTo(path, nextResult, boundaryToken) {
    var target = String(path || "").trim()
    if (!target) {
      root.lastError = "No wallpaper selected."
      return
    }
    root.pendingWallpaper = target
    root.pendingNext = nextResult
    root.pendingBoundaryToken = boundaryToken || ""
    root.pendingScheduleType = root.scheduleType
    root.lastError = ""
    setProc.command = ["omarchy-theme-bg-set", target]
    root.busy = true
    setProc.running = true
  }

  function reconcile() {
    if (!root.loaded || root.busy) return
    root.nowEpoch = Date.now()
    if (!root.enabled) return
    if (root.scheduleType === Schedule.SCHEDULE_DAILY) root.applyDaily(false)
    else if (Schedule.isDue(root.currentConfig(), root.nowEpoch)) root.applyNext()
  }
  function onThemeChanged(slug) {
    var theme = String(slug || "").trim()
    var previous = root.currentTheme
    root.currentTheme = theme
    root.currentThemeDisplay = Schedule.wallpaperName(theme) || "Unknown"
    root.catalogReady = false
    root.catalogPaths = []
    root.wallpaperList = []
    root.currentReady = false
    root.updateCurrent()
    root.refreshCatalog(true)
    // Don't persist on a theme event that races ahead of the config file
    // loading; otherwise in-memory defaults could be written out first and
    // appear to "disable" (or otherwise clobber) saved settings.
    if (!root.loaded) return
    if (!previous || previous === theme) return
    // New theme, new wallpaper set: let interval mode wait before switching,
    // and let pickNext rebuild the shuffle cycle on the next change. Daily
    // selections are validated against the refreshed catalog before use.
    root.saveConfig({
      lastChangeEpoch: Date.now(),
      cycle: [],
      cycleTheme: "",
      lastHandledBoundary: ""
    })
    root.lastAction = "Theme changed to " + root.currentThemeDisplay
  }

  function onSetExited(exitCode) {
    root.busy = false
    var applied = root.pendingWallpaper
    if (exitCode === 0) {
      root.currentWallpaper = applied
      var patch
      if (root.pendingScheduleType === Schedule.SCHEDULE_DAILY) {
        patch = {
          lastHandledBoundary: root.pendingBoundaryToken
            || Schedule.boundaryToken(new Date(), root.currentConfig())
        }
      } else {
        // Start the next interval and keep the shuffle cycle aligned with
        // whichever wallpaper we just showed.
        var next = root.pendingNext
        patch = { lastChangeEpoch: Date.now(), cycleTheme: root.currentTheme }
        if (next) {
          patch.cycle = next.cycle
          patch.cycleIndex = next.cycleIndex
        }
      }
      root.saveConfig(patch)
      if (!root.currentProc.running) root.currentProc.running = true
      root.lastAction = "Wallpaper set to " + Schedule.wallpaperName(applied)
      root.lastError = ""
    } else {
      root.lastError = String(setError.text || "Wallpaper change failed").trim()
    }
    root.pendingWallpaper = ""
    root.pendingNext = null
    root.pendingBoundaryToken = ""
    root.pendingScheduleType = ""
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("")
    onFileChanged: reload()
  }

  FileView {
    id: themeNameFile
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onLoaded: root.onThemeChanged(text())
    onLoadFailed: root.onThemeChanged("")
    onFileChanged: reload()
  }

  Process {
    id: configDirProcess
    command: ["mkdir", "-p", root.configDir]
  }

  Process {
    id: cacheProc
    command: ["omarchy-theme-bg-cache"]
    onExited: function(exitCode) {
      // Run the list either way; missing thumbnails fall back to the original.
      if (!catalogProc.running) catalogProc.running = true
    }
  }

  Process {
    id: catalogProc
    command: ["bash", root.catalogScriptPath]
    stdout: StdioCollector {
      id: catalogOutput
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: catalogError
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = String(catalogError.text || "Could not list wallpapers").trim()
        return
      }
      var parsed = Schedule.parseWallpaperCatalog(catalogOutput.text)
      var paths = []
      var list = []
      for (var i = 0; i < parsed.length; i++) {
        var entry = parsed[i]
        if (!entry.path) continue
        paths.push(entry.path)
        list.push({ path: entry.path, thumb: entry.thumb, name: Schedule.wallpaperName(entry.path) })
      }
      root.catalogPaths = paths
      root.wallpaperList = list
      root.catalogReady = true
      Qt.callLater(root.reconcile)
    }
  }

  Process {
    id: currentProc
    command: ["readlink", "-f", root.currentBgLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        root.currentWallpaper = path !== root.currentWallpaper ? path : root.currentWallpaper
        root.currentReady = true
        Qt.callLater(root.reconcile)
      }
    }
  }

  Process {
    id: setProc
    stderr: StdioCollector {
      id: setError
      waitForEnd: true
    }
    onExited: function(exitCode) { root.onSetExited(exitCode) }
  }

  Timer {
    id: scheduleTimer
    interval: 60000
    running: root.loaded
    repeat: true
    // Pure in-memory check; `reconcile` only spawns a process when a scheduled
    // change is actually due (rare), so an idle plugin pays nothing.
    onTriggered: root.reconcile()
  }

  Component.onCompleted: {
    root.nowEpoch = Date.now()
    configDirProcess.running = true
    root.updateCurrent()
    root.refreshCatalog()
  }
}
