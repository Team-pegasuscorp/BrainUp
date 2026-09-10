## Social tab page. Edit this script and `scenes/tabs/social_tab.tscn` only.
extends Control

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")
const ScenePaths = preload("res://scripts/config/scene_paths.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")

@onready var content: VBoxContainer = %Content
@onready var message_label: Label = %MessageLabel

var _categories: Array[Dictionary] = []
var _selected_category_id: String = ""
var _current_challenge: Dictionary = {}
var _status_text: String = ""

var _live_state: String = "idle" # idle | searching | question | over
var _live_opponent_name: String = ""
var _live_my_score: int = 0
var _live_opponent_score: int = 0
var _live_question: Dictionary = {}
var _live_last_reveal: Dictionary = {}
var _live_answered: bool = false
var _live_countdown: float = 0.0
var _live_over_data: Dictionary = {}
var _countdown_label: Label = null

var _friend_backdrop: ColorRect
var _friend_detail_panel: PanelContainer
var _friend_detail_body: VBoxContainer
var _selected_friend: Dictionary = {}


func _ready() -> void:
	_ensure_friend_detail_overlay()
	_apply()
	LocaleManager.locale_changed.connect(_on_locale_changed)
	NetworkManager.challenge_created.connect(_on_challenge_created)
	NetworkManager.challenge_create_failed.connect(_on_challenge_create_failed)
	NetworkManager.challenge_joined.connect(_on_challenge_joined)
	NetworkManager.challenge_join_failed.connect(_on_challenge_join_failed)
	NetworkManager.challenge_fetched.connect(_on_challenge_fetched)
	NetworkManager.challenge_fetch_failed.connect(_on_challenge_fetch_failed)
	NetworkManager.live_match_found.connect(_on_live_match_found)
	NetworkManager.live_question.connect(_on_live_question)
	NetworkManager.live_reveal.connect(_on_live_reveal)
	NetworkManager.live_match_over.connect(_on_live_match_over)
	NetworkManager.live_error.connect(_on_live_error)


func _unhandled_input(event: InputEvent) -> void:
	if _friend_detail_panel != null and _friend_detail_panel.visible and event.is_action_pressed("ui_cancel"):
		_close_friend_detail()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _live_state != "question" or _live_answered:
		return
	_live_countdown = max(0.0, _live_countdown - _delta)
	if _countdown_label != null:
		_countdown_label.text = "%d" % ceili(_live_countdown)


func on_tab_shown() -> void:
	_apply()


func _apply() -> void:
	message_label.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	_categories = QuestionLoaderScript.get_categories(LocaleManager.get_content_locale())
	if _selected_category_id.is_empty() and not _categories.is_empty():
		_selected_category_id = str(_categories[0].get("id", ""))
	_rebuild_content()


func _rebuild_content() -> void:
	_close_friend_detail()
	for child in content.get_children():
		if child != message_label:
			child.queue_free()
	_countdown_label = null

	if _live_state != "idle":
		content.add_child(_live_section())
	elif _current_challenge.is_empty():
		content.add_child(_friends_section())
		content.add_child(_live_search_section())
		content.add_child(_create_section())
		content.add_child(_join_section())
	else:
		content.add_child(_friends_section())
		content.add_child(_challenge_card())

	if not _status_text.is_empty():
		var status := Label.new()
		status.text = _status_text
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.add_theme_font_size_override("font_size", 13)
		status.add_theme_color_override("font_color", UiTokens.INK_MUTED)
		content.add_child(status)

	message_label.text = tr("UI_SOCIAL_CHALLENGE_HINT")
	content.move_child(message_label, content.get_child_count() - 1)


func _friends_section() -> PanelContainer:
	## Friends added over time — first tile on Social when idle.
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 230
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 12))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_FRIENDS").to_upper()
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(caption)

	var friends := _get_friends()
	if friends.is_empty():
		var empty := Label.new()
		empty.text = tr("UI_SOCIAL_FRIENDS_EMPTY")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
		vbox.add_child(empty)
		return panel

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 152
	vbox.add_child(scroll)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(row)
	for friend in friends:
		if typeof(friend) != TYPE_DICTIONARY:
			continue
		row.add_child(_friend_chip(friend))
	return panel


