# Frontend translations

The client uses Godot gettext catalogs. All twenty-four catalogs cover frontend menus, settings, city management,
research, policies, diplomacy, trade, religion, victory and replay, empire overview, built-in panels and appearance
options, controller hints, tutorials and status messages. Each has 1,036 messages, ready for wording review.

| Language | Catalog | Picker label |
| --- | --- | --- |
| German | `de.po` | Deutsch |
| Arabic | `ar.po` | العربية |
| Hebrew | `he.po` | עברית |
| Spanish | `es.po` | Español |
| French | `fr.po` | Français |
| Italian | `it.po` | Italiano |
| Brazilian Portuguese | `pt_BR.po` | Português (Brasil) |
| Swedish | `sv.po` | Svenska |
| European Portuguese | `pt_PT.po` | Português (Portugal) |
| Dutch | `nl.po` | Nederlands |
| Polish | `pl.po` | Polski |
| Turkish | `tr.po` | Türkçe |
| Indonesian | `id.po` | Bahasa Indonesia |
| Japanese | `ja.po` | 日本語 |
| Russian | `ru.po` | Русский |
| Ukrainian | `uk.po` | Українська |
| Czech | `cs.po` | Čeština |
| Hungarian | `hu.po` | Magyar |
| Romanian | `ro.po` | Română |
| Croatian | `hr.po` | Hrvatski |
| Catalan | `ca.po` | Català |
| Galician | `gl.po` | Galego |
| Norwegian | `nb.po` | Norsk |
| Esperanto | `eo.po` | Esperanto |

The first fourteen catalogs reuse matching translations from this checkout's Unciv catalogs;
the remaining entries are AI-assisted drafts. Each has all 1,036 entries filled. Native-speaker and in-game
layout review remain pending beyond the spot checks below.
The latest five drafts use existing engine catalogs listed as Portuguese 95%, Dutch 97%, Polish 98%,
Turkish 97% and Indonesian 99% in this checkout. European Portuguese adapts the Brazilian draft with
European wording and native engine terms; its separate `pt_PT` catalog does not replace `pt_BR`.

Japanese also reuses Unciv's existing terms and game-content catalog (96% in this checkout), with draft
VR-specific wording. It bundles the full Noto Sans CJK JP font for kana, kanji and punctuation on both platforms.
Japanese had a desktop spot check of settings, kana input, city production and research on 2026-10-13.
No missing glyphs or major layout issues were observed there; some compact city controls had tight labels.
Native-speaker and Quest review remain pending.

### Ten additional language drafts

Russian, Ukrainian, Czech, Hungarian, Romanian, Croatian, Catalan, Galician, Norwegian and Esperanto each
have all 1,036 frontend entries filled. Matching terms come from the existing Unciv catalogs. Other text was
drafted with Google Translate, followed by AI-assisted corrections to recurring gameplay terms, counters,
keyboard labels and menu wording. These are draft translations, not native-speaker-approved translations.
Formatting arguments and template fields are preserved; the canonical editable files are the `.po` catalogs.
No additional engine translations were added in this pass.

The game-content percentages in this checkout are Russian 99%, Ukrainian 97%, Czech 80%, Hungarian 99%,
Romanian 75%, Croatian 95%, Catalan 99%, Galician 99%, Norwegian 75% and Esperanto 98%.
Those percentages describe Unciv content, not the filled frontend entries. Missing game content still falls back
to English. Norwegian uses Godot's Bokmål locale `nb` while retaining the engine language name `Norwegian`;
inherited Unciv wording can include Nynorsk forms.

These ten languages have not yet had a Godot visual check, Quest check or native-speaker review.
In particular, long explanations, grammatical agreement around numbers and controller instructions need review.

Choose **Settings > Gameplay > Language**. The Latin-script languages, Russian, Ukrainian and Japanese use Unciv's existing game-content
catalogs as well. Arabic and Hebrew
now load draft native Unciv catalogs through the bridge; blank entries still fall back to English. See
[content coverage and upstream review notes](CONTENT.md). Picker percentages describe Unciv's content catalog,
not frontend coverage. No game identifiers or saved names are changed.

## Adding a language

Copy a catalog, retain its English `msgid` strings, update the `Language` and `Plural-Forms` headers, and translate
each `msgstr`. Preserve formatting placeholders (`%s`, `%d`, `%+d`, `%%`) and template field names (`{count}`, `{leader}`,
`{era}`). Register it in `internationalization/locale/translations` in `project.godot` and `Lang.FRONTEND_LANGUAGES`.
`Lang.apply()` merges matching catalogs with Unciv's dictionary; frontend wording takes precedence. Frontend
languages missing from the bridge's language list automatically use English in the engine.
Regional catalogs only merge for their matching region (`pt_BR` does not replace `pt_PT`);
generic catalogs such as `fr` work for that language's regions. Source catalogs are removed from the global
translation lookup when merging so Godot cannot select a different region as a fallback.

Keep plain Label/Button/Label3D text in English for automatic language switching. Use `Lang.format()` for assembled
messages, `Lang.join()` for lists and `Lang.t()` for fragments. Never translate identifiers in commands, icons,
callbacks, saved data or ruleset lookups. `Panels.display()` translates display templates; `Panels.fill()` remains raw.

## Right-to-left support

Godot mirrors normal containers and shapes Arabic/Hebrew text. Do not reverse strings. Bundled Noto fonts support
mixed Latin/Arabic/Hebrew text on desktop and Quest. Their license is included in both export presets.

`Lang.display_value()` isolates inserted display names with Unicode FSI/PDI. Numeric expressions in RTL catalogs use
LRI/PDI so signs, fractions and percentages keep their order. Preserve these invisible characters when editing.
Count labels use neutral wording instead of assuming English singular/plural rules; panel turn counts use `Turns: %s`.

Custom tree and politics diagrams retain their shared coordinate system for nodes and drawn connectors. TreeCanvas
reapplies stored child positions after entering the scene tree, since detached controls may compute mirrored offsets.
World coordinates, controller handedness, map geometry and physical keyboard key order do not mirror.

The VR keyboard offers Arabic/Hebrew and Russian/Ukrainian keys plus a Latin switch. Its LineEdit displays the native bidirectional caret;
text remains in logical order for saving. The Latin keyboard's accent row follows the selected language,
including Spanish ñ, French ligatures, Italian accents, Portuguese ç/ã/õ, Swedish å/ä/ö,
Dutch diacritics, Polish ąćęłńóśźż and Turkish çğıöşü. Turkish Shift uses i/İ and ı/I correctly.
Indonesian uses the base Latin rows without an extra accent row.
Japanese offers hiragana, small kana, punctuation and a hiragana/katakana toggle. The ゛ and ゜ keys modify
the previous kana as a single composed character; use the Latin toggle for numbers and Latin names.
There is no kanji conversion or Japanese IME integration in the VR keyboard; existing kanji names remain readable.
German letters remain the default accent row.
Russian includes ё and Ukrainian includes ґ, є, і, ї and apostrophes. Both use the existing one-shot Shift
behavior. The additional Latin rows cover Czech áčďéěíňóřšťúůýž, Hungarian áéíóöőúüű,
Romanian ăâîșț (comma-below forms), Croatian čćđšž, Catalan àçèéíïòóúü·,
Galician áéíóúüñ, Norwegian æøåé and Esperanto ĉĝĥĵŝŭ.

The five latest catalogs (European Portuguese, Dutch, Polish, Turkish and Indonesian) have not yet had
a Godot visual or native-speaker review. The earlier spot-check results below do not cover them.

## Checks and visual review

From the repository root, run Godot with:

```text
--headless --xr-mode off --path client --script res://tools/check_translations.gd
```

This checks the catalogs, placeholders, template counts, raw commands, mixed text, bundled font glyphs and
language switching. For visual review, select a language normally or pass `-- --language=Arabic` (or Hebrew/German).
The development override is not saved unless a language is explicitly selected.

For a read-only desktop check against an existing save:

```text
-- --language=Arabic --load=<save-path> --translation-check
```

It visits city production, the five main board tabs, diplomacy details, trade, all ten empire overview tabs,
keyboard and settings, then switches to English and back. Screenshots and `<language>-ui-review.json` are saved
under `build/`. Review wording and clipping on the headset too; a desktop check does not verify Quest appearance.

### French and Brazilian Portuguese spot checks

On 2026-10-13, both languages were checked in desktop Godot: Appearance, Gameplay, and the save-name
keyboard, including a live French-to-Brazilian-Portuguese switch and accented input/backspace.
Screenshots were visually reviewed at 1600×900. Corrected Portuguese Tiles/Rankings and clarified French
Gameplay/Clear labels, then repeated the checks successfully. No script errors; OpenXR reported no headset
and used desktop mode. No game orders or saves were issued. This does not constitute full UI or Quest review.

To repeat this short review, load a save with `--translation-check --translation-spot-check --language=French`.
Screenshots and text captures are written to `build/french-spot-*` and `build/brazilian_portuguese-spot-*`.

### Spanish, Italian and Swedish spot checks

On 2026-10-13, the same desktop Appearance, Gameplay and save-name keyboard checks passed for
Spanish, Italian and Swedish, including live language switching and accented input/backspace.
All nine screenshots were visually reviewed at 1600×900; no clipping in the checked menus or missing
accent glyphs was found. Aligned the Italian Gameplay label and Spanish/Swedish tutorial navigation
wording, then repeated the checks successfully. No script errors; Quest remains untested.
Use `--spot-languages=Spanish,Italian,Swedish` with the short-review flags above to repeat.
Screenshots and text captures are in `build/<language>-spot-*`.

### Arabic gameplay spot check

On 2026-10-13, reviewed desktop unit actions, city production, research and policies against an existing save.
Filled missing core unit-action translations and translated client-added action titles before appending targeting
ellipses. No game orders, turns or saves were issued. Some building/research description fragments remain English;
the units-needing-orders button and unit rename label clip, and engine/frontend digit styles differ.
This is a limited visual check, not native-speaker approval or Quest verification.
Repeat with `--language=Arabic --load=<save-path> --translation-check --translation-gameplay-check`.
The four screenshots and a review guide are packaged in `build/UncivVR-Arabic-review-2026-10-13.zip`.
