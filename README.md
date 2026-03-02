# Status Dashboard

A lightweight, zero-dependency Ruby status dashboard for macOS. Monitors system resources, launchd services, and optional integrations like Docker/OrbStack and Claude Code API usage.

## Features

- System resource monitoring (CPU, memory, disk, load average, uptime)
- launchd service monitoring with four service types: `daemon`, `runner`, `scheduled`, `process`
- Grouped service organization with status indicators (ok / warning / error / idle)
- Log viewer — tail service logs directly from the dashboard
- Dynamic favicon reflecting overall system health (green/red)
- Optional Docker/OrbStack status monitoring
- Optional Claude Code API usage tracking
- PWA support (installable on iOS/macOS)
- Auto-refresh every 5 seconds
- Dark theme UI
- Zero external dependencies — runs on Ruby stdlib alone

## Requirements

- **macOS** (uses `launchctl`, `vm_stat`, `top`, `df`)
- **Ruby 3.x** (any recent Ruby should work)

## Quick Start

```sh
git clone <repo-url> && cd status
cp config.example.yml config.yml
# Edit config.yml to define your services
ruby server.rb
```

Open [http://localhost:9999](http://localhost:9999) in your browser.

> **Note:** If no `config.yml` exists, the app falls back to `config.example.yml` automatically, so you can run `ruby server.rb` immediately to see the UI.

## Configuration

`config.yml` is gitignored so your personal config stays private. See [`config.example.yml`](config.example.yml) for the full reference with comments.

The config has three sections:

### Dashboard settings

```yaml
dashboard:
  title: "My Status Dashboard"   # Page title and PWA name
  subtitle: "hostname"           # Optional subtitle shown in header
  port: 9999                     # Server port (overridable via PORT env var)
```

### Features

```yaml
features:
  docker: false       # Show Docker/OrbStack status card
  claude_code: false  # Show Claude Code usage section
```

### Services

Services are organized into named groups. Each group has a `label` and a list of `services`:

```yaml
services:
  web:
    label: "Web Services"
    services:
      - id: "com.example.web-server"
        name: "Web Server"
        type: daemon
        log: "~/logs/web-server.log"

      - id: "com.example.cleanup"
        name: "Cleanup Job"
        type: scheduled
        schedule: "Every 30 min"
        log: "~/logs/cleanup.log"

  runners:
    label: "GitHub Actions Runners"
    services:
      - id: "actions.runner.myorg-myrepo.runner1"
        name: "myrepo"
        type: runner
        log: "~/Library/Logs/actions.runner.myorg-myrepo.runner1/stdout.log"

  background:
    label: "Background Processes"
    services:
      - id: "my-worker"
        name: "Worker"
        type: process
        process: "my-worker"
```

**Service types:**

| Type | Description |
|------|-------------|
| `daemon` | Long-running launchd process — should always have a PID |
| `runner` | GitHub Actions self-hosted runner — checks for `Runner.Listener` process |
| `scheduled` | Runs on a schedule — "idle" is normal when not running |
| `process` | Monitors any process by name via `ps` |

**Service fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | launchd job label or unique identifier |
| `name` | Yes | Display name in the dashboard |
| `type` | Yes | One of: `daemon`, `runner`, `scheduled`, `process` |
| `log` | No | Path to log file (supports `~` and `$HOME` expansion) |
| `schedule` | No | Display label for scheduled services (e.g., "Every 30 min") |
| `process` | No | Process name to search for (required for `process` type) |

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | HTML dashboard |
| `GET` | `/api/status` | JSON system + service status |
| `GET` | `/api/logs?service=<id>&lines=<n>` | Tail log for a service (lines: 1–1000, default 100) |
| `POST` | `/api/docker/start` | Start Docker/OrbStack (requires `docker` feature) |
| `GET` | `/health` | Health check (returns `ok`) |
| `GET` | `/favicon.svg` | Dynamic status favicon |

## Running as a Background Service

To run the dashboard as a persistent launchd service that starts on login:

1. Copy the example plist:
   ```sh
   cp config/examples/launchd-server.plist ~/Library/LaunchAgents/com.status-dashboard.plist
   ```

2. Edit the plist to customize paths for your environment:
   - Path to your Ruby binary (e.g., output of `which ruby`)
   - Path to the `server.rb` file
   - Working directory
   - `HOME` and `PATH` environment variables
   - Log file path

3. Load the service:
   ```sh
   launchctl load ~/Library/LaunchAgents/com.status-dashboard.plist
   ```

4. To stop the service:
   ```sh
   launchctl unload ~/Library/LaunchAgents/com.status-dashboard.plist
   ```

The plist uses `KeepAlive` and `RunAtLoad`, so the server starts on login and automatically restarts if it exits.

> A tunnel plist example (`config/examples/launchd-tunnel.plist`) is also provided for setting up remote access via SSH tunneling — customize it for your environment.

## Optional Features

### Docker / OrbStack

Set `features.docker: true` in your config. The dashboard will show a Docker status card with the running state and Docker version. If Docker is stopped, a "Start Docker" button appears (uses OrbStack on macOS).

### Claude Code Usage

Set `features.claude_code: true` in your config. This reads your Claude Code OAuth token from the macOS Keychain (stored automatically by the Claude Code desktop app under "Claude Code-credentials") and displays weekly and per-session usage bars with pace indicators. If the token isn't available, the section gracefully shows "Disconnected."

## Running Tests

```sh
ruby test/config_test.rb
```

## License

MIT