func _friend_chip(friend: Dictionary) -> Control:
	const AVATAR := 76.0
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(100, 140)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(col)

	var accent: Color = friend.get("accent", UiTokens.ACCENT_SOCIAL)
	var avatar_wrap := Control.new()
	avatar_wrap.custom_minimum_size = Vector2(AVATAR, AVATAR)
	avatar_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var avatar := PanelContainer.new()
	avatar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc := UiStyle.filled_disc(accent, int(AVATAR * 0.5))
	disc.set_border_width_all(3)
	disc.border_color = Color(1, 1, 1, 0.88)
	avatar.add_theme_stylebox_override("panel", disc)
	var initial := Label.new()
	initial.text = str(friend.get("name", "?")).substr(0, 1).to_upper()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	initial.add_theme_font_size_override("font_size", 28)
	initial.add_theme_color_override("font_color", Color.WHITE)
	avatar.add_child(initial)
	avatar_wrap.add_child(avatar)

	## Presence dot (online / away / offline) for layout work.
	var presence := str(friend.get("presence", "offline"))
	var dot_color := Color(0.45, 0.48, 0.55, 1)
	match presence:
		"online":
			dot_color = Color(0.2, 0.86, 0.45, 1)
		"away":
			dot_color = Color(1.0, 0.72, 0.2, 1)
	var dot_size := 16.0
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(dot_size, dot_size)
	dot.position = Vector2(AVATAR - dot_size - 1.0, AVATAR - dot_size - 1.0)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = dot_color
	dot_style.set_corner_radius_all(int(dot_size * 0.5))
	dot_style.set_border_width_all(2)
	dot_style.border_color = UiTokens.SOCIAL_CARD_BG
	dot.add_theme_stylebox_override("panel", dot_style)
	avatar_wrap.add_child(dot)
	col.add_child(avatar_wrap)

	var name_label := Label.new()
	name_label.text = str(friend.get("name", ""))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", UiTokens.PSEUDO_FONT_SIZE)
	name_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	col.add_child(name_label)

	var level_label := Label.new()
	level_label.text = "Nv.%d" % int(friend.get("level", 1))
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.add_theme_font_size_override("font_size", 16)
	level_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	col.add_child(level_label)

	var hit := Button.new()
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	hit.add_theme_stylebox_override("normal", empty)
	hit.add_theme_stylebox_override("hover", empty)
	hit.add_theme_stylebox_override("pressed", empty)
	hit.add_theme_stylebox_override("focus", empty)
	var friend_copy: Dictionary = friend.duplicate(true)
	hit.pressed.connect(_open_friend_detail.bind(friend_copy))
	PressScaleUtil.wire(hit, self)
	wrap.add_child(hit)
	return wrap


func _ensure_friend_detail_overlay() -> void:
	if _friend_backdrop != null and is_instance_valid(_friend_backdrop):
		return

	_friend_backdrop = ColorRect.new()
	_friend_backdrop.visible = false
	_friend_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_friend_backdrop.color = Color(0, 0, 0, 0.45)
	_friend_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_friend_backdrop.gui_input.connect(_on_friend_backdrop_gui_input)
	add_child(_friend_backdrop)

	_friend_detail_panel = PanelContainer.new()
	_friend_detail_panel.visible = false
	_friend_detail_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_friend_detail_panel.offset_left = -186.0
	_friend_detail_panel.offset_top = -230.0
	_friend_detail_panel.offset_right = 186.0
	_friend_detail_panel.offset_bottom = 230.0
	_friend_detail_panel.add_theme_stylebox_override("panel", UiStyle.social_surface(true, 16))
	add_child(_friend_detail_panel)

	_friend_detail_body = VBoxContainer.new()
	_friend_detail_body.add_theme_constant_override("separation", 12)
	_friend_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_friend_detail_panel.add_child(_friend_detail_body)


func _open_friend_detail(friend: Dictionary) -> void:
	_ensure_friend_detail_overlay()
	_selected_friend = friend.duplicate(true)
	_populate_friend_detail(friend)
	_friend_backdrop.visible = true
	_friend_detail_panel.visible = true
	_friend_backdrop.move_to_front()
	_friend_detail_panel.move_to_front()
	_set_shell_swipe_enabled(false)


func _close_friend_detail() -> void:
	if _friend_backdrop != null:
		_friend_backdrop.visible = false
	if _friend_detail_panel != null:
		_friend_detail_panel.visible = false
	_selected_friend.clear()
	_set_shell_swipe_enabled(true)


