# Plan: Pace Line for Claude Code Usage

## Context

The Claude Code usage section in `templates/status.html.erb` displays two progress bars — **Weekly** (7-day) and **5-Hour** (session) — showing utilization as a filled bar with percentage. The user wants a thin vertical red "pace line" overlaid on each bar to indicate how far through the time period we are, so you can tell at a glance whether usage is ahead of or behind a linear pace.

**Example:** If 3.5 days of a 7-day week have elapsed, the pace line sits at 50% of the bar width. If the fill is at 30%, you're under pace (good). If the fill is at 70%, you're ahead of pace (burning through quota).

## Files to Modify

**1. `templates/status.html.erb`** — CSS, HTML, and JavaScript changes (single file)

No backend changes needed. The `resets_at` timestamp is already provided by the API and exposed to both ERB and JavaScript. The pace percentage can be computed entirely on the frontend from `resets_at` and the known period length.

## Implementation Steps

### Step 1: Add pace calculation helper (ERB, ~line 439)

Add a Ruby lambda alongside the existing `cc_fill` and `cc_reset` helpers:

```ruby
# pace_pct: how far through the period we are (0-100)
# period_secs: 604800 for weekly (7 days), 18000 for 5-hour session
cc_pace = ->(iso, period_secs) {
  return nil unless iso
  t = Time.parse(iso)
  elapsed = period_secs - (t - Time.now)
  pct = (elapsed / period_secs.to_f) * 100
  pct.clamp(0, 100)
}
```

### Step 2: Add CSS for the pace marker (~line 137, after `.claude-usage-bar .fill`)

Make `.claude-usage-bar` position: relative so the pace marker can be absolutely positioned inside it. Remove `overflow: hidden` so the marker's top/bottom overshoot can be visible (the fill still clips naturally via border-radius).

```css
.claude-usage-bar {
  flex: 1;
  height: 8px;
  background: #21262d;
  border-radius: 4px;
  overflow: hidden;         /* CHANGE to: overflow: visible */
  position: relative;       /* ADD */
}

.claude-usage-bar .fill {
  height: 100%;
  border-radius: 4px;
  transition: width 0.5s ease;
  /* ADD: ensure fill clips its own border-radius */
  overflow: hidden;
}

.claude-pace-marker {
  position: absolute;
  top: -2px;              /* extend 2px above bar */
  bottom: -2px;           /* extend 2px below bar */
  width: 2px;
  background: #f85149;    /* red */
  border-radius: 1px;
  transition: left 0.5s ease;
  z-index: 1;
  pointer-events: none;   /* don't interfere with hover/click */
}
```

Design notes:
- The marker is 2px wide, red (#f85149), and extends 2px above and below the 8px bar (total 12px tall) so it's clearly visible even when the fill reaches it.
- `pointer-events: none` keeps it non-interactive.
- `transition: left 0.5s ease` matches the fill animation timing.
- `z-index: 1` ensures it renders above the fill.

### Step 3: Add pace marker HTML elements (~lines 464-466, 472-474)

Inside each `.claude-usage-bar` div, add a pace marker sibling to the fill div:

**Weekly row (line 464):**
```erb
<div class="claude-usage-bar">
  <div class="fill <%= cc_fill.call(cc_weekly[:utilization]) %>" style="width: <%= cc_weekly[:utilization] %>%"></div>
  <% wp = cc_pace.call(cc_weekly[:resets_at], 604800) %>
  <div class="claude-pace-marker" style="left: <%= wp || 0 %>%<%= wp ? '' : '; display: none' %>"></div>
</div>
```

**Session row (line 472):**
```erb
<div class="claude-usage-bar">
  <div class="fill <%= cc_fill.call(cc_session[:utilization]) %>" style="width: <%= cc_session[:utilization] %>%"></div>
  <% sp = cc_pace.call(cc_session[:resets_at], 18000) %>
  <div class="claude-pace-marker" style="left: <%= sp || 0 %>%<%= sp ? '' : '; display: none' %>"></div>
</div>
```

### Step 4: Update JavaScript `updateRow` to refresh pace marker (~line 733)

Add a JavaScript pace calculation function and update `updateRow` to reposition the marker on each 15-second refresh:

```javascript
var ccPace = function(iso, periodSecs) {
  if (!iso) return null;
  var resetTime = new Date(iso).getTime();
  var now = Date.now();
  var elapsed = periodSecs * 1000 - (resetTime - now);
  var pct = (elapsed / (periodSecs * 1000)) * 100;
  return Math.max(0, Math.min(100, pct));
};
```

In `updateRow`, add pace marker update logic after the existing fill/pct/reset updates:

```javascript
function updateRow(rowId, obj, periodSecs) {
  var row = document.getElementById(rowId);
  if (!row) return;
  var fill = row.querySelector('.fill');
  var pct = obj ? obj.utilization : 0;
  fill.style.width = pct + '%';
  fill.className = 'fill ' + ccFill(pct);
  row.querySelector('.claude-usage-pct').textContent = Math.round(pct) + '%';
  row.querySelector('.claude-usage-reset').textContent = obj && obj.resets_at ? 'resets ' + ccReset(obj.resets_at) : '';
  // Pace marker
  var marker = row.querySelector('.claude-pace-marker');
  if (marker) {
    var pace = obj ? ccPace(obj.resets_at, periodSecs) : null;
    if (pace !== null) {
      marker.style.left = pace + '%';
      marker.style.display = '';
    } else {
      marker.style.display = 'none';
    }
  }
}
```

Update the two call sites to pass the period:
```javascript
updateRow('cc-weekly-row', data.claude_code.weekly, 604800);
updateRow('cc-session-row', data.claude_code.session, 18000);
```

And for the disconnected state:
```javascript
updateRow('cc-weekly-row', null, 604800);
updateRow('cc-session-row', null, 18000);
```

## Edge Cases

| Case | Behavior |
|------|----------|
| `resets_at` is null (disconnected) | Pace marker hidden (`display: none`) |
| Period just started (elapsed ≈ 0) | Marker at left edge (0%) |
| Period almost over (elapsed ≈ 100%) | Marker at right edge (100%) |
| `resets_at` is in the past (overdue reset) | Clamped to 100% |
| `resets_at` is far future (> period length away) | Clamped to 0% — should not happen in practice |
| Bar fill exceeds pace | Visual comparison makes it obvious usage is ahead of linear pace |
| Bar fill is behind pace | Visual comparison shows spare capacity — on track |
| Mobile/responsive | Marker uses percentage positioning, scales with bar width |

## Testing Strategy

1. **Visual verification:** Reload the dashboard and confirm a red vertical line appears on each usage bar at the expected position relative to the current time in the period.
2. **Math check:** If `resets_at` is ~3.5 days away for weekly, the marker should be at ~50%. Verify by inspecting the computed `left` style in browser dev tools.
3. **Auto-refresh:** Wait 15 seconds for the JavaScript auto-update and confirm the marker position updates smoothly (CSS transition).
4. **Disconnected state:** Stop the OAuth token (or simulate `{ available: false }`) and verify the pace marker is hidden.
5. **Edge of period:** Near the start or end of a period, confirm the marker is at ~0% or ~100% respectively and doesn't overflow the bar visually.
