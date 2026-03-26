# ClaudeUsageBar

A lightweight macOS menu bar app that monitors your Claude API usage in real-time.

<!-- screenshot goes here -->

## Features

- Displays 5-hour rolling, 7-day rolling, and Sonnet-specific usage percentages directly in the menu bar
- Color-coded indicators: green (normal), orange (warning), red (critical)
- Warning icon when any metric reaches the critical threshold
- Popover panel with progress bars, reset countdowns, and a link to the Anthropic console
- System notifications when 7-day usage crosses configurable thresholds
- Configurable warning and critical threshold percentages
- No external dependencies — uses only Apple frameworks

## Requirements

- macOS 13.0+
- Claude Code installed and signed in (credentials must be present in macOS Keychain)

## Installation

### Download

Pre-built universal binaries are available on the [GitHub Releases](../../releases) page.

1. Download the latest `.zip` from Releases
2. Unzip and drag `ClaudeUsageBar.app` to `/Applications`
3. On first launch, right-click the app and choose "Open" (required for unsigned apps)

Alternatively, remove the quarantine flag via Terminal:

```sh
xattr -cr ClaudeUsageBar.app
```

### Build from Source

Prerequisites: Swift 5.9+, Xcode command line tools, macOS 13+

```sh
make app             # Build .app bundle (current architecture)
make app-universal   # Build universal binary (Apple Silicon + Intel)
make install         # Install to /Applications
make run             # Build and launch
make test            # Run tests
make clean           # Clean build artifacts
```

## Usage

Once running, ClaudeUsageBar appears in the menu bar as:

```
5h:[%] · 7d:[%] · S:[%]
```

The three values represent your 5-hour rolling, 7-day rolling, and Sonnet-specific usage percentages. Click the menu bar item to open the popover panel, which shows detailed usage rows with progress bars and reset countdowns. From the popover you can manually refresh, open the Anthropic usage console, access Settings, or quit the app.

## Configuration

Open Settings from the popover panel to configure:

- **Notifications** — toggle system notifications on or off
- **Warning threshold** — percentage at which indicators turn orange (50–95%, default 80%)
- **Critical threshold** — percentage at which indicators turn red and a warning icon appears (60–100%, default 90%)
- **Reset to defaults** — restore all settings to their default values

Notifications fire when 7-day usage crosses either threshold, with a 1-hour cooldown between repeated alerts.

## How It Works

ClaudeUsageBar reads your OAuth token from the macOS Keychain (service: `Claude Code-credentials`) — the same credentials stored when you sign in to Claude Code. It polls `https://api.anthropic.com/api/oauth/usage` every 5 minutes, backing off to 15-minute intervals if the request is rate-limited or credentials are not found. Settings are persisted in `UserDefaults`.

## License

MIT
