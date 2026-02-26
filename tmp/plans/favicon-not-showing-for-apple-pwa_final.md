# Plan: Fix Favicon for Apple PWA

## Problem

The app has no Apple PWA support. Safari/iOS requires specific meta tags and a PNG icon for "Add to Home Screen" functionality. The current implementation only provides an SVG favicon via `<link rel="icon">`, which:

1. **Does not work as a home screen icon** - iOS requires `apple-touch-icon` in PNG format (not SVG)
2. **Missing PWA meta tags** - No `apple-mobile-web-app-capable`, status bar style, or app title meta tags
3. **No web app manifest** - No `manifest.json` for broader PWA support

## Context Analysis

### Current Favicon System
- **`lib/favicon_renderer.rb`**: Generates a dynamic SVG (Mac Mini shape with green/red status light)
- **`server.rb:95-105`**: Serves `/favicon.svg` endpoint with dynamic status
- **`server.rb:115-116`**: Redirects `/favicon.ico` to `/favicon.svg`
- **`templates/status.html.erb:7`**: Single `<link rel="icon" type="image/svg+xml" href="/favicon.svg">`
- **No static image files** exist in the project

### Key Constraint
Apple's `apple-touch-icon` **must be PNG** format. SVG is not supported. Since this is a pure Ruby server with no image processing libraries, we need a strategy to serve a PNG icon.

## Implementation Plan

### Step 1: Generate a static PNG apple-touch-icon

