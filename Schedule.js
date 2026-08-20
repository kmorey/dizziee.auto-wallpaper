.pragma library

var DEFAULTS = {
  enabled: true,
  scheduleType: "interval",
  intervalMinutes: 30,
  mode: "sequential",
  lastChangeEpoch: 0,
  cycle: [],
  cycleIndex: 0,
  cycleTheme: "",
  dayWallpaper: "",
  nightWallpaper: "",
  dayStart: 420,
  nightStart: 1140,
  lastHandledBoundary: ""
}

var MODE_SEQUENTIAL = "sequential"
var MODE_SHUFFLE = "shuffle"
var SCHEDULE_INTERVAL = "interval"
var SCHEDULE_DAILY = "daily"

function integer(value, fallback) {
  var parsed = Number(value)
  return isFinite(parsed) && Math.floor(parsed) === parsed ? parsed : fallback
}

function interval(value, fallback) {
  var parsed = integer(value, fallback)
  return parsed >= 1 && parsed <= 1440 ? parsed : fallback
}

function minute(value, fallback) {
  var parsed = integer(value, fallback)
  return parsed >= 0 && parsed < 1440 ? parsed : fallback
}

function mode(value, fallback) {
  return value === MODE_SHUFFLE ? MODE_SHUFFLE : MODE_SEQUENTIAL
}

function scheduleType(value) {
  return value === SCHEDULE_DAILY ? SCHEDULE_DAILY : SCHEDULE_INTERVAL
}

function wallpaperPath(value) {
  return typeof value === "string" ? value.trim() : ""
}

function normalize(raw) {
  var source = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}
  var dayStart = minute(source.dayStart, DEFAULTS.dayStart)
  var nightStart = minute(source.nightStart, DEFAULTS.nightStart)
  if (dayStart === nightStart) nightStart = (dayStart + 720) % 1440
  return {
    enabled: typeof source.enabled === "boolean" ? source.enabled : DEFAULTS.enabled,
    scheduleType: scheduleType(source.scheduleType),
    intervalMinutes: interval(source.intervalMinutes, DEFAULTS.intervalMinutes),
    mode: mode(source.mode, DEFAULTS.mode),
    lastChangeEpoch: integer(source.lastChangeEpoch, DEFAULTS.lastChangeEpoch),
    cycle: Array.isArray(source.cycle) ? source.cycle.slice() : [],
    cycleIndex: integer(source.cycleIndex, DEFAULTS.cycleIndex),
    cycleTheme: typeof source.cycleTheme === "string" ? source.cycleTheme : "",
    dayWallpaper: wallpaperPath(source.dayWallpaper),
    nightWallpaper: wallpaperPath(source.nightWallpaper),
    dayStart: dayStart,
    nightStart: nightStart,
    lastHandledBoundary: typeof source.lastHandledBoundary === "string"
      ? source.lastHandledBoundary : ""
  }
}

// Parse the catalog script's tab-separated rows "<path>\t<thumbnail path>"
// into an array of { path, thumb }. Blank lines are ignored; a row without a
// thumbnail column falls back to the original path.
function parseWallpaperCatalog(text) {
  var result = []
  var seen = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].split("\t")
    var path = String(fields[0] || "").trim()
    if (!path || seen[path]) continue
    seen[path] = true
    var thumb = String(fields[1] || "").trim()
    result.push({ path: path, thumb: thumb || path })
  }
  return result
}

// Turn a wallpaper path into a short, human-readable display name.
function wallpaperName(path) {
  var base = String(path || "").replace(/\\/g, "/").split("/").pop()
  base = base.replace(/\.[^.]+$/, "")
  if (!base) return "Unknown"
  base = base.replace(/[-_.]+/g, " ")
  return base.replace(/\b[a-z]/g, function(letter) { return letter.toUpperCase() })
    .replace(/\s+/g, " ").trim()
}

function pad(value) {
  return value < 10 ? "0" + value : String(value)
}

function timeLabel(minutes) {
  var value = minute(minutes, 0)
  return pad(Math.floor(value / 60)) + ":" + pad(value % 60)
}

