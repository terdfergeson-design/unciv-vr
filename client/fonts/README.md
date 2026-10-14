# UI fonts

Noto Sans Regular, Noto Sans Arabic Regular and Noto Sans Hebrew Regular are bundled under the
SIL Open Font License 1.1 (see `OFL.txt`). Source: the Noto project's
[hinted TTF collection](https://github.com/notofonts/noto-fonts/tree/main/hinted/ttf).
The original font files are unmodified. `ui_font.tres` combines them for mixed-script text.
The existing Noto Sans font also provides Cyrillic and the additional Latin letters used by Russian,
Ukrainian, Czech, Hungarian, Romanian, Croatian, Catalan, Galician, Norwegian and Esperanto.
These languages do not require another bundled font.

Japanese, Chinese and Korean use **Noto Sans CJK JP Regular**, unmodified, from the Noto project's
[Japanese OTF collection](https://github.com/notofonts/noto-cjk/tree/main/Sans/OTF/Japanese).
Its SIL Open Font License 1.1 is included separately as `OFL-CJK.txt` and in both exports.
The full font supports kana, Han characters, Hangul and CJK punctuation in frontend and engine text,
including player names, without depending on the headset's installed fonts.
It is the full language-specific OTF, not the Japanese-only subset. Noto documents that these fonts
include other CJK languages' glyphs and regional forms via language tagging and OpenType `locl`:
[Noto CJK deployment guide](https://github.com/notofonts/noto-cjk/blob/main/Sans/README.md#language-specific-otfs).
Godot's advanced text renderer uses HarfBuzz with the text language; the frontend registers distinct
`zh_CN` and `zh_TW` catalogs. Regional glyph appearance still needs in-game review.
No additional font binaries are required for the six latest languages. Vietnamese and Maltese use Noto Sans;
Toki Pona uses Latin spelling (sitelen Lasina), not sitelen pona glyphs.

Godot handles Arabic shaping and bidirectional text. Both desktop and Quest exports carry these fonts;
other scripts can still use system fallback fonts. The export presets include the license.
Parallel asset import is disabled because Godot 4.7 can crash when importing several fonts together.