Create a static 180x180 PNG file for the apple-touch-icon. Since the home screen icon is captured at install time (it won't update dynamically), a static "green status" icon is the right choice.

**Approach**: Use macOS `sips` or `rsvg-convert` (if available) at development time to convert the SVG to PNG, or create the PNG manually. The simplest reliable method:

1. Write the SVG to a temp file
2. Use a one-time script to convert it to PNG (e.g., using `sips` via a wrapper, or a quick Ruby script using `open-uri` with an online converter, or just create the file with any image tool)
3. Save as `public/apple-touch-icon.png` (180x180)

**Alternative (no external tools needed)**: Encode a minimal PNG directly in Ruby. Since the icon is simple geometric shapes, we can create a small Ruby script that outputs a valid PNG using pure Ruby (chunky_png gem or a minimal inline PNG encoder). However, the simplest path is to just create the PNG file once as a static asset.

**Recommended**: Create a `public/` directory and add a pre-rendered `apple-touch-icon.png` (180x180). This can be generated from the existing SVG using any tool (browser dev tools, Inkscape, ImageMagick, etc.).

**File to create**: `public/apple-touch-icon.png`

### Step 2: Add a PNG icon renderer for server-side generation (alternative to static file)

If a dynamic icon is preferred (showing current status at install time), add a PNG generation approach:

**File to create**: `lib/png_icon_renderer.rb`

This module would:
- Render a minimal 180x180 PNG with the Mac Mini icon and status light
- Use pure Ruby to create a valid PNG (the icon is simple enough: rounded rectangles and circles with flat colors)
- Accept `all_ok` parameter like `FaviconRenderer`

**Note**: Pure-Ruby PNG generation for simple shapes is feasible but adds complexity. The static file approach (Step 1) is strongly recommended unless dynamic home screen icons are a hard requirement.

### Step 3: Add server routes for icon and manifest

**File to modify**: `server.rb`

Add routes before the default HTML route (before the `else` block):

1. **`/apple-touch-icon.png`** route - Serves the static PNG file from `public/apple-touch-icon.png` with `Content-Type: image/png`
2. **`/manifest.json`** route - Serves a JSON web app manifest (can be generated inline)

The manifest should include:
```json
{
  "name": "Mac Mini Status",
  "short_name": "Status",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#0d1117",
  "theme_color": "#0d1117",
  "icons": [
    {
      "src": "/apple-touch-icon.png",
      "sizes": "180x180",
      "type": "image/png"
    }
  ]
}
```

Add these route handlers in `server.rb`:
- After the `/favicon.ico` redirect (line 116) and before the `else` (line 117)
- `/apple-touch-icon.png`: Read and serve `public/apple-touch-icon.png` with appropriate headers
- `/manifest.json`: Generate and serve the manifest JSON

### Step 4: Add PWA meta tags to HTML template

**File to modify**: `templates/status.html.erb`

Add the following tags in the `<head>` section (after line 7):

```html
<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Mac Mini Status">
<meta name="theme-color" content="#0d1117">
<link rel="manifest" href="/manifest.json">
```

These tags enable:
- **`apple-touch-icon`**: Home screen icon on iOS
- **`apple-mobile-web-app-capable`**: Full-screen standalone mode when launched from home screen
- **`apple-mobile-web-app-status-bar-style`**: Dark status bar matching the app theme
- **`apple-mobile-web-app-title`**: App name on home screen
- **`theme-color`**: Browser chrome color (also used by Android)
- **`manifest`**: Web app manifest for broader PWA support

### Step 5: Update JavaScript favicon updater (optional enhancement)

**File to modify**: `templates/status.html.erb` (around line 677)

The existing JavaScript updates `link[rel="icon"]` on each refresh. No changes needed for PWA functionality, but ensure the selector doesn't accidentally match the apple-touch-icon link.

Current code already targets `link[rel="icon"]` specifically, which won't match `link[rel="apple-touch-icon"]`, so no changes required.

## Files Summary

| File | Action | Description |
|------|--------|-------------|
| `public/apple-touch-icon.png` | **Create** | Static 180x180 PNG icon (Mac Mini with green status light) |
| `server.rb` | **Modify** | Add routes for `/apple-touch-icon.png` and `/manifest.json` |
| `templates/status.html.erb` | **Modify** | Add apple-touch-icon, PWA meta tags, and manifest link |

## Implementation Order

1. Create `public/` directory and generate `apple-touch-icon.png` (180x180)
2. Add `/apple-touch-icon.png` route to `server.rb` (serve static file)
3. Add `/manifest.json` route to `server.rb` (inline JSON generation)
4. Add PWA meta tags to `templates/status.html.erb`
5. Test

## Testing Strategy

1. **Desktop Safari**: Load the page, verify favicon still works in the tab
2. **iOS Safari**:
   - Navigate to the status page
   - Tap Share > "Add to Home Screen"
   - Verify the Mac Mini icon appears in the add-to-home-screen dialog
   - Verify the icon appears on the home screen after adding
   - Tap the home screen icon and verify it launches in standalone mode (no Safari chrome)
3. **Manifest validation**: Navigate to `/manifest.json` directly, verify valid JSON with correct icon reference
4. **Icon endpoint**: Navigate to `/apple-touch-icon.png` directly, verify a valid PNG is served
5. **Existing favicon**: Verify `/favicon.svg` still works and the dynamic tab favicon still updates

## Edge Cases

- **Icon caching**: iOS aggressively caches home screen icons. During development/testing, may need to remove and re-add the PWA to see icon changes. Consider adding a version query param if needed.
- **Multiple icon sizes**: iOS primarily uses 180x180 for modern devices. Older devices may use 152x152 or 120x120. A single 180x180 icon will be downscaled automatically and should be sufficient for this use case.
- **Standalone mode navigation**: When launched as a PWA in standalone mode, there's no browser navigation bar. The app is a single-page dashboard with auto-refresh, so this should work fine. The log viewer modal and docker start button all work within the page.
- **HTTPS requirement**: PWA installation typically requires HTTPS. If the app is served over HTTP (e.g., through the SSH tunnel), the "Add to Home Screen" option may still appear but some PWA features may be limited. The apple-touch-icon itself works over HTTP.
- **File reading at startup vs per-request**: The static PNG should be read once at server startup and cached in memory, not read from disk on every request. This matches the app's performance-conscious design.
