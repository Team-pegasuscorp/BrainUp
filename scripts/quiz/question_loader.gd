class_name QuestionLoader
extends RefCounted

const QUESTIONS_DIR: String = "res://data/questions/"
const CATEGORIES_PATH: String = "res://data/categories.json"


static func get_categories(locale: String) -> Array[Dictionary]:
	var parsed: Variant = _load_json(CATEGORIES_PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []

	var result: Array[Dictionary] = []
	for category_id in parsed.keys():
		var entry: Dictionary = parsed[category_id]
		var translations: Dictionary = entry.get("translations", {})
		var locale_block: Dictionary = translations.get(locale, translations.get("fr", {}))
		result.append({
			"id": category_id,
			"name": locale_block.get("name", category_id),
			"description": locale_block.get("description", ""),
			"locales": entry.get("locales", ["fr", "en"]),
		})

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("name", "") < b.get("name", "")
	)
	return result


static func load_questions_for_category(
	category_id: String,
	locale: String,
	count: int,
	seed_value: int = 0
) -> Array[Dictionary]:
	var localized := _load_localized(category_id, locale)
	if seed_value == 0:
		localized.shuffle()
	else:
		_seeded_shuffle(localized, seed_value)
	if count > 0 and localized.size() > count:
		return localized.slice(0, count)
	return localized


## Daily challenge: every player gets the same questions in the same order.
## Ordering is by SHA-256 of (seed + question id), not a shuffle of the localised
## list, so a question missing in one language cannot shift the others.
## (String.hash() is too regular for this: near-identical ids sort in id order.)
static func load_daily_questions(
	category_id: String,
	locale: String,
	count: int,
	seed_key: String
) -> Array[Dictionary]:
	var localized := _load_localized(category_id, locale)
	var keys := {}
	for question in localized:
		var question_id := str(question.get("id", ""))
		keys[question_id] = ("%s|%s" % [seed_key, question_id]).sha256_text()
	localized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(keys[str(a.get("id", ""))]) < str(keys[str(b.get("id", ""))])
	)
	if count > 0 and localized.size() > count:
		return localized.slice(0, count)
	return localized


static func _load_localized(category_id: String, locale: String) -> Array[Dictionary]:
	var path: String = "%s%s.json" % [QUESTIONS_DIR, category_id]
	var parsed: Variant = _load_json(path)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("QuestionLoader: invalid question file %s" % path)
		return []

	var localized: Array[Dictionary] = []
	for raw in parsed.get("questions", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var question: Dictionary = _localize_question(raw, locale)
		if not question.is_empty():
			localized.append(question)
	return localized


static func _seeded_shuffle(array: Array, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in range(array.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var tmp: Variant = array[index]
		array[index] = array[swap_index]
		array[swap_index] = tmp


static func _localize_question(raw: Dictionary, locale: String) -> Dictionary:
	var allowed_locales: Array = raw.get("locales", ["fr", "en"])
	if locale not in allowed_locales:
		return {}

	var translations: Dictionary = raw.get("translations", {})
	var locale_block: Dictionary = translations.get(locale, {})
	if locale_block.is_empty():
		for fallback in ["fr", "en"]:
			if translations.has(fallback):
				locale_block = translations[fallback]
				break

	if locale_block.is_empty():
		return {}

	var choices: Array = locale_block.get("choices", [])
	if choices.size() != 4:
		return {}

	return {
		"id": raw.get("id", ""),
		"category": raw.get("category", ""),
		"difficulty": int(raw.get("difficulty", 1)),
		"text": locale_block.get("text", ""),
		"choices": choices,
		"explanation": locale_block.get("explanation", ""),
		"correct_index": int(raw.get("correct_index", -1)),
	}


static func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("QuestionLoader: file not found %s" % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed
