# dizziee.auto-wallpaper

Preview the active Omarchy theme's wallpapers and switch them on an interval or
at any number of fixed daily times.

## Requirements

- Omarchy 4 (Quattro) with the Quickshell bar
- A theme that ships wallpapers (under its `backgrounds/` directory)

## Installation

```sh
omarchy plugin add https://github.com/JJDizz1L/dizziee.auto-wallpaper.git --enable
```

### Then place it in your bar layout with

`omarchy bar plugin add dizziee.auto-wallpaper [--section <left|center|right>]`

Suggested placement:

```sh
omarchy bar plugin add dizziee.auto-wallpaper --section right
```

You can validate the plugin at any time with:

```sh
omarchy plugin validate ~/.config/omarchy/plugins/dizziee.auto-wallpaper
```

## Configuration

Configuration lives in `~/.config/omarchy/auto-wallpaper/config.json`.

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | boolean | true | Automatically cycle wallpapers |
| `scheduleType` | string (`interval`, `daily`) | `interval` | Scheduling strategy |
| `intervalMinutes` | integer | 30 | How often the wallpaper changes |
| `mode` | string (`sequential`, `shuffle`) | `sequential` | Rotation order |
| `dailyEntries` | array | `[]` | Sorted `{ time, wallpaper }` daily schedule entries; `time` is local minutes after midnight |

## How it works

- **Sequential** advances to the next wallpaper, wrapping at the end.
- **Shuffle** plays every wallpaper once before repeating.
- **Daily times** accepts any number of exact hour/minute entries. Each entry
  selects a wallpaper from a scrollable thumbnail picker.
- In interval mode, manual picks and scheduled changes share the same rotation.
- In interval mode, changing the active theme resets the rotation and waits one
  interval.
- Previews reuse Omarchy's own wallpaper thumbnail cache, so the panel stays
  light and nothing is re-cached.

Daily scheduling follows local time and wraps from the final entry back to the
first entry on the following day. If the computer sleeps through a scheduled
time or Omarchy Shell restarts, the plugin applies the wallpaper for the current
period when it resumes. A manual wallpaper choice remains in place until the
next scheduled time.

Configurations created by the earlier two-entry day/night implementation are
converted to `dailyEntries` automatically.

Daily wallpaper selections belong to the active theme. After changing themes,
edit the schedule with wallpapers from the new theme before automation continues.

## Development

```sh
node tests/test_schedule.js
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell ./*.qml
```

## Preview

![preview](preview.png)

## Uninstall

```sh
omarchy plugin remove dizziee.auto-wallpaper
```

## License

MIT
