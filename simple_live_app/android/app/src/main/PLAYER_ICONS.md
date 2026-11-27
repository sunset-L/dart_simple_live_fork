# Native player icon fonts

The fonts in `assets/player_icons` are subsets for `NativeIcons.kt`, not the
full Flutter icon fonts. Keep every `Pair(material, ...)` and `Pair(remix, ...)`
codepoint, including the default icon and the entries now handled by vectors.

When adding a codepoint, regenerate both subsets with the pinned Flutter SDK's
`font-subset` executable (`bin/cache/artifacts/engine/windows-x64/font-subset.exe`
on Windows). Use the full font blobs at commit `caa6fc9` in this same asset
directory, not the existing subsets. Run `font-subset <output> <full-font>` and
feed the corresponding space-separated codepoints on one line via stdin.
Keep the asset filenames and license files unchanged, and verify the selected
glyphs' outlines and metrics against the full fonts before replacing the assets.
