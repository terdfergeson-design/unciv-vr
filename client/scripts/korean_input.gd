# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## Composes modern Hangul from the on-screen two-set keyboard's compatibility jamo.
## The caller keeps committed text separate and records keystrokes for backspace.
const LEADS := "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
const VOWELS := "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
const TAILS := " ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ"
const DOUBLE_VOWELS := {
	"ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅘㅣ": "ㅙ",
	"ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅝㅣ": "ㅞ", "ㅡㅣ": "ㅢ",
}
const DOUBLE_TAILS := {
	"ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ",
	"ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ",
	"ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ",
}
const SHIFTED := {"ㅂ": "ㅃ", "ㅈ": "ㅉ", "ㄷ": "ㄸ", "ㄱ": "ㄲ", "ㅅ": "ㅆ", "ㅐ": "ㅒ", "ㅔ": "ㅖ"}


static func is_jamo(character: String) -> bool:
	return character.length() == 1 and (LEADS.contains(character) or VOWELS.contains(character))


static func _syllable(lead: int, vowel: int, tail := 0) -> String:
	return String.chr(0xAC00 + (lead * 21 + vowel) * 28 + tail)


static func append(buffer: String, character: String) -> String:
	if buffer.is_empty() or not is_jamo(character):
		return buffer + character
	var previous := buffer.right(1)
	var prefix := buffer.left(buffer.length() - 1)
	var vowel := VOWELS.find(character)
	var lead := LEADS.find(previous)
	if lead >= 0 and vowel >= 0:
		return prefix + _syllable(lead, vowel)
	if vowel >= 0 and VOWELS.contains(previous):
		var combined: String = DOUBLE_VOWELS.get(previous + character, "")
		if not combined.is_empty():
			return prefix + combined
	var code := previous.unicode_at(0) - 0xAC00
	if code < 0 or code >= 11172:
		return buffer + character
	var old_lead := int(code / 588)
	var old_vowel := int((code % 588) / 28)
	var old_tail := code % 28
	if vowel >= 0:
		if old_tail == 0:
			var combined: String = DOUBLE_VOWELS.get(VOWELS[old_vowel] + character, "")
			if not combined.is_empty():
				return prefix + _syllable(old_lead, VOWELS.find(combined))
		else:
			# A following vowel moves the final consonant to the next syllable.
			var moving := TAILS[old_tail]
			var remaining := 0
			for pair: String in DOUBLE_TAILS:
				if DOUBLE_TAILS[pair] == moving:
					remaining = TAILS.find(pair[0])
					moving = pair[1]
					break
			var next_lead := LEADS.find(moving)
			if next_lead >= 0:
				return prefix + _syllable(old_lead, old_vowel, remaining) + _syllable(next_lead, vowel)
	else:
		var tail := TAILS.find(character)
		if old_tail == 0 and tail > 0:
			return prefix + _syllable(old_lead, old_vowel, tail)
		var combined: String = DOUBLE_TAILS.get(TAILS[old_tail] + character, "")
		if not combined.is_empty():
			return prefix + _syllable(old_lead, old_vowel, TAILS.find(combined))
	return buffer + character