function minuteOfDay(date) {
  return date.getHours() * 60 + date.getMinutes()
}

function isDayAt(minutes, dayStart, nightStart) {
  if (dayStart < nightStart) return minutes >= dayStart && minutes < nightStart
  return minutes >= dayStart || minutes < nightStart
}

function periodAt(date, config) {
  var normalized = normalize(config)
  return isDayAt(minuteOfDay(date), normalized.dayStart, normalized.nightStart)
    ? "day" : "night"
}

function desiredWallpaper(date, config) {
  var normalized = normalize(config)
  return periodAt(date, normalized) === "day"
    ? normalized.dayWallpaper : normalized.nightWallpaper
}

function localDateKey(date) {
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function dateAtMinute(date, minutes, dayDelta) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + (dayDelta || 0),
                  Math.floor(minutes / 60), minutes % 60, 0, 0)
}

// Return the boundary that opened the current day/night period. Keeping this
// token stable across midnight prevents a manual override from being undone
// before the next configured boundary.
function boundaryInfo(date, config) {
  var normalized = normalize(config)
  var period = periodAt(date, normalized)
  var start = period === "day" ? normalized.dayStart : normalized.nightStart
  var boundary = dateAtMinute(date, start, 0)
  if (boundary.getTime() > date.getTime()) boundary = dateAtMinute(date, start, -1)
  return { date: boundary, period: period, start: start }
}

function boundaryToken(date, config) {
  var info = boundaryInfo(date, config)
  return localDateKey(info.date) + "@" + info.period + "@" + info.start
}

function nextBoundary(date, config) {
  var normalized = normalize(config)
  var period = periodAt(date, normalized)
  var start = period === "day" ? normalized.nightStart : normalized.dayStart
  var next = dateAtMinute(date, start, 0)
  if (next.getTime() <= date.getTime()) next = dateAtMinute(date, start, 1)
  return next
}

function nextSwitchText(date, config) {
  var normalized = normalize(config)
  if (!normalized.enabled) return "Automatic switching is off"
  if (!normalized.dayWallpaper || !normalized.nightWallpaper)
    return "Choose day and night wallpapers"

  var next = nextBoundary(date, normalized)
  var nextWallpaper = periodAt(date, normalized) === "day"
    ? normalized.nightWallpaper : normalized.dayWallpaper
  var prefix = localDateKey(next) === localDateKey(date) ? "Today at " : "Tomorrow at "
  return prefix + timeLabel(next.getHours() * 60 + next.getMinutes()) + " · "
    + wallpaperName(nextWallpaper)
}

function timeOptions(step) {
  var size = integer(step, 15)
  if (size <= 0 || size > 720) size = 15
  var options = []
  for (var value = 0; value < 1440; value += size)
    options.push({ value: String(value), label: timeLabel(value) })
  return options
}

function scheduleTypeOptions() {
  return [
    { value: SCHEDULE_INTERVAL, label: "Interval" },
    { value: SCHEDULE_DAILY, label: "Daily times" }
  ]
}

function wallpaperOptions(catalog) {
  var values = [{ value: "", label: "Choose wallpaper" }]
  var entries = Array.isArray(catalog) ? catalog : []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i] || {}
    var path = wallpaperPath(entry.path)
    if (!path) continue
    values.push({ value: path, label: entry.name || wallpaperName(path) })
  }
  return values
}

// Fisher-Yates shuffle. `rng` is optional to support deterministic tests.
function shuffle(values, rng) {
  var a = Array.isArray(values) ? values.slice() : []
  for (var i = a.length - 1; i > 0; i--) {
    var j = Math.floor((rng ? rng() : Math.random()) * (i + 1))
    var t = a[i]
    a[i] = a[j]
    a[j] = t
  }
  return a
}

function sameSet(left, right) {
  if (left.length !== right.length) return false
  var sortedL = left.slice().sort()
  var sortedR = right.slice().sort()
  for (var i = 0; i < sortedL.length; i++)
    if (sortedL[i] !== sortedR[i]) return false
  return true
}

