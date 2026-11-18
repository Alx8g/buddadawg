# App icon setup

## Status: no shipping-ready source art yet

`Brand/icon-concept.png` (1336×1280, opaque raster) is a **generated concept,
not an asset**. `docs/design/visual-language.md` ("Don't" section) and
`docs/roadmap-0.3.md` §4.1 both state it needs a vector redraw on the palette
(Icon Ink `#222222` background, Pat Cream `#FFEEA9`, Coat `#DF9838`–`#F6CB83`),
Apple icon-grid safe margins, and only then an iconset export — "a public
beta cannot ship the clipped raster concept." No `.icns` was generated from it
here; do not wire the raw PNG into the bundle.

## Once the icon exists (target: `Resources/AppIcon.icns`)

1. Produce the art as a square 1024×1024 master (PNG or SVG), then build the
   iconset and convert:

   ```sh
   mkdir -p /tmp/AppIcon.iconset
   # render each size into /tmp/AppIcon.iconset/icon_16x16.png … icon_512x512@2x.png
   # (sips can resample the master; iconutil needs the full set)
   iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
   ```

   Required `icon_*.png` names: `16x16`, `16x16@2x` (32), `32x32`,
   `32x32@2x` (64), `128x128`, `128x128@2x` (256), `256x256`,
   `256x256@2x` (512), `512x512`, `512x512@2x` (1024).

2. `scripts/bundle.sh` — add one line next to the other `cp` lines
   (after `cp Resources/butterdog.gif …`):

   ```sh
   cp Resources/AppIcon.icns "$APP/Contents/Resources/"
   ```

3. `scripts/bundle.sh` — add two keys inside the generated `Info.plist`
   heredoc (anywhere in the `<dict>`):

   ```xml
   <key>CFBundleIconFile</key><string>AppIcon</string>
   <key>CFBundleIconName</key><string>AppIcon</string>
   ```

   (`CFBundleIconName` alone is sufficient on modern macOS; including both is
   harmless and matches older conventions.)

4. Rebuild via `scripts/bundle.sh` and confirm Finder/Dock show the icon.
   The app is `LSUIElement` (menu-bar only), so the icon appears in Finder,
   Get Info, and wherever the bundle is shown — there is no Dock tile to check.
