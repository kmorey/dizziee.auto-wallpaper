# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Flexible daily scheduling with any number of exact hour/minute wallpaper
  entries.
- A scrollable thumbnail picker for choosing each scheduled wallpaper.
- Local-time overnight handling and catch-up after sleep or shell restart.
- Daily-mode manual overrides that remain active until the next scheduled time.
- Automatic migration from the earlier fixed day/night configuration.
- Unit coverage for daily-entry normalization, migration, boundaries, overnight
  wrapping, and next-switch labels.

### Changed

- The schedule panel switches between interval rotation and flexible daily
  times without changing existing interval configurations.

## [1.0.0] - 2026-08-15

### Added

- Wallpaper preview grid for the active theme, with click-to-apply and a
  highlighted border on the current wallpaper.
- Automatic wallpaper cycling on a schedule: sequential advance or shuffle
  (play every wallpaper once before repeating).
- Interval options from 5 minutes to 24 hours.
- Theme-name detection that resets the rotation when the active theme changes.
- Persistent configuration under `~/.config/omarchy/auto-wallpaper/`.
- Omarchy bar widget with a "next wallpaper" tooltip and a middle-click to
  apply the next wallpaper now.
- Shell IPC commands for status, enable, disable, and immediate application.
- Pure scheduling logic with unit tests and a wallpaper catalog test in CI.

### Changed

- Rebranded from the upstream `acrogenesis.theme-scheduler` plugin as
  `dizziee.auto-wallpaper`, focused on wallpaper rotation instead of light/dark
  theme switching.

[Unreleased]: https://github.com/JJDizz1L/dizziee.auto-wallpaper/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/JJDizz1L/dizziee.auto-wallpaper/releases/tag/v1.0.0