// A persisted shuffle cycle stays valid only while the theme is unchanged and
// the catalog still contains exactly the same paths.
function cycleStillValid(cycle, catalog, cycleTheme, theme) {
  if (cycleTheme !== theme || !Array.isArray(cycle)) return false
  return sameSet(cycle, catalog)
}
// Compute the next wallpaper for the given catalog and current selection. Pure
// and deterministic given a fixed rng. Returns the target path ("" when there
// is nothing to change to) plus the shuffle bookkeeping that must be saved.
//
// Sequential: advance one slot past the current wallpaper, wrapping around.
// Shuffle: step a persisted, never-repeating cycle. The cycle is rebuilt when
// the theme or catalog changes, then resumes from wherever the current
// wallpaper sits so manual picks stay part of the rotation.
function pickNext(config, catalog, currentPath, theme, rng) {
  var paths = Array.isArray(catalog) ? catalog.slice() : []
  if (paths.length === 0)
    return { path: "", cycle: [], cycleIndex: 0, changed: false }

  var cycle
  var cycleIndex

  if (config.mode === MODE_SHUFFLE) {
    if (cycleStillValid(config.cycle, paths, config.cycleTheme, theme)) {
      cycle = config.cycle.slice()
      cycleIndex = config.cycleIndex || 0
    } else {
      cycle = shuffle(paths, rng)
      var idx = currentPath ? cycle.indexOf(currentPath) : -1
      cycleIndex = idx >= 0 ? idx : -1
    }

    if (cycle.length <= 1)
      return { path: "", cycle: cycle, cycleIndex: cycleIndex, changed: false }

    var nextShuffle = (cycleIndex + 1) % cycle.length
    return {
      path: cycle[nextShuffle],
      cycle: cycle,
      cycleIndex: nextShuffle,
      changed: cycle[nextShuffle] !== currentPath
    }
  }

  var at = currentPath ? paths.indexOf(currentPath) : -1
  if (paths.length <= 1)
    return { path: "", cycle: [], cycleIndex: 0, changed: false }
  var nextSeq = at >= 0 ? (at + 1) % paths.length : 0
  return {
    path: paths[nextSeq],
    cycle: [],
    cycleIndex: 0,
    changed: paths[nextSeq] !== currentPath
  }
}

// Is a scheduled change due right now?
function isDue(config, nowEpoch) {
  if (!config.enabled) return false
  var last = config.lastChangeEpoch > 0 ? config.lastChangeEpoch : 0
  var elapsed = nowEpoch - last
  if (elapsed < 0) elapsed = 0
  return elapsed >= (config.intervalMinutes || 0) * 60000
}

// Whole minutes until the next scheduled change (ceil). -1 when automation off.
function minutesUntil(config, nowEpoch) {
  if (!config.enabled) return -1
  var last = config.lastChangeEpoch > 0 ? config.lastChangeEpoch : 0
  var intervalMs = (config.intervalMinutes || 0) * 60000
  var remaining = intervalMs - (nowEpoch - last)
  if (remaining < 1) remaining = 1
  return Math.ceil(remaining / 60000)
}

function modeLabel(modeValue) {
  return modeValue === MODE_SHUFFLE ? "Shuffle" : "Sequential"
}

function intervalLabel(minutes) {
  var value = interval(minutes, 60)
  if (value < 60) return "Every " + value + " min"
  var hours = value / 60
  if (value % 60 === 0) return "Every " + hours + (hours === 1 ? " hour" : " hours")
  return "Every " + value + " min"
}

function intervalOptions() {
  var steps = [5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 360, 480, 720, 1440]
  var options = []
  for (var i = 0; i < steps.length; i++) {
    var minutes = steps[i]
    options.push({ value: String(minutes), label: intervalLabel(minutes) })
  }
  return options
}

function modeOptions() {
  return [
    { value: MODE_SEQUENTIAL, label: "Sequential" },
    { value: MODE_SHUFFLE, label: "Shuffle" }
  ]
}
