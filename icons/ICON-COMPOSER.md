# Making the `.icon` files in Icon Composer

Summon and Corners both ship an `AppIcon.appiconset` of PNGs rendered from the light
SVG. That format has no dark variant, so the Dock, Finder and Launchpad always show the
light icon. (The About windows already switch; they use a separate `AboutIcon` image set.)

An Icon Composer `.icon` file fixes that. It holds one icon with Default, Dark, Clear
and Tinted appearances plus Liquid Glass effects, and macOS picks the right one. Making
it takes a GUI app, so this part is yours. Wiring it into the projects afterwards is
mechanical; hand that back to Claude (checklist at the end).

> Written for Xcode 27.1's Icon Composer, without a click-through of the app, so
> labels and placement may differ a little. The steps are the general shape.

## Before you start

- **Open Icon Composer:** Xcode ▸ Open Developer Tool ▸ Icon Composer, or
  `/Applications/Xcode.app/Contents/Applications/Icon Composer.app`.
- **Use the layer files, not the full icon SVGs.** Icon Composer draws the rounded
  background itself and adds its own glass, shadow and highlights. The full SVGs bake in
  a background squircle and SVG filters (a drop shadow, a glow), which would double up.
  The layer files are just the artwork, at the same positions on the same 1024×1024
  canvas, so they line up when you drop them in:

  | App | Layer files | Colors in the files |
  |---|---|---|
  | Summon | `icons/layers/sparkle-large.svg`, `icons/layers/sparkles-small.svg` | Light |
  | Corners | `design/icon/layers/tile-primary.svg`, `design/icon/layers/tiles-secondary.svg` (in the Corners repo) | Light |

## Steps (Summon)

1. **New document.** Save it right away as `AppIcon.icon` in `Summon/`, next to
   `Assets.xcassets`. That's where the project expects it, and the name matches the
   current app icon name.
2. **Background.** Select the canvas/document and set its fill to a vertical gradient
   from `#F7F5FF` (top) to `#D9D1FB` (bottom). Don't import a background shape; the
   rounded square comes from the system.
3. **Layers.** Drag `sparkle-large.svg` in, then `sparkles-small.svg`. Put each in its own
   group. Groups are where the glass, shadow and translucency settings live, and separate
   groups let the big sparkle stand forward of the small ones.
4. **Effects.** Start with Liquid Glass on for both groups and the defaults for
   everything else, then adjust to taste. The old SVG drop shadow (soft violet, below the
   sparkles) maps to the group shadow. Try the colored ("chromatic") shadow option if it
   looks flat.
5. **Dark appearance.** Switch the preview/appearance to **Dark**. Changes made while Dark
   is selected apply to Dark only (check that Default still looks right afterwards):
   - Background gradient: `#25213A` (top) to `#0E0C18` (bottom).
   - Large sparkle fill: gradient `#C4B5FD` → `#F0ABFC`, top-left to bottom-right.
   - Small sparkles: `#E9D5FF` (the larger one, top right) and `#C4B5FD` (top left).
   - The dark SVG has a soft glow around the sparkles and a violet halo behind the large
     one. Icon Composer has no glow as such. A brighter or colored shadow, or a lighter
     background center, gets close. Or skip it: the About window already shows the dark
     icon without the glow, and you liked that.
6. **Clear and Tinted.** Flip through those previews. macOS derives them from your
   layers, so they usually need nothing. If the sparkles disappear in one, raise their
   opacity or contrast for that appearance.
7. **Save.**

## Steps (Corners)

Same flow, simpler artwork. Save as `Corners/AppIcon.icon` in the Corners repo.

1. **Background:** solid `#EEF7F3`.
2. **Layers:** `tile-primary.svg` and `tiles-secondary.svg`, each in its own group, so the
   lit tile can sit forward or glow a little differently from the other three.
3. **Effects:** flat tiles look best with subtle glass. Start low.
4. **Dark:** background `#0F1E1A`, lit tile `#3CC79C`, other tiles `#24493D`.
5. Check Clear and Tinted, then save.

## Then: wiring it up (hand this to Claude)

For each app:

- [ ] Add `AppIcon.icon` to the app target through `project.yml` (XcodeGen), and confirm
      XcodeGen treats it as an icon file rather than a folder.
- [ ] Keep `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`, which now points at the `.icon`.
- [ ] Remove `Assets.xcassets/AppIcon.appiconset` so the two don't share a name.
- [ ] `make install`, then check the Dock and Finder icon in light and dark mode.
- [ ] Keep the `AboutIcon` image set. It already handles the About window.
- [ ] Update the READMEs (the Icons section and the TODO about Icon Composer).
- [ ] For the App Store later: export a 1024×1024 PNG from Icon Composer.
