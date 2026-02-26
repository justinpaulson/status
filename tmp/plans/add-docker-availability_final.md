# Plan: Add Docker (OrbStack) Availability Indicator

## Context Analysis

The Mac Mini status dashboard monitors system metrics (CPU, memory, disk, uptime) and 22 launchd-managed services across 3 groups. GitHub Actions runners depend on Docker being available, and failed runs have occurred because Docker/OrbStack wasn't running.

**Key patterns in the existing codebase:**
- `SystemStats` module collects system-level metrics (CPU, memory, disk, uptime) via shell commands
- `ServiceChecker` module checks launchd-managed services via `launchctl list` and `ps`
- `StatusPage.collect_all` aggregates both into a cached data hash (`system:` + `services:`)
- The HTML template renders system stats as cards in a grid, and services as grouped rows
- JavaScript auto-refreshes via `/api/status` every 15 seconds and updates DOM in-place
- The favicon turns red if any service has a non-"ok" status

**Docker/OrbStack is different from existing services** — it's a macOS application, not a launchd daemon managed the same way. It fits better as system-level infrastructure (alongside CPU/memory/disk) since runners depend on it.

## Files to Modify

### 1. `lib/system_stats.rb`
Add a `docker` key to the collected stats hash with Docker/OrbStack availability info.

### 2. `templates/status.html.erb`
- Add a Docker stat card in the system-stats grid
- Include a "Start" button when Docker is not running
- Update the JavaScript `refresh()` function to handle the new Docker card and start action

### 3. `server.rb`
Add a `POST /api/docker/start` endpoint that triggers OrbStack startup.

## Implementation Steps

### Step 1: Add Docker check to `SystemStats` (`lib/system_stats.rb`)

Add a new method `parse_docker` and include it in `collect`:

```ruby
def self.collect
  {
    uptime: parse_uptime,
    cpu: parse_cpu,
    memory: parse_memory,
    disk: parse_disk,
    load: parse_load,
    docker: parse_docker
  }
end
```

**`parse_docker` method logic:**
1. Run `docker info --format '{{.ServerVersion}}' 2>/dev/null` — this returns the Docker server version if Docker is running, or fails/returns empty if not
2. If the command succeeds and returns a version string:
   - `{ running: true, version: "X.Y.Z" }`
3. If the command fails or returns empty:
   - Check if OrbStack is installed: `command -v orbctl >/dev/null 2>&1` or check if `/Applications/OrbStack.app` exists
   - `{ running: false, orbstack_installed: true/false }`

