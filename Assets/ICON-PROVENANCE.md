# Thruline Bible app icon — 0.22.0

The icon is a lit ivory cross standing above a winding path through dark hills: the path of
Scripture and the Church's reading of it leading to Christ, the throughline the app is named for.
Matt supplied the artwork (`AppIcon-source.png`) on 2026-10-31. `AppIcon-1024.png` is that
artwork cropped to its rounded square, masked to the macOS icon shape on a 1024-pixel canvas
with the standard 100-pixel margin and a soft shadow; the `AppIcon.iconset` sizes and
`AppIcon.icns` are scaled from it with `sips` and `iconutil`:

```
for s in 16 32 128 256 512; do
  sips -z $s $s AppIcon-1024.png --out AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) AppIcon-1024.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

Earlier marks (the Lectern **L** with a bookmark, and the Throughline **T** crossed by a copper
line) remain in Git history. Original project artwork is covered by the repository's MIT
license to the extent copyright applies.
