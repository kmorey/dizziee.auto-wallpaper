#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const source = fs.readFileSync(path.join(__dirname, "..", "Schedule.js"), "utf8")
  .replace(/^\.pragma library\s*/, "");
const Schedule = { Math, Date, Number, String, Array, Object, JSON, isFinite };
vm.createContext(Schedule);
vm.runInContext(source, Schedule, { filename: "Schedule.js" });

let checks = 0;
let failures = 0;

function printable(value) {
  if (value instanceof Date) return value.toISOString();
  return JSON.stringify(value);
}

function eq(label, actual, expected) {
  checks++;
  if (printable(actual) !== printable(expected)) {
    failures++;
    console.error(`FAIL ${label}\n  expected ${printable(expected)}\n  actual   ${printable(actual)}`);
  }
}

function differs(label, left, right) {
  checks++;
  if (printable(left) === printable(right)) {
    failures++;
    console.error(`FAIL ${label}\n  both sides are ${printable(left)}`);
  }
}

const dayPath = "/themes/nord/backgrounds/morning-blue.jpg";
const nightPath = "/themes/nord/backgrounds/star-field.png";
const eveningPath = "/themes/nord/backgrounds/sunset.jpg";
const morningPath = "/themes/nord/backgrounds/sunrise.jpg";
const daily = Schedule.normalize({
  enabled: true,
  scheduleType: "daily",
  dailyEntries: [
    { time: 1320, wallpaper: nightPath },
    { time: 360, wallpaper: morningPath },
    { time: 1080, wallpaper: eveningPath },
    { time: 600, wallpaper: dayPath }
  ]
});

eq("legacy configs retain interval behavior",
  Schedule.normalize({ intervalMinutes: 60, mode: "shuffle" }).scheduleType,
  Schedule.SCHEDULE_INTERVAL);
eq("daily mode survives normalization", daily.scheduleType, Schedule.SCHEDULE_DAILY);
eq("unknown schedule mode falls back to interval",
  Schedule.normalize({ scheduleType: "sunrise" }).scheduleType,
  Schedule.SCHEDULE_INTERVAL);
eq("daily entries are sorted by time", daily.dailyEntries.map(entry => entry.time),
  [360, 600, 1080, 1320]);
eq("duplicate times keep the latest valid entry",
  Schedule.normalize({ dailyEntries: [
    { time: 60, wallpaper: dayPath },
    { time: 60, wallpaper: nightPath },
    { time: -1, wallpaper: eveningPath },
    { time: 120, wallpaper: "" }
  ] }).dailyEntries,
  [{ time: 60, wallpaper: nightPath }]);
eq("legacy day and night settings migrate to entries",
  Schedule.normalize({
    dayWallpaper: dayPath,
    nightWallpaper: nightPath,
    dayStart: 420,
    nightStart: 1140
  }).dailyEntries,
  [{ time: 420, wallpaper: dayPath }, { time: 1140, wallpaper: nightPath }]);
eq("time labels are zero padded", Schedule.timeLabel(65), "01:05");
eq("midnight has a twelve-hour clock label", Schedule.clockLabel(0), "12:00 AM");
eq("afternoon has a twelve-hour clock label", Schedule.clockLabel(810), "1:30 PM");

eq("pre-morning hours use the previous night's wallpaper",
  Schedule.desiredWallpaper(new Date(2026, 7, 12, 5, 59), daily), nightPath);
eq("morning begins inclusively",
  Schedule.desiredWallpaper(new Date(2026, 7, 12, 6, 0), daily), morningPath);
eq("daytime begins inclusively",
  Schedule.desiredWallpaper(new Date(2026, 7, 12, 10, 0), daily), dayPath);
eq("evening begins inclusively",
  Schedule.desiredWallpaper(new Date(2026, 7, 12, 18, 0), daily), eveningPath);
eq("night begins inclusively",
  Schedule.desiredWallpaper(new Date(2026, 7, 12, 22, 0), daily), nightPath);
eq("morning boundary token",
  Schedule.boundaryToken(new Date(2026, 7, 12, 8, 0), daily),
  "2026-08-12@360");
eq("pre-morning token uses previous night's date",
  Schedule.boundaryToken(new Date(2026, 7, 12, 2, 0), daily),
  "2026-08-11@1320");
eq("one scheduled period keeps its boundary across midnight",
  Schedule.boundaryToken(new Date(2026, 7, 12, 23, 0), daily),
  Schedule.boundaryToken(new Date(2026, 7, 13, 2, 0), daily));
differs("consecutive nights have different boundaries",
  Schedule.boundaryToken(new Date(2026, 7, 12, 23, 0), daily),
  Schedule.boundaryToken(new Date(2026, 7, 13, 23, 0), daily));
eq("next same-day boundary",
  Schedule.nextBoundary(new Date(2026, 7, 12, 9, 0), daily),
  new Date(2026, 7, 12, 10, 0));
eq("next-day boundary wraps after the final entry",
  Schedule.nextBoundary(new Date(2026, 7, 12, 23, 0), daily),
  new Date(2026, 7, 13, 6, 0));
eq("next switch names the upcoming wallpaper",
  Schedule.nextSwitchText(new Date(2026, 7, 12, 9, 0), daily),
  "Today at 10:00 AM · Morning Blue");
eq("next switch wraps to tomorrow",
  Schedule.nextSwitchText(new Date(2026, 7, 12, 23, 0), daily),
  "Tomorrow at 6:00 AM · Sunrise");

eq("empty daily selections have actionable status",
  Schedule.nextSwitchText(new Date(2026, 7, 12, 12, 0),
    Schedule.normalize({ scheduleType: "daily", enabled: true })),
  "Add a daily schedule time");
eq("no entries have no active wallpaper",
  Schedule.desiredWallpaper(new Date(2026, 7, 12, 12, 0), {}), "");
eq("no entries have no next boundary",
  Schedule.nextBoundary(new Date(2026, 7, 12, 12, 0), {}), null);

const exactMinute = Schedule.normalize({
  scheduleType: "daily",
  dailyEntries: [
    { time: 367, wallpaper: morningPath },
    { time: 1322, wallpaper: nightPath }
  ]
});
eq("daily entries support arbitrary minutes before a boundary",
  Schedule.desiredWallpaper(new Date(2026, 7, 12, 6, 6), exactMinute), nightPath);
eq("daily entries switch on an arbitrary minute",
  Schedule.desiredWallpaper(new Date(2026, 7, 12, 6, 7), exactMinute), morningPath);
eq("next-switch labels preserve arbitrary minutes",
  Schedule.nextSwitchText(new Date(2026, 7, 12, 6, 6), exactMinute),
  "Today at 6:07 AM · Sunrise");

const interval = Schedule.normalize({
  enabled: true,
  intervalMinutes: 30,
  mode: "sequential",
  lastChangeEpoch: 1000
});
eq("existing interval is not due early", Schedule.isDue(interval, 1000 + 29 * 60000), false);
eq("existing interval becomes due", Schedule.isDue(interval, 1000 + 30 * 60000), true);
eq("existing sequential rotation still advances",
  Schedule.pickNext(interval, [dayPath, nightPath], dayPath, "nord").path,
  nightPath);

if (failures) process.exit(1);
console.log(`ok - ${checks} schedule checks`);