func _on_friend_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_close_friend_detail()


func _set_shell_swipe_enabled(enabled: bool) -> void:
	var shell := get_tree().current_scene
	if shell != null and shell.has_node("%TabSwipeContainer"):
		shell.get_node("%TabSwipeContainer").set_input_enabled(enabled)


func _populate_friend_detail(friend: Dictionary) -> void:
	while _friend_detail_body.get_child_count() > 0:
		var child := _friend_detail_body.get_child(0)
		_friend_detail_body.remove_child(child)
		child.free()

	var accent: Color = friend.get("accent", UiTokens.ACCENT_SOCIAL)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_friend_detail_body.add_child(header)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(72, 72)
	var disc := UiStyle.filled_disc(accent, 36)
	disc.set_border_width_all(3)
	disc.border_color = Color(1, 1, 1, 0.88)
	avatar.add_theme_stylebox_override("panel", disc)
	var initial := Label.new()
	initial.text = str(friend.get("name", "?")).substr(0, 1).to_upper()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initial.add_theme_font_size_override("font_size", 30)
	initial.add_theme_color_override("font_color", Color.WHITE)
	avatar.add_child(initial)
	header.add_child(avatar)

	var identity := VBoxContainer.new()
	identity.add_theme_constant_override("separation", 4)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(identity)

	var name_label := Label.new()
	name_label.text = str(friend.get("name", ""))
	## Explicit enlarge on this detail sheet; list chips stay on PSEUDO_FONT_SIZE.
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	identity.add_child(name_label)

	var meta := Label.new()
	meta.text = "Nv.%d · %s" % [
		int(friend.get("level", 1)),
		_presence_label(str(friend.get("presence", "offline"))),
	]
	meta.add_theme_font_size_override("font_size", 17)
	meta.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	identity.add_child(meta)

	_friend_detail_body.add_child(_friend_info_line(
		tr("UI_PROFILE_BEST_SUBJECT"),
		str(friend.get("best_subject", "—")),
		str(friend.get("best_subject_icon", "")),
		str(friend.get("best_category_id", ""))
	))
	_friend_detail_body.add_child(_friend_info_line(
		tr("UI_SOCIAL_FRIEND_ACCURACY"),
		"%.0f%%" % float(friend.get("best_accuracy", 0.0))
	))
	var last_won := bool(friend.get("last_won", false))
	var last_result := tr("UI_PROFILE_WIN") if last_won else tr("UI_PROFILE_LOSS")
	var last_subject := str(friend.get("last_game_subject", "—"))
	_friend_detail_body.add_child(_friend_info_line(
		tr("UI_SOCIAL_FRIEND_LAST_GAME"),
		"%s · %s" % [last_result, last_subject],
		"",
		"",
		UiTokens.FEEDBACK_CORRECT if last_won else UiTokens.FEEDBACK_WRONG
	))
	_friend_detail_body.add_child(_friend_info_line(
		tr("UI_PROFILE_STAT_WINS"),
		str(int(friend.get("wins", 0)))
	))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_friend_detail_body.add_child(spacer)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.size_flags_vertical = Control.SIZE_SHRINK_END
	_friend_detail_body.add_child(actions)

	var challenge := Button.new()
	challenge.text = tr("UI_SOCIAL_FRIEND_CHALLENGE")
	challenge.focus_mode = Control.FOCUS_NONE
	challenge.add_theme_font_size_override("font_size", 18)
	challenge.pressed.connect(_on_challenge_friend_pressed)
	PressScaleUtil.wire(challenge, self)
	actions.add_child(challenge)

	var close_btn := Button.new()
	close_btn.text = tr("UI_BACK")
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 17)
	close_btn.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	var empty := StyleBoxEmpty.new()
	close_btn.add_theme_stylebox_override("normal", empty)
	close_btn.add_theme_stylebox_override("hover", empty)
	close_btn.add_theme_stylebox_override("pressed", empty)
	close_btn.pressed.connect(_close_friend_detail)
	actions.add_child(close_btn)


