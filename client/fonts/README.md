# UI fonts

Noto Sans Regular, Noto Sans Arabic Regular and Noto Sans Hebrew Regular are bundled under the
SIL Open Font License 1.1 (see `OFL.txt`). Source: the Noto project's
[hinted TTF collection](https://github.com/notofonts/noto-fonts/tree/main/hinted/ttf).
The original font files are unmodified. `ui_font.tres` combines them for mixed-script text.
The existing Noto Sans font also provides Cyrillic and the additional Latin letters used by Russian,
Ukrainian, Czech, Hungarian, Romanian, Croatian, Catalan, Galician, Norwegian and Esperanto.
These languages do not require another bundled font.

Japanese uses **Noto Sans CJK JP Regular**, unmodified, from the Noto project's
[Japanese OTF collection](https://github.com/notofonts/noto-cjk/tree/main/Sans/OTF/Japanese).
Its SIL Open Font License 1.1 is included separately as `OFL-CJK.txt` and in both exports.
The full font supports kana, kanji and Japanese punctuation in frontend and engine text,
including player names, without depending on the headset's installed fonts.

Godot handles Arabic shaping and bidirectional text. Both desktop and Quest exports carry these fonts;
other scripts can still use system fallback fonts. The export presets include the license.
Parallel asset import is disabled because Godot 4.7 can crash when importing several fonts together.
