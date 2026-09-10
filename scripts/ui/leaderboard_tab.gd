## Leaderboard tab page. Edit this script and `scenes/tabs/leaderboard_tab.tscn` only.
extends Control

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const LeaderboardSnapshot = preload("res://scripts/profile/leaderboard_snapshot.gd")

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var filter_row: HBoxContainer = %FilterRow
@onready var scroll: ScrollContainer = %Scroll
@onready var content: VBoxContainer = %Content
@onready var demo_hint_label: Label = %DemoHintLabel

var _selected_filter: String = "all"
var _filter_buttons: Array[Button] = []
var _online_entries_by_category: Dictionary = {}


func _ready() -> void:
	_apply()
	LocaleManager.locale_changed.connect(_on_locale_changed)
	NetworkManager.leaderboard_received.connect(_on_leaderboard_received)
	NetworkManager.leaderboard_failed.connect(_on_leaderboard_failed)


func on_tab_shown() -> void:
	_apply()


func _apply() -> void:
	title_label.text = tr("UI_TAB_LEADERBOARD")
	_rebuild_filters()
	_rebuild_board()


func _rebuild_filters() -> void:
	for child in filter_row.get_children():
		child.queue_free()
	_filter_buttons.clear()

	for filter in LeaderboardSnapshot.available_filters(LocaleManager.get_content_locale()):
		var filter_id := str(filter.get("id", "all"))
		var button := Button.new()
		button.text = str(filter.get("label", filter_id))
		button.custom_minimum_size.y = 40
		button.pressed.connect(_on_filter_pressed.bind(filter_id))
		filter_row.add_child(button)
		_filter_buttons.append(button)

	_selected_filter = _normalize_selected_filter()
	_update_filter_styles()


func _rebuild_board() -> void:
	var online_entries: Variant = _online_entries_by_category.get(_selected_filter)
	if online_entries != null:
		_render_snapshot(_snapshot_from_online(online_entries))
	else:
		_render_snapshot(LeaderboardSnapshot.build(_selected_filter, LocaleManager.get_content_locale()))
	NetworkManager.fetch_leaderboard(_selected_filter)


func _on_leaderboard_received(category: String, entries: Array) -> void:
	_online_entries_by_category[category] = entries
	if category == _selected_filter:
		_render_snapshot(_snapshot_from_online(entries))


func _on_leaderboard_failed(_category: String) -> void:
	pass # backend injoignable : le classement local/démo déjà affiché reste en place


func _snapshot_from_online(entries: Array) -> Dictionary:
	var built: Array[Dictionary] = []
	for raw in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var is_player := not NetworkManager.player_id.is_empty() \
			and str(raw.get("player_id", "")) == NetworkManager.player_id
		built.append({
			"id": str(raw.get("player_id", "")),
			"name": str(raw.get("display_name", "")),
			"score": int(raw.get("score", 0)),
			"level": 1,
			"rank_title_key": "UI_RANK_ROOKIE",
			"is_player": is_player,
			"rank": int(raw.get("rank", 0)),
		})

	var player_rank := 0
	for entry in built:
		if entry.get("is_player", false):
			player_rank = int(entry.get("rank", 0))
			break

	var podium: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for index in range(built.size()):
		if index < 3:
			podium.append(built[index])
		else:
			rest.append(built[index])

	return {
		"entries": built,
		"podium": podium,
		"rest": rest,
		"player_rank": player_rank,
		"is_demo": false,
		"filter": _selected_filter,
	}


func _render_snapshot(snapshot: Dictionary) -> void:
	for child in content.get_children():
		child.queue_free()

	var player_rank := int(snapshot.get("player_rank", 0))
	if player_rank > 0:
		subtitle_label.text = tr("UI_LEADERBOARD_YOUR_RANK").format({"rank": player_rank})
	else:
		subtitle_label.text = tr("UI_LEADERBOARD_NO_RANK")

	demo_hint_label.visible = snapshot.get("is_demo", false)
	demo_hint_label.text = tr("UI_LEADERBOARD_DEMO_HINT")

	var podium: Array = snapshot.get("podium", [])
	if not podium.is_empty():
		content.add_child(_make_podium(podium))

	var rest: Array = snapshot.get("rest", [])
	for entry in rest:
		if typeof(entry) == TYPE_DICTIONARY:
			content.add_child(_make_rank_row(entry))

	if podium.is_empty() and rest.is_empty():
		content.add_child(_make_empty_label(tr("UI_LEADERBOARD_EMPTY")))


func _make_podium(podium: Array) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 8)

	var caption := Label.new()
	caption.text = tr("UI_LEADERBOARD_PODIUM")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 13)
	caption.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	wrapper.add_child(caption)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	wrapper.add_child(row)

	var slots: Array[Dictionary] = []
	if podium.size() >= 2:
		slots.append(podium[1])
	if podium.size() >= 1:
		slots.append(podium[0])
	if podium.size() >= 3:
		slots.append(podium[2])

	var heights := [92.0, 120.0, 80.0]
	var accents := [
		Color(0.72, 0.78, 0.86, 1),
		UiTokens.ACCENT_LEADERBOARD,
		Color(0.85, 0.62, 0.42, 1),
	]
	for slot_index in range(slots.size()):
		var entry: Dictionary = slots[slot_index]
		row.add_child(_podium_card(
			entry,
			heights[slot_index],
			accents[slot_index],
			int(entry.get("rank", slot_index + 1))
		))

	return wrapper