func _friend_info_line(
	caption: String,
	value: String,
	value_icon: String = "",
	category_id: String = "",
	value_color: Color = Color(0, 0, 0, 0)
) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var left := Label.new()
	left.text = caption
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_font_size_override("font_size", 20)
	left.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	row.add_child(left)

	var right_wrap := HBoxContainer.new()
	right_wrap.add_theme_constant_override("separation", 8)
	right_wrap.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(right_wrap)

	var accent := UiTokens.PROFILE_TEXT
	if value_color.a > 0.0:
		accent = value_color
	elif not category_id.is_empty():
		accent = UiTokens.accent_for_category(category_id)

	if not value_icon.is_empty():
		var icon_accent := UiTokens.accent_for_category(category_id) if not category_id.is_empty() else accent
		right_wrap.add_child(_friend_category_icon(value_icon, icon_accent))

	var right := Label.new()
	right.text = value
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.add_theme_font_size_override("font_size", 17)
	right.add_theme_color_override("font_color", accent)
	right_wrap.add_child(right)
	return row


func _friend_category_icon(icon_text: String, accent: Color) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(36, 36)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(accent.r, accent.g, accent.b, 0.28)
	icon_style.set_corner_radius_all(18)
	icon_style.set_content_margin_all(0)
	icon_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.12)
	icon_style.shadow_size = 2
	bg.add_theme_stylebox_override("panel", icon_style)
	slot.add_child(bg)

	var icon := Label.new()
	icon.text = icon_text
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_font_size_override("font_size", 22)
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		icon.add_theme_font_override("font", emoji_font)
	slot.add_child(icon)
	return slot


func _presence_label(presence: String) -> String:
	match presence:
		"online":
			return tr("UI_SOCIAL_FRIEND_ONLINE")
		"away":
			return tr("UI_SOCIAL_FRIEND_AWAY")
		_:
			return tr("UI_SOCIAL_FRIEND_OFFLINE")


func _on_challenge_friend_pressed() -> void:
	if _selected_friend.is_empty():
		return
	var friend_name := str(_selected_friend.get("name", ""))
	_close_friend_detail()
	_status_text = tr("UI_SOCIAL_FRIEND_CHALLENGE_SENT").format({"name": friend_name})
	_rebuild_content()


func _get_friends() -> Array:
	## Prefer real save data when available; otherwise demo profiles for UI work.
	if SaveManager.has_method("get_friends"):
		var stored: Variant = SaveManager.call("get_friends")
		if stored is Array and not stored.is_empty():
			return stored
	return _demo_friends()


func _demo_friends() -> Array:
	## Placeholder profiles until friends API / save exists.
	return [
		_demo_friend("Lucas", 24, "online", UiTokens.ACCENT_QUIZ, "sport", 84.0, true, "sport", 142),
		_demo_friend("Emma", 18, "online", UiTokens.ACCENT_SOCIAL, "cinema", 79.0, false, "cinema", 98),
		_demo_friend("Noah", 31, "away", UiTokens.ACCENT_HOME, "history", 88.0, true, "history", 201),
		_demo_friend("Léa", 12, "offline", UiTokens.ACCENT_LEADERBOARD, "geography", 71.0, true, "geography", 45),
		_demo_friend("Hugo", 27, "online", UiTokens.ACCENT_PROFILE, "science", 82.0, true, "science", 167),
		_demo_friend("Chloé", 22, "away", Color(0.95, 0.48, 0.28, 1), "music", 76.0, false, "music", 121),
		_demo_friend("Inès", 15, "online", Color(0.28, 0.72, 0.45, 1), "general", 73.0, true, "general", 66),
		_demo_friend("Adam", 29, "offline", Color(0.55, 0.40, 0.95, 1), "television", 80.0, true, "television", 188),
		_demo_friend("Sarah", 21, "away", Color(0.20, 0.70, 0.85, 1), "cinema", 85.0, true, "cinema", 110),
		_demo_friend("Theo", 33, "online", UiTokens.FEEDBACK_CORRECT, "sport", 91.0, true, "sport", 244),
		_demo_friend("Maya", 9, "offline", Color(0.98, 0.55, 0.35, 1), "music", 64.0, false, "music", 22),
		_demo_friend("Yanis", 26, "online", Color(0.75, 0.35, 0.70, 1), "history", 77.0, true, "history", 155),
		_demo_friend("Jade", 19, "away", Color(0.35, 0.55, 0.95, 1), "science", 74.0, false, "science", 89),
		_demo_friend("Louis", 14, "online", Color(0.90, 0.70, 0.20, 1), "geography", 69.0, true, "geography", 58),
	]


