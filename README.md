# dizziee.auto-wallpaper

Preview the active Omarchy theme's wallpapers and switch them on an interval or
at fixed day and night times.

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
| `dayWallpaper` | string | empty | Wallpaper used during the day |
| `nightWallpaper` | string | empty | Wallpaper used during the night |
| `dayStart` | integer | 420 (07:00) | Day boundary in local minutes after midnight |
| `nightStart` | integer | 1140 (19:00) | Night boundary in local minutes after midnight |

## How it works

- **Sequential** advances to the next wallpaper, wrapping at the end.
- **Shuffle** plays every wallpaper once before repeating.
- **Daily times** assigns one wallpaper to the day period and another to the
  night period. Both boundary times are configurable in 15-minute steps.
- In interval mode, manual picks and scheduled changes share the same rotation.
- In interval mode, changing the active theme resets the rotation and waits one
  interval.
- Previews reuse Omarchy's own wallpaper thumbnail cache, so the panel stays
  light and nothing is re-cached.

Daily scheduling follows local time and supports schedules that cross midnight.
If the computer sleeps through a boundary or Omarchy Shell restarts, the plugin
applies the wallpaper for the current period when it resumes. A manual wallpaper
choice remains in place until the next configured day or night boundary.

Daily wallpaper selections belong to the active theme. After changing themes,
choose day and night wallpapers from the new theme before automation continues.

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
