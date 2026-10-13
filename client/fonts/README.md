# UI fonts

Noto Sans Regular, Noto Sans Arabic Regular and Noto Sans Hebrew Regular are bundled under the
SIL Open Font License 1.1 (see `OFL.txt`). Source: the Noto project's
[hinted TTF collection](https://github.com/notofonts/noto-fonts/tree/main/hinted/ttf).
The original font files are unmodified. `ui_font.tres` combines them for mixed-script text.

Godot handles Arabic shaping and bidirectional text. Both desktop and Quest exports carry these fonts;
other scripts can still use system fallback fonts. The export presets include the license.
Parallel asset import is disabled because Godot 4.7 can crash when importing several fonts together.