func _demo_friend(
	name: String,
	level: int,
	presence: String,
	accent: Color,
	best_category_id: String,
	best_accuracy: float,
	last_won: bool,
	last_category_id: String,
	wins: int
) -> Dictionary:
	var locale := TranslationServer.get_locale()
	return {
		"name": name,
		"level": level,
		"presence": presence,
		"accent": accent,
		"best_category_id": best_category_id,
		"best_subject": ProfileSnapshot._resolve_category_name(best_category_id, locale),
		"best_subject_icon": ProfileSnapshot._category_icon(best_category_id),
		"best_accuracy": best_accuracy,
		"last_won": last_won,
		"last_category_id": last_category_id,
		"last_game_subject": ProfileSnapshot._resolve_category_name(last_category_id, locale),
		"wins": wins,
	}


func _create_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 10))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_CREATE_CHALLENGE").to_upper()
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(caption)

	var category_scroll := ScrollContainer.new()
	category_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	category_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	category_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_scroll.custom_minimum_size.y = 48
	vbox.add_child(category_scroll)

	var category_row := HBoxContainer.new()
	category_row.add_theme_constant_override("separation", 8)
	category_scroll.add_child(category_row)
	for category in _categories:
		var category_id := str(category.get("id", ""))
		var button := Button.new()
		button.text = str(category.get("name", category_id))
		var accent := UiTokens.accent_for_category(category_id)
		var selected := category_id == _selected_category_id
		button.add_theme_stylebox_override(
			"normal",
			UiStyle.social_chip(accent, true) if selected else UiStyle.social_chip(accent, false)
		)
		button.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
		button.add_theme_color_override("font_hover_color", UiTokens.PROFILE_TEXT)
		button.add_theme_color_override("font_pressed_color", UiTokens.PROFILE_TEXT)
		button.pressed.connect(_on_category_pressed.bind(category_id))
		category_row.add_child(button)

	var create_button := Button.new()
	create_button.text = tr("UI_SOCIAL_CREATE_BUTTON")
	create_button.pressed.connect(_on_create_pressed)
	vbox.add_child(create_button)

	return panel


func _live_search_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 10))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_LIVE_TITLE").to_upper()
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(caption)

	var search_button := Button.new()
	search_button.text = tr("UI_SOCIAL_LIVE_SEARCH")
	search_button.pressed.connect(_on_live_search_pressed)
	vbox.add_child(search_button)

	return panel


func _live_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 10))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	match _live_state:
		"searching":
			var label := Label.new()
			label.text = tr("UI_SOCIAL_LIVE_SEARCHING")
			label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
			vbox.add_child(label)
			var cancel_button := Button.new()
			cancel_button.text = tr("UI_SOCIAL_LIVE_CANCEL")
			cancel_button.pressed.connect(_on_live_cancel_pressed)
			vbox.add_child(cancel_button)
		"question":
			_build_live_question_view(vbox)
		"over":
			_build_live_over_view(vbox)

	return panel


func _build_live_question_view(vbox: VBoxContainer) -> void:
	var header := Label.new()
	header.text = tr("UI_SOCIAL_LIVE_HEADER").format({
		"opponent": _live_opponent_name,
		"my_score": _live_my_score,
		"opponent_score": _live_opponent_score,
	})
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	vbox.add_child(header)

	_countdown_label = Label.new()
	_countdown_label.text = "%d" % ceili(_live_countdown)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 22)
	_countdown_label.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	vbox.add_child(_countdown_label)

	var question_label := Label.new()
	question_label.text = str(_live_question.get("text", ""))
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_label.add_theme_font_size_override("font_size", 17)
	question_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(question_label)

	var correct_index := -1
	var your_selected := -2
	if not _live_last_reveal.is_empty():
		correct_index = int(_live_last_reveal.get("correct_index", -1))
		your_selected = int(_live_last_reveal.get("your_result", {}).get("selected_index", -2))

	var choices: Array = _live_question.get("choices", [])
	for index in range(choices.size()):
		var button := Button.new()
		button.text = str(choices[index])
		button.disabled = _live_answered
		if index == correct_index:
			button.add_theme_color_override("font_color", Color.FOREST_GREEN)
		elif index == your_selected:
			button.add_theme_color_override("font_color", Color.CRIMSON)
		button.pressed.connect(_on_live_choice_pressed.bind(index))
		vbox.add_child(button)

	if not _live_last_reveal.is_empty():
		var your_result: Dictionary = _live_last_reveal.get("your_result", {})
		var points_label := Label.new()
		points_label.text = tr("UI_SOCIAL_LIVE_POINTS").format({"points": int(your_result.get("points", 0))})
		points_label.add_theme_font_size_override("font_size", 13)
		points_label.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
		vbox.add_child(points_label)


