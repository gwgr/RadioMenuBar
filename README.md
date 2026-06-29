# RadioMenuBar

Minimal macOS menu bar app for live radio streams, with a custom app icon and editable station list.

![Screenshot](screenshot.png)

## Build App

From the repository root:

```bash
./scripts/build-app.sh
```

This creates:

```text
dist/RadioMenuBar.app
```

Double-click `dist/RadioMenuBar.app` to start it. The app runs as a menu bar item and does not show a Dock icon.

## Run From Source

```bash
cd RadioMenuBar
swift run
```

You can also run it from this nested package directory with `cd app && swift run`.

The built app copies its editable station config to:

```text
~/Library/Application Support/RadioMenuBar/stations.json
```

When running from source, it also falls back to `stations.json` in the current working directory or `app/stations.json` when launched from the repository root.

## Features

- Menu bar station picker
- Play, stop, and active-station indicator
- Optional station-name display in the menu bar
- Persisted last selected station
- Persisted volume control
- Loading, playing, stopped, and failed states
- macOS Now Playing metadata
- Media play/pause/stop command support
- Reloadable `stations.json`
- Menu item to open the station config
- Visible config load warnings in the menu
- Keyboard shortcuts for stations 1-9, reload, config, and quit
- Launch at Login toggle in the built app

## Default Stations

The bundled `app/stations.json` currently includes:

- ABC NewsRadio
- Gold 104.3
- The Fox Melbourne
- Triple M Melbourne 105.1
- triple j
- Triple R 102.7FM

## Notes

- Requires macOS 13 or newer for `MenuBarExtra`.
- Keep `stations.json` URLs pointed at stable stream URLs.
- Do not save generated `listeningSessionID` child playlist URLs from LISTNR streams.
- Station config warnings appear in the menu when a config cannot be loaded.
- Launch at Login uses macOS ServiceManagement in the built app.

## Disclaimer

RadioMenuBar is an independent app and is not affiliated with the broadcasters included in the sample station list. Stream URLs belong to their respective broadcasters and may change without notice. Users are responsible for configuring and using valid public stream URLs.
