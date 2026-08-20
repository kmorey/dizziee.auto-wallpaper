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
const daily = Schedule.normalize({
  enabled: true,
  scheduleType: "daily",
  dayWallpaper: dayPath,
  nightWallpaper: nightPath,
  dayStart: 420,
  nightStart: 1140
});

eq("legacy configs retain interval behavior",
  Schedule.normalize({ intervalMinutes: 60, mode: "shuffle" }).scheduleType,
  Schedule.SCHEDULE_INTERVAL);
eq("daily mode survives normalization", daily.scheduleType, Schedule.SCHEDULE_DAILY);
eq("unknown schedule mode falls back to interval",
  Schedule.normalize({ scheduleType: "sunrise" }).scheduleType,
  Schedule.SCHEDULE_INTERVAL);
eq("invalid daily times use defaults",
  [Schedule.normalize({ dayStart: -1, nightStart: "late" }).dayStart,
    Schedule.normalize({ dayStart: -1, nightStart: "late" }).nightStart],
  [420, 1140]);
eq("equal boundaries are separated",
  Schedule.normalize({ dayStart: 60, nightStart: 60 }).nightStart, 780);
eq("time options cover a day in quarter hours", Schedule.timeOptions(15).length, 96);
eq("time labels are zero padded", Schedule.timeLabel(65), "01:05");

eq("day begins inclusively",
  Schedule.periodAt(new Date(2026, 7, 12, 7, 0), daily), "day");
eq("night begins inclusively",
  Schedule.periodAt(new Date(2026, 7, 12, 19, 0), daily), "night");
eq("day wallpaper is selected",
  Schedule.desiredWallpaper(new Date(2026, 7, 12, 12, 0), daily), dayPath);
eq("night wallpaper is selected",
  Schedule.desiredWallpaper(new Date(2026, 7, 12, 23, 0), daily), nightPath);
eq("day boundary token",
  Schedule.boundaryToken(new Date(2026, 7, 12, 8, 0), daily),
  "2026-08-12@day@420");
eq("pre-dawn night uses previous boundary",
  Schedule.boundaryToken(new Date(2026, 7, 12, 2, 0), daily),
  "2026-08-11@night@1140");
eq("one night keeps its boundary across midnight",
  Schedule.boundaryToken(new Date(2026, 7, 12, 23, 0), daily),
  Schedule.boundaryToken(new Date(2026, 7, 13, 2, 0), daily));
differs("consecutive nights have different boundaries",
  Schedule.boundaryToken(new Date(2026, 7, 12, 23, 0), daily),
  Schedule.boundaryToken(new Date(2026, 7, 13, 23, 0), daily));
eq("next night boundary",
  Schedule.nextBoundary(new Date(2026, 7, 12, 12, 0), daily),
  new Date(2026, 7, 12, 19, 0));
eq("next day boundary",
  Schedule.nextBoundary(new Date(2026, 7, 12, 23, 0), daily),
  new Date(2026, 7, 13, 7, 0));
eq("next switch names tonight's wallpaper",
  Schedule.nextSwitchText(new Date(2026, 7, 12, 12, 0), daily),
  "Today at 19:00 · Star Field");
eq("next switch names tomorrow's wallpaper",
  Schedule.nextSwitchText(new Date(2026, 7, 12, 23, 0), daily),
  "Tomorrow at 07:00 · Morning Blue");

const overnight = Schedule.normalize({
  scheduleType: "daily",
  dayWallpaper: dayPath,
  nightWallpaper: nightPath,
  dayStart: 1200,
  nightStart: 360
});
eq("overnight day before midnight",
  Schedule.periodAt(new Date(2026, 7, 12, 23, 0), overnight), "day");
eq("overnight day after midnight",
  Schedule.periodAt(new Date(2026, 7, 13, 2, 0), overnight), "day");
eq("overnight night period",
  Schedule.periodAt(new Date(2026, 7, 13, 10, 0), overnight), "night");
eq("overnight token crosses the date boundary",
  Schedule.boundaryToken(new Date(2026, 7, 13, 2, 0), overnight),
  "2026-08-12@day@1200");

eq("empty daily selections have actionable status",
  Schedule.nextSwitchText(new Date(2026, 7, 12, 12, 0),
    Schedule.normalize({ scheduleType: "daily", enabled: true })),
  "Choose day and night wallpapers");
eq("wallpaper options include a prompt and names",
  Schedule.wallpaperOptions([{ path: dayPath, name: "Morning" }]),
  [{ value: "", label: "Choose wallpaper" },
    { value: dayPath, label: "Morning" }]);

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