func _build_live_over_view(vbox: VBoxContainer) -> void:
	var won: bool = bool(_live_over_data.get("won", false))
	var my_score: int = int(_live_over_data.get("your_score", 0))
	var opponent_score: int = int(_live_over_data.get("opponent_score", 0))

	var key := "UI_SOCIAL_RESULT_LOSS"
	if won:
		key = "UI_SOCIAL_RESULT_WIN"
	elif my_score == opponent_score:
		key = "UI_SOCIAL_RESULT_TIE"

	var label := Label.new()
	label.text = tr(key).format({"my_score": my_score, "opponent_score": opponent_score})
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	vbox.add_child(label)

	var close_button := Button.new()
	close_button.text = tr("UI_SOCIAL_LIVE_CLOSE")
	close_button.pressed.connect(_on_live_close_pressed)
	vbox.add_child(close_button)


func _join_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 10))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_JOIN_CHALLENGE").to_upper()
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(caption)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	var code_input := LineEdit.new()
	code_input.placeholder_text = tr("UI_SOCIAL_CODE_PLACEHOLDER")
	code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(code_input)

	var join_button := Button.new()
	join_button.text = tr("UI_SOCIAL_JOIN_BUTTON")
	join_button.pressed.connect(_on_join_pressed.bind(code_input))
	row.add_child(join_button)

	return panel


func _challenge_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 10))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var code := str(_current_challenge.get("code", ""))
	var category_id := str(_current_challenge.get("category", ""))
	var status := str(_current_challenge.get("status", "pending"))

	var header := Label.new()
	header.text = tr("UI_SOCIAL_CHALLENGE_HEADER").format({"category": category_id, "code": code}).to_upper()
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(header)

	var copy_button := Button.new()
	copy_button.text = tr("UI_SOCIAL_COPY_CODE")
	copy_button.pressed.connect(_on_copy_code_pressed.bind(code))
	vbox.add_child(copy_button)

	if status == "completed":
		vbox.add_child(_make_result_label())
		var new_button := Button.new()
		new_button.text = tr("UI_SOCIAL_NEW_CHALLENGE")
		new_button.pressed.connect(_on_new_challenge_pressed)
		vbox.add_child(new_button)
	else:
		var status_label := Label.new()
		status_label.text = tr("UI_SOCIAL_STATUS_PENDING") if status == "pending" else tr("UI_SOCIAL_STATUS_ACCEPTED")
		status_label.add_theme_font_size_override("font_size", 13)
		status_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
		vbox.add_child(status_label)

		if status == "accepted" and not _my_score_submitted():
			var play_button := Button.new()
			play_button.text = tr("UI_PLAY")
			play_button.pressed.connect(_on_play_pressed)
			vbox.add_child(play_button)

		var refresh_button := Button.new()
		refresh_button.text = tr("UI_SOCIAL_REFRESH")
		refresh_button.pressed.connect(_on_refresh_pressed)
		vbox.add_child(refresh_button)

	return panel


func _make_result_label() -> Label:
	var is_challenger := _is_challenger()
	var my_score: int = int(_current_challenge.get("challenger_score" if is_challenger else "opponent_score", 0))
	var opponent_score: int = int(_current_challenge.get("opponent_score" if is_challenger else "challenger_score", 0))
	var label := Label.new()
	var key := "UI_SOCIAL_RESULT_WIN"
	if my_score < opponent_score:
		key = "UI_SOCIAL_RESULT_LOSS"
	elif my_score == opponent_score:
		key = "UI_SOCIAL_RESULT_TIE"
	label.text = tr(key).format({"my_score": my_score, "opponent_score": opponent_score})
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	return label


func _is_challenger() -> bool:
	return not NetworkManager.player_id.is_empty() \
		and str(_current_challenge.get("challenger_id", "")) == NetworkManager.player_id