**Why `docker info` over `pgrep`:** `docker info` confirms the Docker daemon is actually responsive and ready to accept commands, not just that a process exists. This matches the real failure mode (runner tries to use Docker and it's not ready).

### Step 2: Add Docker stat card to template (`templates/status.html.erb`)

Add a 5th card to the `.system-stats` grid, after the Uptime card:

```erb
<div class="stat-card" id="docker-card">
  <div class="label">Docker</div>
  <% if data[:system][:docker][:running] %>
    <div class="value" style="font-size:16px; color: #3fb950;">Running</div>
    <div class="sub">v<%= data[:system][:docker][:version] %></div>
  <% else %>
    <div class="value" style="font-size:16px; color: #f85149;">Stopped</div>
    <div class="sub">
      <% if data[:system][:docker][:orbstack_installed] %>
        <button class="log-btn" onclick="startDocker()" id="start-docker-btn">Start OrbStack</button>
      <% else %>
        OrbStack not installed
      <% end %>
    </div>
  <% end %>
</div>
```

**CSS addition:** Add a style for a small status dot/indicator within the Docker card (reuse existing badge styles or keep minimal with inline color).

### Step 3: Add `POST /api/docker/start` endpoint (`server.rb`)

In the request routing section of `server.rb`, add handling for a POST to `/api/docker/start`:

```ruby
elsif _method == 'POST' && path == '/api/docker/start'
  # Start OrbStack in the background
  system('open -a OrbStack')
  body = JSON.generate({ status: 'starting' })
  conn.print "HTTP/1.1 200 OK\r\n" \
             "Content-Type: application/json; charset=utf-8\r\n" \
             "Content-Length: #{body.bytesize}\r\n" \
             "Cache-Control: no-cache\r\n" \
             "Access-Control-Allow-Origin: *\r\n" \
             "Connection: close\r\n\r\n#{body}"
```

Place this route **before** the catch-all `else` block. Use `open -a OrbStack` which is the standard macOS way to launch applications.

**Important:** Also need to read the request body for POST requests (even though we don't need body content for this endpoint). The current header-reading loop already discards headers; we just need to handle the Content-Length for POST bodies if present, or simply not require a body.

### Step 4: Add JavaScript `startDocker()` function and update `refresh()` (`templates/status.html.erb`)

**Add `startDocker()` function:**
```javascript
function startDocker() {
  var btn = document.getElementById('start-docker-btn');
  if (btn) {
    btn.textContent = 'Starting...';
    btn.disabled = true;
  }
  fetch('/api/docker/start', { method: 'POST' })
    .then(function() {
      // The next status refresh will pick up the new state
      if (btn) btn.textContent = 'Starting...';
    })
    .catch(function() {
      if (btn) { btn.textContent = 'Start OrbStack'; btn.disabled = false; }
    });
}
```

**Update the `refresh()` function** to update the Docker card on each status poll:

In the system stats update section (after updating cards[3] for uptime), add logic to update the Docker card:

```javascript
// Update Docker card
var dockerCard = document.getElementById('docker-card');
if (dockerCard && sys.docker) {
  if (sys.docker.running) {
    dockerCard.querySelector('.value').textContent = 'Running';
    dockerCard.querySelector('.value').style.color = '#3fb950';
    dockerCard.querySelector('.sub').textContent = 'v' + sys.docker.version;
  } else {
    dockerCard.querySelector('.value').textContent = 'Stopped';
    dockerCard.querySelector('.value').style.color = '#f85149';
    if (sys.docker.orbstack_installed) {
      dockerCard.querySelector('.sub').innerHTML = '<button class="log-btn" onclick="startDocker()" id="start-docker-btn">Start OrbStack</button>';
    } else {
      dockerCard.querySelector('.sub').textContent = 'OrbStack not installed';
    }
  }
}
```

### Step 5: Include Docker status in favicon health check (`server.rb`)

Update the favicon route to also consider Docker status:

```ruby
elsif path == '/favicon.svg'
  data = StatusPage.collect_all
  all_ok = data[:services].values.all? { |g|
    g[:services].all? { |s| s[:status] == "ok" }
  } && data[:system][:docker][:running]
```

And similarly update the JavaScript `allOk` check in the `refresh()` function:

```javascript
var allOk = Object.keys(data.services).every(function(key) {
  return data.services[key].services.every(function(s) { return s.status === 'ok'; });
}) && data.system.docker && data.system.docker.running;
```

This ensures the favicon reflects Docker being down as a problem, which is appropriate since it causes runner failures.

## Testing Strategy

1. **Docker running:** Start OrbStack, verify the card shows "Running" with version, green color
2. **Docker stopped:** Quit OrbStack, verify the card shows "Stopped" with "Start OrbStack" button, red color
3. **Start button:** Click "Start OrbStack" button, verify:
   - Button text changes to "Starting..."
   - OrbStack actually launches
   - On next auto-refresh (15s), card updates to "Running"
4. **API endpoint:** `curl -X POST http://localhost:9999/api/docker/start` — verify 200 response with `{"status":"starting"}`
5. **API status:** `curl http://localhost:9999/api/status | jq .system.docker` — verify correct docker object
6. **Favicon:** Verify favicon shows red when Docker is stopped, green when all services OK and Docker running
7. **Auto-refresh:** Verify Docker card updates correctly on each 15-second poll cycle
8. **Mobile:** Verify Docker card renders properly in the responsive grid on small screens

## Edge Cases

1. **`docker` CLI not installed:** `docker info` will fail with command not found. The `parse_docker` method should handle this gracefully — return `{ running: false, orbstack_installed: false }` (or check for OrbStack app separately)

2. **Docker starting but not ready:** There's a window after `open -a OrbStack` where the app is launching but `docker info` still fails. The button shows "Starting..." and the next few status polls may still show "Stopped" until Docker is fully ready. This is acceptable — no need to add a transitional state.

3. **OrbStack installed but `docker` symlink missing:** OrbStack normally creates the `docker` CLI symlink, but if it's missing, fall back to checking `/Applications/OrbStack.app` existence for the "installed" flag and use `orbctl start` as an alternative start command.

4. **Slow `docker info` command:** If Docker daemon is hanging, `docker info` could take a long time. Add a timeout: use `timeout 3 docker info ...` (or Ruby's `IO.popen` with timeout) to prevent blocking the status collection. Since `SystemStats.collect` runs on every status check (every 5s cache TTL), a hanging Docker command would freeze the entire dashboard.

5. **Multiple rapid "Start" clicks:** The button is disabled after first click, preventing duplicate `open -a OrbStack` calls. Even if called twice, `open -a` is idempotent for already-running apps.

6. **POST body handling:** The current server reads headers until `\r\n` but doesn't read POST bodies. For this endpoint no body is needed, but if a client sends one (e.g., `Content-Length: 0`), the unread bytes could cause issues on the socket. Should read and discard the body based on `Content-Length` header if present.
