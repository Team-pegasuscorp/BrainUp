class_name ShareCard
extends RefCounted

## Renders the end-of-round card shared from the results screen: wordmark,
## category, mode, big score and the streak, as a portrait PNG for messaging apps.

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")

const SIZE := Vector2i(720, 960)
const WORDMARK_PATH := "res://assets/ui/brainup_wordmark.png"


## Draws the card off-screen under `host` and returns the image (null if the
## renderer gave nothing back, e.g. headless).
static func render(host: Node, summary: Dictionary) -> Image:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(_build(summary))
	host.add_child(viewport)
	## Two frames: one to lay the containers out, one to draw them.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image


static func _build(summary: Dictionary) -> Control:
	var category_id := str(summary.get("category_id", ""))
	var accent := UiTokens.accent_for_category(category_id)
	var mode := str(summary.get("mode", "classic"))

	var root := ColorRect.new()
	root.color = UiTokens.BRAND_BG
	root.size = Vector2(SIZE)

	var margin := MarginContainer.new()
	margin.size = Vector2(SIZE)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	root.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	margin.add_child(column)

	var wordmark := TextureRect.new()
	wordmark.texture = GameAssets.load_texture(WORDMARK_PATH)
	wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wordmark.custom_minimum_size = Vector2(0, 90)
	column.add_child(wordmark)

	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 14)
	column.add_child(header)
	header.add_child(GameAssets.make_circular_icon_display(GameAssets.category_texture(category_id), "🧠", 64.0))
	var category_label := _label(_category_name(category_id), 34, Color(1, 1, 1, 0.95))
	## Inside an HBox a wrapping label has no width and breaks after every letter.
	category_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(category_label)

	var mode_chip := _label(_mode_title(summary, mode), 22, accent)
	mode_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(mode_chip)

	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiStyle.card(accent, 36))
	column.add_child(card)
	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 10)
	card.add_child(inner)

	var score_caption := _label(tr_key("UI_FINAL_SCORE").to_upper(), 20, UiTokens.INK_MUTED)
	score_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(score_caption)
	var score := _label(str(int(summary.get("score", 0))), 120, accent)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(score)

	var details := _label("%s   ·   %s" % [
		tr_key("UI_SHARE_CORRECT").format({"correct": int(summary.get("correct_count", 0)), "total": int(summary.get("total_count", 0))}),
		tr_key("UI_SHARE_COMBO").format({"combo": int(summary.get("max_combo", 0))}),
	], 26, UiTokens.INK)
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(details)

	var streak := DayStreak.current()
	if streak >= 2:
		var streak_label := _label(tr_key("UI_SHARE_STREAK").format({"days": streak}), 26, Color(1.0, 0.55, 0.15))
		streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(streak_label)

	var footer := _label(tr_key("UI_SHARE_CHALLENGE"), 30, Color(1, 1, 1, 0.9))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)
	return root


## Title line under the category: mode name, plus "new record" or "daily challenge".
static func _mode_title(summary: Dictionary, mode: String) -> String:
	var name := tr_key("UI_MODE_CLASSIC")
	if mode == "survival":
		name = tr_key("UI_MODE_SURVIVAL")
	elif mode == "time_attack":
		name = tr_key("UI_MODE_TIME_ATTACK")
	if bool(summary.get("is_daily", false)):
		name = tr_key("UI_DAILY_CHALLENGE_TITLE")
	if bool((summary.get("record", {}) as Dictionary).get("is_record", false)):
		name += "  ·  " + tr_key("UI_RESULTS_NEW_RECORD")
	return name.to_upper()


## Text shared along with the image (and the clipboard fallback).
static func message(summary: Dictionary) -> String:
	var text := tr_key("UI_SHARE_MESSAGE").format({
		"score": int(summary.get("score", 0)),
		"category": _category_name(str(summary.get("category_id", ""))),
	})
	var streak := DayStreak.current()
	if streak >= 2:
		text += " " + tr_key("UI_SHARE_STREAK").format({"days": streak})
	return text + " " + tr_key("UI_SHARE_CHALLENGE")


static func _category_name(category_id: String) -> String:
	for category in QuestionLoaderScript.get_categories(LocaleManager.get_content_locale()):
		if str(category.get("id", "")) == category_id:
			return str(category.get("name", category_id))
	return category_id


static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


## Static helpers have no tr(): go through the TranslationServer.
static func tr_key(key: String) -> String:
	return TranslationServer.translate(key)