func _my_score_submitted() -> bool:
	var field := "challenger_score" if _is_challenger() else "opponent_score"
	return typeof(_current_challenge.get(field)) != TYPE_NIL


func _on_category_pressed(category_id: String) -> void:
	_selected_category_id = category_id
	_rebuild_content()


func _on_create_pressed() -> void:
	if _selected_category_id.is_empty():
		return
	_status_text = tr("UI_SOCIAL_CREATING")
	_rebuild_content()
	NetworkManager.create_challenge(_selected_category_id)


func _on_challenge_created(challenge: Dictionary) -> void:
	_current_challenge = challenge
	_status_text = ""
	_rebuild_content()


func _on_challenge_create_failed() -> void:
	_status_text = tr("UI_SOCIAL_ERROR_OFFLINE")
	_rebuild_content()


func _on_join_pressed(code_input: LineEdit) -> void:
	var code := code_input.text.strip_edges().to_upper()
	if code.is_empty():
		return
	_status_text = tr("UI_SOCIAL_JOINING")
	_rebuild_content()
	NetworkManager.join_challenge(code)


func _on_challenge_joined(challenge: Dictionary) -> void:
	_current_challenge = challenge
	_status_text = ""
	_rebuild_content()


func _on_challenge_join_failed(_error_code: int) -> void:
	_status_text = tr("UI_SOCIAL_ERROR_JOIN")
	_rebuild_content()


func _on_refresh_pressed() -> void:
	NetworkManager.fetch_challenge(str(_current_challenge.get("code", "")))


func _on_challenge_fetched(challenge: Dictionary) -> void:
	_current_challenge = challenge
	_rebuild_content()


func _on_challenge_fetch_failed(_code: String) -> void:
	_status_text = tr("UI_SOCIAL_ERROR_OFFLINE")
	_rebuild_content()


func _on_copy_code_pressed(code: String) -> void:
	DisplayServer.clipboard_set(code)


func _on_new_challenge_pressed() -> void:
	_current_challenge = {}
	_rebuild_content()


func _on_play_pressed() -> void:
	var code := str(_current_challenge.get("code", ""))
	var category_id := str(_current_challenge.get("category", ""))
	GameManager.start_round(category_id, code)
	if not GameManager.has_questions():
		_status_text = tr("UI_EMPTY_QUESTIONS")
		_rebuild_content()
		return
	get_tree().change_scene_to_file(ScenePaths.QUIZ_GAME)


func _on_live_search_pressed() -> void:
	if _selected_category_id.is_empty():
		return
	_live_state = "searching"
	_rebuild_content()
	NetworkManager.start_live_matchmaking(_selected_category_id)


func _on_live_cancel_pressed() -> void:
	NetworkManager.stop_live_matchmaking()
	_live_state = "idle"
	_rebuild_content()


func _on_live_match_found(data: Dictionary) -> void:
	_live_opponent_name = str(data.get("opponent_name", ""))
	_live_my_score = 0
	_live_opponent_score = 0


func _on_live_question(data: Dictionary) -> void:
	_live_question = data
	_live_state = "question"
	_live_answered = false
	_live_last_reveal = {}
	_live_countdown = float(data.get("time_limit", 10.0))
	_rebuild_content()


func _on_live_choice_pressed(index: int) -> void:
	if _live_answered:
		return
	_live_answered = true
	NetworkManager.send_live_answer(int(_live_question.get("index", 0)), index)
	_rebuild_content()


func _on_live_reveal(data: Dictionary) -> void:
	_live_last_reveal = data
	_live_answered = true
	_live_my_score = int(data.get("your_result", {}).get("score", _live_my_score))
	_live_opponent_score = int(data.get("opponent_result", {}).get("score", _live_opponent_score))
	_rebuild_content()


func _on_live_match_over(data: Dictionary) -> void:
	_live_over_data = data
	_live_state = "over"
	_rebuild_content()


func _on_live_error(_reason: String) -> void:
	_live_state = "idle"
	_status_text = tr("UI_SOCIAL_ERROR_OFFLINE")
	_rebuild_content()


func _on_live_close_pressed() -> void:
	_live_state = "idle"
	_live_over_data = {}
	_rebuild_content()


func _on_locale_changed(_locale: String) -> void:
	_apply()
