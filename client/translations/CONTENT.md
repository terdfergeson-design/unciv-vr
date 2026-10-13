# Arabic and Hebrew game-content drafts

The canonical catalogs live in the Unciv submodule:

- `unciv/android/assets/jsons/translations/Arabic.properties`
- `unciv/android/assets/jsons/translations/Hebrew.properties`

These are AI-assisted drafts for native-speaker review, not reviewed upstream translations.
They use Unciv's normal UTF-8 `English key = translation` format. Edit these files directly.
The frontend `.po` files remain separate and take precedence for matching client labels.

## Coverage — 2026-10-13

Arabic has 1,710 filled entries out of 6,544 scaffold entries; Hebrew has 1,700 out of 6,542
(including 10 language settings). The picker shows Arabic 26% and Hebrew 25%, rounded down using Unciv's convention of excluding
`ConditionalsOrder` from the denominator. This is whole-catalog coverage, not the percentage
of text seen in a typical VR game. The scaffold uses this checkout's German catalog plus
any additional manual-template keys; no German values were copied.

Included in both languages:

- Built-in building, wonder and technology names (their quotations are still pending).
- Complete generated unit, unit type, promotion, policy, belief, terrain, improvement,
  resource, difficulty and era sections for Vanilla and Gods & Kings.
- All 570 shared unique-effect templates, including conditional clauses and triggers.
- Filters, city qualifiers, spies' actions, countable expressions and leader titles.
- Major civilization and leader names, plus overlapping frontend vocabulary.

Still pending: most city and great-person names, civilization dialogue and ability names,
quotations, engine notifications and UI sentences, diplomatic modifiers, events and tutorials.
Blank values are marked `# Requires translation!`; Unciv falls back to English. Do not fill
these with copies of the English key merely to increase completion. Partial sentences can
still mix languages where their component words have not been translated.

## Review conventions

- Keep English keys and every `[placeholder]` unchanged, including spelling and case.
- Preserve literal `\n` for line breaks. Keep translations on one physical line.
- Write normal logical Unicode text. Godot supplies shaping, bidi and fonts; do not reverse
  strings, substitute presentation-form glyphs or insert renderer-specific private-use codes.
- Check terminology against the frontend catalogs, especially happiness, faith, city-states,
  great people, promotions and puppet cities. Generic fragments may need grammatical revision
  when composed with different units, resources and numbers.
- Check proper names against established Arabic/Hebrew usage. Quotations should be translated
  from the supplied source, not copied from copyrighted modern editions.

## Using and contributing

Select Arabic or Hebrew in Settings > Gameplay > Language. The bridge loads the native
catalog and returns translated descriptions plus a name dictionary to Godot. Restart a
running bridge after editing a catalog because translations are cached in memory.

Both locales remain `unused` in stock Unciv's locale list; the bridge explicitly exposes
them to its RTL-capable frontend. This checkout's Unciv translation documentation says
its stock renderer does not support RTL. Adding a catalog does not resolve that limitation.

Before proposing an upstream contribution:

1. Have native speakers review terminology, composed descriptions and proper names.
2. Regenerate against the target Unciv revision's translation template, updating completion
   percentages with its translation generator.
3. Discuss RTL rendering and language enablement with Unciv maintainers. Keep the catalog
   contribution separate from bridge-specific integration and Godot files.
4. Commit changes inside the Unciv submodule first, then record that commit in this repository.

Nothing has been submitted upstream. A limited Arabic desktop gameplay review covered unit actions,
city production, research and policies; some mixed-English descriptions and clipped labels remain.
Native-speaker review and Quest review of these content drafts are still pending.