func _podium_card(entry: Dictionary, height: float, accent: Color, rank: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(104, height)
	panel.size_flags_vertical = Control.SIZE_SHRINK_END
	var is_player: bool = bool(entry.get("is_player", false))
	panel.add_theme_stylebox_override(
		"panel",
		UiStyle.profile_surface(UiTokens.ACCENT_LEADERBOARD, true, 0) if is_player else UiStyle.profile_surface(accent, false, 0)
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var rank_label := Label.new()
	rank_label.text = "#%d" % rank
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", 14)
	rank_label.add_theme_color_override("font_color", accent)
	vbox.add_child(rank_label)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(40, 40)
	avatar.add_theme_stylebox_override("panel", UiStyle.filled_disc(accent, 20))
	var initial := Label.new()
	initial.text = str(entry.get("name", "?")).substr(0, 1)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_color_override("font_color", Color.WHITE)
	initial.add_theme_font_size_override("font_size", 18)
	avatar.add_child(initial)
	vbox.add_child(avatar)

	var name_label := Label.new()
	name_label.text = str(entry.get("name", ""))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", UiTokens.PSEUDO_FONT_SIZE)
	name_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(name_label)

	var score_label := Label.new()
	score_label.text = str(entry.get("score", 0))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 20)
	score_label.add_theme_color_override("font_color", accent)
	vbox.add_child(score_label)

	return panel


func _make_rank_row(entry: Dictionary) -> PanelContainer:
	var is_player: bool = bool(entry.get("is_player", false))
	var accent: Color = UiTokens.ACCENT_LEADERBOARD if is_player else UiTokens.PROFILE_TEXT_MUTED
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel",
		UiStyle.profile_surface(UiTokens.ACCENT_LEADERBOARD, true, 0) if is_player else UiStyle.profile_surface(UiTokens.ACCENT_LEADERBOARD, false, 0)
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var rank := Label.new()
	rank.custom_minimum_size.x = 36
	rank.text = "#%d" % int(entry.get("rank", 0))
	rank.add_theme_font_size_override("font_size", 16)
	rank.add_theme_color_override("font_color", accent)
	row.add_child(rank)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(44, 44)
	avatar.add_theme_stylebox_override("panel", UiStyle.filled_disc(accent, 22))
	var initial := Label.new()
	initial.text = str(entry.get("name", "?")).substr(0, 1)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_color_override("font_color", Color.WHITE)
	avatar.add_child(initial)
	row.add_child(avatar)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name := Label.new()
	name.text = str(entry.get("name", ""))
	if is_player:
		name.text += " (%s)" % tr("UI_LEADERBOARD_YOU")
	name.add_theme_font_size_override("font_size", UiTokens.PSEUDO_FONT_SIZE)
	name.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	info.add_child(name)

	var meta := Label.new()
	meta.text = tr("UI_LEADERBOARD_ROW_META").format({
		"rank_title": tr(str(entry.get("rank_title_key", "UI_RANK_ROOKIE"))),
		"level": entry.get("level", 1),
	})
	meta.add_theme_font_size_override("font_size", 12)
	meta.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	info.add_child(meta)

	var score := Label.new()
	score.text = str(entry.get("score", 0))
	score.add_theme_font_size_override("font_size", 22)
	score.add_theme_color_override("font_color", UiTokens.ACCENT_LEADERBOARD)
	row.add_child(score)

	return panel


func _make_empty_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	return label


func _on_filter_pressed(filter_id: String) -> void:
	_selected_filter = filter_id
	_update_filter_styles()
	_rebuild_board()


func _update_filter_styles() -> void:
	var filters := LeaderboardSnapshot.available_filters(LocaleManager.get_content_locale())
	for index in range(_filter_buttons.size()):
		if index >= filters.size():
			break
		var button := _filter_buttons[index]
		var filter_id := str(filters[index].get("id", "all"))
		button.set_meta("filter_id", filter_id)
		var selected := filter_id == _selected_filter
		var normal := UiStyle.profile_chip(UiTokens.ACCENT_LEADERBOARD, selected)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", normal)
		button.add_theme_stylebox_override("pressed", UiStyle.profile_chip(UiTokens.ACCENT_LEADERBOARD, true))
		button.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
		button.add_theme_color_override("font_hover_color", UiTokens.PROFILE_TEXT)
		button.add_theme_color_override("font_pressed_color", UiTokens.PROFILE_TEXT)


func _normalize_selected_filter() -> String:
	var filters := LeaderboardSnapshot.available_filters(LocaleManager.get_content_locale())
	for filter in filters:
		if str(filter.get("id", "")) == _selected_filter:
			return _selected_filter
	_selected_filter = "all"
	return _selected_filter


func _on_locale_changed(_locale: String) -> void:
	_apply()
