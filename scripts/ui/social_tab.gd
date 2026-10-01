## Social tab page. Edit this script and `scenes/tabs/social_tab.tscn` only.
extends Control

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")
const ScenePaths = preload("res://scripts/config/scene_paths.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const GameAssets = preload("res://scripts/config/game_assets.gd")

## Async create/join challenge tiles — kept in code, hidden from the Social page for now.
## Flip to `true` to restore `_create_section` / `_join_section` / `_challenge_card`.
const SHOW_ASYNC_CHALLENGE_TILES := false

@onready var content: VBoxContainer = %Content
@onready var message_label: Label = %MessageLabel

var _categories: Array[Dictionary] = []
var _selected_category_id: String = ""
var _current_challenge: Dictionary = {}
## Friend key for the open challenge (H2H counter; no trophies).
var _challenge_friend_key: String = ""
var _status_text: String = ""

var _live_state: String = "idle" # idle | searching | question | over
var _live_opponent_name: String = ""
var _live_opponent_trophies: int = -1
## Opponent's look from match_found {avatar, frame, banner}.
var _live_opponent_cosmetics: Dictionary = {}
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
var _friend_detail_banner: BannerView
var _friend_detail_body: VBoxContainer
var _selected_friend: Dictionary = {}
var _friends_page: Control
var _friends_page_grid: GridContainer
var _friends_page_scroll: ScrollContainer
var _friend_requests: Array = []
var _friend_requests_page: Control
var _friend_requests_list: VBoxContainer
var _challenge_requests: Array = []
var _challenge_requests_page: Control
var _challenge_requests_list: VBoxContainer
var _challenge_mode_picker: Control
var _pending_challenge_friend: Dictionary = {}


func _ready() -> void:
	_friend_requests = _demo_friend_requests()
	_challenge_requests = _demo_challenge_requests()
	_prune_expired_challenge_requests()
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
	NetworkManager.live_search_range_changed.connect(_on_live_search_range_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _challenge_mode_picker != null and _challenge_mode_picker.visible:
		_close_challenge_mode_picker()
		get_viewport().set_input_as_handled()
		return
	if _friend_detail_panel != null and _friend_detail_panel.visible:
		_close_friend_detail()
		get_viewport().set_input_as_handled()
		return
	if _challenge_requests_page != null and _challenge_requests_page.visible:
		_close_challenge_requests_page()
		get_viewport().set_input_as_handled()
		return
	if _friend_requests_page != null and _friend_requests_page.visible:
		_close_friend_requests_page()
		get_viewport().set_input_as_handled()
		return
	if _friends_page != null and _friends_page.visible:
		_close_friends_page()
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


func _rebuild_content(reset_scroll: bool = false) -> void:
	_close_challenge_mode_picker()
	_close_friend_detail()
	var scroll := content.get_parent() as ScrollContainer
	var prev_scroll := scroll.scroll_vertical if scroll != null else 0
	## Remove immediately so height (and scroll) don't spike while queue_free waits.
	var stale: Array[Node] = []
	for child in content.get_children():
		if child != message_label:
			stale.append(child)
	for child in stale:
		content.remove_child(child)
		child.queue_free()
	_countdown_label = null

	if _live_state != "idle":
		content.add_child(_live_section())
	else:
		content.add_child(_friends_section())
		content.add_child(_friend_requests_section())
		content.add_child(_challenge_requests_section())
		content.add_child(_player_search_section())
		## Create / join / active-code tiles: see SHOW_ASYNC_CHALLENGE_TILES.
		if SHOW_ASYNC_CHALLENGE_TILES:
			if _current_challenge.is_empty():
				content.add_child(_create_section())
				content.add_child(_join_section())
			else:
				content.add_child(_challenge_card())

	if not _status_text.is_empty():
		content.add_child(_make_status_label(_status_text))
	ScrollTouch.let_drags_through(content)

	## Hint label kept in the scene tree for rebuild stability, but unused.
	message_label.text = ""
	message_label.visible = false
	if scroll != null:
		if reset_scroll:
			scroll.scroll_vertical = 0
		else:
			call_deferred("_restore_scroll_y", prev_scroll)


func _restore_scroll_y(y: int) -> void:
	var scroll := content.get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = y


func _make_status_label(text: String) -> Label:
	var status := Label.new()
	status.set_meta("status_label", true)
	status.text = text
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", UiScale.font(13))
	status.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	return status


func _show_status(text: String) -> void:
	## Update status without rebuilding the page (keeps scroll position).
	_status_text = text
	var existing: Label = null
	for child in content.get_children():
		if child is Label and bool(child.get_meta("status_label", false)):
			existing = child as Label
			break
	if text.is_empty():
		if existing != null:
			content.remove_child(existing)
			existing.queue_free()
		return
	if existing != null:
		existing.text = text
		return
	## Insert above the hint message when present.
	var status := _make_status_label(text)
	content.add_child(status)
	if message_label.get_parent() == content:
		content.move_child(status, message_label.get_index())
	else:
		content.move_child(status, content.get_child_count() - 1)


func _friends_section() -> PanelContainer:
	## Same title size / left inset as profile tiles; Voir tout on the right.
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 220
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 0))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	pad.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_FRIENDS").to_upper()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", UiScale.font(18))
	caption.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	header.add_child(caption)

	var see_all := Button.new()
	see_all.text = tr("UI_PROFILE_SEE_ALL").to_upper() + " >"
	see_all.flat = true
	see_all.focus_mode = Control.FOCUS_NONE
	see_all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	see_all.add_theme_font_size_override("font_size", UiScale.font(17))
	see_all.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	see_all.add_theme_color_override("font_hover_color", UiTokens.ACCENT_SOCIAL.lightened(0.15))
	see_all.add_theme_color_override("font_pressed_color", UiTokens.ACCENT_SOCIAL.darkened(0.1))
	var empty_style := StyleBoxEmpty.new()
	see_all.add_theme_stylebox_override("normal", empty_style)
	see_all.add_theme_stylebox_override("hover", empty_style)
	see_all.add_theme_stylebox_override("pressed", empty_style)
	see_all.add_theme_stylebox_override("focus", empty_style)
	see_all.pressed.connect(_open_friends_page)
	PressScaleUtil.wire(see_all, self)
	header.add_child(see_all)

	var friends := _get_friends()
	if friends.is_empty():
		var empty := Label.new()
		empty.text = tr("UI_SOCIAL_FRIENDS_EMPTY")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", UiScale.font(14))
		empty.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
		vbox.add_child(empty)
		return panel

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 148
	vbox.add_child(scroll)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	scroll.add_child(row)
	for friend in friends:
		if typeof(friend) != TYPE_DICTIONARY:
			continue
		row.add_child(_friend_chip(friend))
	return panel


func _friend_requests_section() -> PanelContainer:
	## Mock: demandes d'amis with accept / decline rows.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 0))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 11)
	pad.add_theme_constant_override("margin_bottom", 11)
	panel.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	pad.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_FRIEND_REQUESTS").to_upper()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", UiScale.font(18))
	caption.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	header.add_child(caption)

	var see_all := Button.new()
	see_all.text = tr("UI_PROFILE_SEE_ALL").to_upper() + " >"
	see_all.flat = true
	see_all.focus_mode = Control.FOCUS_NONE
	see_all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	see_all.add_theme_font_size_override("font_size", UiScale.font(17))
	see_all.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	see_all.add_theme_color_override("font_hover_color", UiTokens.ACCENT_SOCIAL.lightened(0.15))
	see_all.add_theme_color_override("font_pressed_color", UiTokens.ACCENT_SOCIAL.darkened(0.1))
	var empty_style := StyleBoxEmpty.new()
	see_all.add_theme_stylebox_override("normal", empty_style)
	see_all.add_theme_stylebox_override("hover", empty_style)
	see_all.add_theme_stylebox_override("pressed", empty_style)
	see_all.add_theme_stylebox_override("focus", empty_style)
	see_all.pressed.connect(_open_friend_requests_page)
	PressScaleUtil.wire(see_all, self)
	header.add_child(see_all)

	var divider := ColorRect.new()
	divider.custom_minimum_size.y = 1
	divider.color = Color(1, 1, 1, 0.08)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(divider)

	var requests := _friend_requests
	if requests.is_empty():
		var empty := Label.new()
		empty.text = tr("UI_SOCIAL_FRIEND_REQUESTS_EMPTY")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", UiScale.font(18))
		empty.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
		vbox.add_child(empty)
		return panel

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	vbox.add_child(list)
	var shown := mini(requests.size(), 3)
	for i in range(shown):
		if typeof(requests[i]) != TYPE_DICTIONARY:
			continue
		list.add_child(_friend_request_row(requests[i]))
	return panel


func _challenge_requests_section() -> PanelContainer:
	## Same layout as friend requests: title + Voir tout + accept/decline rows.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 0))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 11)
	pad.add_theme_constant_override("margin_bottom", 11)
	panel.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	pad.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_CHALLENGE_REQUESTS").to_upper()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", UiScale.font(18))
	caption.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	header.add_child(caption)

	var see_all := Button.new()
	see_all.text = tr("UI_PROFILE_SEE_ALL").to_upper() + " >"
	see_all.flat = true
	see_all.focus_mode = Control.FOCUS_NONE
	see_all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	see_all.add_theme_font_size_override("font_size", UiScale.font(17))
	see_all.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	see_all.add_theme_color_override("font_hover_color", UiTokens.ACCENT_SOCIAL.lightened(0.15))
	see_all.add_theme_color_override("font_pressed_color", UiTokens.ACCENT_SOCIAL.darkened(0.1))
	var empty_style := StyleBoxEmpty.new()
	see_all.add_theme_stylebox_override("normal", empty_style)
	see_all.add_theme_stylebox_override("hover", empty_style)
	see_all.add_theme_stylebox_override("pressed", empty_style)
	see_all.add_theme_stylebox_override("focus", empty_style)
	see_all.pressed.connect(_open_challenge_requests_page)
	PressScaleUtil.wire(see_all, self)
	header.add_child(see_all)

	var divider := ColorRect.new()
	divider.custom_minimum_size.y = 1
	divider.color = Color(1, 1, 1, 0.08)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(divider)

	_prune_expired_challenge_requests()
	var requests := _challenge_requests
	if requests.is_empty():
		var empty := Label.new()
		empty.text = tr("UI_SOCIAL_CHALLENGE_REQUESTS_EMPTY")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", UiScale.font(18))
		empty.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
		vbox.add_child(empty)
		return panel

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	vbox.add_child(list)
	var shown := mini(requests.size(), 3)
	for i in range(shown):
		if typeof(requests[i]) != TYPE_DICTIONARY:
			continue
		list.add_child(_challenge_request_row(requests[i]))
	return panel


func _player_search_section() -> PanelContainer:
	## Mock: search field + add-friend CTA.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 0))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	pad.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_SEARCH_PLAYER").to_upper()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", UiScale.font(18))
	caption.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	header.add_child(caption)

	var divider := ColorRect.new()
	divider.custom_minimum_size.y = 1
	divider.color = Color(1, 1, 1, 0.08)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(divider)

	var search_wrap := PanelContainer.new()
	var search_bg := StyleBoxFlat.new()
	search_bg.bg_color = Color(0.93, 0.91, 0.94, 1)
	search_bg.set_corner_radius_all(22)
	search_bg.content_margin_left = 14
	search_bg.content_margin_right = 6
	search_bg.content_margin_top = 6
	search_bg.content_margin_bottom = 6
	search_wrap.add_theme_stylebox_override("panel", search_bg)
	vbox.add_child(search_wrap)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	search_row.alignment = BoxContainer.ALIGNMENT_CENTER
	search_wrap.add_child(search_row)

	var search := LineEdit.new()
	search.placeholder_text = tr("UI_SOCIAL_SEARCH_PLACEHOLDER")
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.y = 44
	search.focus_mode = Control.FOCUS_CLICK
	search.add_theme_font_size_override("font_size", UiScale.font(18))
	search.add_theme_color_override("font_color", Color(0.18, 0.12, 0.16, 1))
	search.add_theme_color_override("font_placeholder_color", Color(0.45, 0.42, 0.48, 1))
	var clear_line := StyleBoxEmpty.new()
	search.add_theme_stylebox_override("normal", clear_line)
	search.add_theme_stylebox_override("focus", clear_line)
	search_row.add_child(search)

	var search_btn := Button.new()
	search_btn.text = "🔍"
	search_btn.focus_mode = Control.FOCUS_NONE
	search_btn.custom_minimum_size = Vector2(40, 40)
	search_btn.add_theme_font_size_override("font_size", UiScale.font(16))
	var search_btn_style := StyleBoxFlat.new()
	search_btn_style.bg_color = UiTokens.ACCENT_SOCIAL
	search_btn_style.set_corner_radius_all(20)
	search_btn.add_theme_stylebox_override("normal", search_btn_style)
	search_btn.add_theme_stylebox_override("hover", search_btn_style)
	search_btn.add_theme_stylebox_override("pressed", search_btn_style)
	search_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	search_btn.pressed.connect(_on_search_player_pressed.bind(search))
	PressScaleUtil.wire(search_btn, self)
	search_row.add_child(search_btn)

	var add_btn := Button.new()
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.custom_minimum_size.y = 52
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## Same opaque CTA as Create / Join — readable hover on social tiles.
	var add_style := StyleBoxFlat.new()
	add_style.bg_color = UiTokens.ACCENT_SOCIAL
	add_style.set_corner_radius_all(16)
	add_style.content_margin_left = 16
	add_style.content_margin_right = 16
	add_style.content_margin_top = 12
	add_style.content_margin_bottom = 12
	var add_hover := add_style.duplicate() as StyleBoxFlat
	add_hover.bg_color = UiTokens.ACCENT_SOCIAL.lightened(0.10)
	var add_pressed := add_style.duplicate() as StyleBoxFlat
	add_pressed.bg_color = UiTokens.ACCENT_SOCIAL.darkened(0.06)
	add_btn.add_theme_stylebox_override("normal", add_style)
	add_btn.add_theme_stylebox_override("hover", add_hover)
	add_btn.add_theme_stylebox_override("pressed", add_pressed)
	add_btn.add_theme_stylebox_override("focus", add_hover)
	add_btn.pressed.connect(_on_add_friend_pressed.bind(search))
	PressScaleUtil.wire(add_btn, self)
	vbox.add_child(add_btn)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 10)
	add_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_btn.add_child(add_row)

	var ink := Color(0.12, 0.06, 0.1, 1)
	var plus := Label.new()
	plus.text = "＋"
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plus.add_theme_font_size_override("font_size", UiScale.font(18))
	plus.add_theme_color_override("font_color", ink)
	add_row.add_child(plus)

	var add_label := Label.new()
	add_label.text = tr("UI_SOCIAL_ADD_FRIEND").to_upper()
	add_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_label.add_theme_font_size_override("font_size", UiScale.font(18))
	add_label.add_theme_color_override("font_color", ink)
	add_row.add_child(add_label)
	return panel


func _friend_request_row(request: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	## Transparent fill so the requester's banner reads as the row background.
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(14)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	row.add_theme_stylebox_override("panel", style)

	var request_name := str(request.get("name", ""))
	var cosmetics: Dictionary = request.get("cosmetics", {})
	if cosmetics.is_empty():
		cosmetics = ShopCatalog.demo_cosmetics_for(request_name)

	var banner := CosmeticsView.banner(str(cosmetics.get("banner", "")), Vector2.ZERO, 14)
	row.add_child(banner)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	row.add_child(pad)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pad.add_child(hbox)

	const AVATAR := 64.0
	hbox.add_child(CosmeticsView.avatar(cosmetics, AVATAR))

	var identity := VBoxContainer.new()
	identity.add_theme_constant_override("separation", 1)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(identity)

	var name_label := Label.new()
	name_label.text = request_name
	name_label.clip_text = true
	name_label.add_theme_font_size_override(
		"font_size",
		UiScale.font(UiTokens.pseudo_font_size(request_name))
	)
	name_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	identity.add_child(name_label)

	var level_label := Label.new()
	level_label.text = "%s %d" % [tr("UI_PROFILE_LEVEL_CAPTION"), int(request.get("level", 1))]
	level_label.add_theme_font_size_override("font_size", UiScale.font(13))
	level_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	identity.add_child(level_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	hbox.add_child(actions)

	actions.add_child(_friend_request_action_btn(
		"✕",
		UiTokens.FEEDBACK_WRONG,
		_on_friend_request_declined.bind(request_name)
	))
	actions.add_child(_friend_request_action_btn(
		"✓",
		UiTokens.FEEDBACK_CORRECT,
		_on_friend_request_accepted.bind(request_name)
	))
	return row


func _friend_request_action_btn(label_text: String, color: Color, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(48, 48)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.clip_text = true
	btn.add_theme_font_size_override("font_size", UiScale.font(22))
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_constant_override("outline_size", 0)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(999)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.08)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.08)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if callback.is_valid():
		btn.pressed.connect(callback)
	PressScaleUtil.wire(btn, self)
	return btn


func _demo_friend_requests() -> Array:
	## Names must match assets/avatars/demo/*.png slugs.
	return [
		{"name": "Sarah", "level": 18, "accent": Color(0.95, 0.45, 0.70, 1)},
		{"name": "Theo", "level": 21, "accent": Color(0.35, 0.55, 0.95, 1)},
		{"name": "Maya", "level": 14, "accent": Color(0.95, 0.60, 0.25, 1)},
		{"name": "Yanis", "level": 27, "accent": Color(0.30, 0.75, 0.55, 1)},
	]


func _demo_challenge_requests() -> Array:
	## Pending live duel invites — expire after 4h; presence gates accept.
	var now := int(Time.get_unix_time_from_system())
	var sent_at := Time.get_datetime_string_from_system(true)
	return [
		{
			"name": "Hugo",
			"level": 16,
			"mode": 0,
			"presence": "online",
			"sent_at": sent_at,
			"sent_unix": now,
		},
		{
			"name": "Lea",
			"level": 22,
			"mode": 1,
			"presence": "offline",
			"sent_at": sent_at,
			"sent_unix": now,
		},
		{
			"name": "Noah",
			"level": 19,
			"mode": 2,
			"presence": "online",
			"sent_at": sent_at,
			"sent_unix": now,
		},
	]


func _prune_expired_challenge_requests() -> void:
	var kept: Array = []
	for request in _challenge_requests:
		if typeof(request) != TYPE_DICTIONARY:
			continue
		if SaveManager.is_challenge_invite_expired(request):
			continue
		kept.append(request)
	_challenge_requests = kept


func _challenge_mode_meta(mode: int) -> Dictionary:
	## Labels / emoji aligned with Quiz duel modes.
	match clampi(mode, 0, 2):
		1:
			return {
				"key": "UI_MODE_SURVIVAL",
				"icon": "❤️",
				"accent": UiTokens.ACCENT_MODE_SURVIVAL,
			}
		2:
			return {
				"key": "UI_MODE_TIME_ATTACK",
				"icon": "⏱️",
				"accent": UiTokens.ACCENT_MODE_TIME_ATTACK,
			}
		_:
			return {
				"key": "UI_MODE_CLASSIC",
				"icon": "🎯",
				"accent": UiTokens.ACCENT_MODE_CLASSIC,
			}


func _challenge_request_row(request: Dictionary) -> Control:
	## Friend-request row layout, with the proposed duel mode as a clear badge.
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(14)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	row.add_theme_stylebox_override("panel", style)

	var request_name := str(request.get("name", ""))
	var cosmetics: Dictionary = request.get("cosmetics", {})
	if cosmetics.is_empty():
		cosmetics = ShopCatalog.demo_cosmetics_for(request_name)

	var banner := CosmeticsView.banner(str(cosmetics.get("banner", "")), Vector2.ZERO, 14)
	row.add_child(banner)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	row.add_child(pad)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pad.add_child(hbox)

	const AVATAR := 64.0
	hbox.add_child(CosmeticsView.avatar(cosmetics, AVATAR))

	var identity := VBoxContainer.new()
	identity.add_theme_constant_override("separation", 1)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(identity)

	var name_label := Label.new()
	name_label.text = request_name
	name_label.clip_text = true
	name_label.add_theme_font_size_override(
		"font_size",
		UiScale.font(UiTokens.pseudo_font_size(request_name))
	)
	name_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	identity.add_child(name_label)

	var level_label := Label.new()
	level_label.text = "%s %d" % [tr("UI_PROFILE_LEVEL_CAPTION"), int(request.get("level", 1))]
	level_label.add_theme_font_size_override("font_size", UiScale.font(13))
	level_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	identity.add_child(level_label)

	## Proposed mode — the detail that matters on this tile.
	var mode_meta := _challenge_mode_meta(int(request.get("mode", 0)))
	var mode_accent: Color = mode_meta["accent"]
	var mode_badge := PanelContainer.new()
	mode_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = mode_accent
	badge_style.set_border_width_all(0)
	badge_style.set_corner_radius_all(12)
	badge_style.content_margin_left = 10
	badge_style.content_margin_right = 12
	badge_style.content_margin_top = 8
	badge_style.content_margin_bottom = 8
	mode_badge.add_theme_stylebox_override("panel", badge_style)
	hbox.add_child(mode_badge)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_badge.add_child(mode_row)

	var mode_icon := Label.new()
	mode_icon.text = str(mode_meta["icon"])
	mode_icon.add_theme_font_size_override("font_size", UiScale.font(18))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		mode_icon.add_theme_font_override("font", emoji_font)
	mode_row.add_child(mode_icon)

	var mode_label := Label.new()
	mode_label.text = tr(str(mode_meta["key"])).to_upper()
	mode_label.add_theme_font_size_override("font_size", UiScale.font(15))
	mode_label.add_theme_color_override("font_color", Color(0.10, 0.08, 0.12, 1))
	mode_row.add_child(mode_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	hbox.add_child(actions)

	actions.add_child(_friend_request_action_btn(
		"✕",
		UiTokens.FEEDBACK_WRONG,
		_on_challenge_request_declined.bind(request)
	))
	actions.add_child(_friend_request_action_btn(
		"✓",
		UiTokens.FEEDBACK_CORRECT,
		_on_challenge_request_accepted.bind(request)
	))
	return row


func _remove_friend_request(player_name: String) -> void:
	var next: Array = []
	for request in _friend_requests:
		if typeof(request) != TYPE_DICTIONARY:
			continue
		if str(request.get("name", "")) == player_name:
			continue
		next.append(request)
	_friend_requests = next


func _on_friend_request_accepted(player_name: String) -> void:
	_remove_friend_request(player_name)
	_show_status(tr("UI_SOCIAL_FRIEND_REQUEST_ACCEPTED").format({"name": player_name}))
	if _friend_requests_page != null and _friend_requests_page.visible:
		_populate_friend_requests_page()
	_rebuild_content()


func _on_friend_request_declined(player_name: String) -> void:
	_remove_friend_request(player_name)
	_show_status(tr("UI_SOCIAL_FRIEND_REQUEST_DECLINED").format({"name": player_name}))
	if _friend_requests_page != null and _friend_requests_page.visible:
		_populate_friend_requests_page()
	_rebuild_content()


func _remove_challenge_request(player_name: String) -> void:
	var next: Array = []
	for request in _challenge_requests:
		if typeof(request) != TYPE_DICTIONARY:
			continue
		if str(request.get("name", "")) == player_name:
			continue
		next.append(request)
	_challenge_requests = next


func _on_challenge_request_accepted(request: Dictionary) -> void:
	## Live duel only: must accept within 4h while the challenger is online.
	var player_name := str(request.get("name", ""))
	if SaveManager.is_challenge_invite_expired(request):
		_remove_challenge_request(player_name)
		_show_status(tr("UI_SOCIAL_CHALLENGE_REQUEST_EXPIRED"))
		if _challenge_requests_page != null and _challenge_requests_page.visible:
			_populate_challenge_requests_page()
		_rebuild_content()
		return

	var presence := str(request.get("presence", "offline"))
	if presence != "online":
		_remove_challenge_request(player_name)
		_show_status(tr("UI_SOCIAL_CHALLENGE_REQUEST_OFFLINE").format({"name": player_name}))
		if _challenge_requests_page != null and _challenge_requests_page.visible:
			_populate_challenge_requests_page()
		_rebuild_content()
		return

	var mode := clampi(int(request.get("mode", 0)), 0, 2)
	_challenge_friend_key = _friend_rivalry_key(request)
	_remove_challenge_request(player_name)
	NetworkManager.accept_friend_challenge(_challenge_friend_key, mode)
	GameManager.selected_mode = mode
	GameManager.shell_tab_index = ScenePaths.Tab.SOCIAL
	AudioManager.play("click")
	get_tree().change_scene_to_file(ScenePaths.LIVE_MATCH)


func _on_challenge_request_declined(request: Dictionary) -> void:
	var player_name := str(request.get("name", ""))
	_remove_challenge_request(player_name)
	_show_status(tr("UI_SOCIAL_CHALLENGE_REQUEST_DECLINED").format({"name": player_name}))
	if _challenge_requests_page != null and _challenge_requests_page.visible:
		_populate_challenge_requests_page()
	_rebuild_content()


func _on_search_player_pressed(search: LineEdit) -> void:
	_on_add_friend_pressed(search)


func _on_add_friend_pressed(search: LineEdit) -> void:
	var player_name := search.text.strip_edges() if search != null else ""
	if player_name.is_empty():
		_show_status(tr("UI_SOCIAL_ADD_FRIEND_EMPTY"))
	else:
		_show_status(tr("UI_SOCIAL_ADD_FRIEND_SENT").format({"name": player_name}))
		if search != null:
			search.text = ""


func _open_friend_requests_page() -> void:
	_ensure_friend_requests_page()
	_populate_friend_requests_page()
	_friend_requests_page.visible = true
	_friend_requests_page.move_to_front()
	_set_shell_swipe_enabled(false)


func _close_friend_requests_page() -> void:
	_close_friend_detail()
	if _friend_requests_page != null:
		_friend_requests_page.visible = false
	if (_friends_page == null or not _friends_page.visible) and (
		_challenge_requests_page == null or not _challenge_requests_page.visible
	):
		_set_shell_swipe_enabled(true)


func _ensure_friend_requests_page() -> void:
	if _friend_requests_page != null and is_instance_valid(_friend_requests_page):
		return

	_friend_requests_page = Control.new()
	_friend_requests_page.name = "FriendRequestsPage"
	_friend_requests_page.visible = false
	_friend_requests_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_friend_requests_page.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_friend_requests_page)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.WHITE
	bg.material = UiTokens.page_bg_material_for_tab(ScenePaths.Tab.SOCIAL)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_friend_requests_page.add_child(bg)

	var page_margin := MarginContainer.new()
	page_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_margin.add_theme_constant_override("margin_left", 10)
	page_margin.add_theme_constant_override("margin_right", 10)
	page_margin.add_theme_constant_override("margin_top", 10)
	page_margin.add_theme_constant_override("margin_bottom", 10)
	_friend_requests_page.add_child(page_margin)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(true, 14))
	page_margin.add_child(panel)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 14)
	inner.add_theme_constant_override("margin_right", 14)
	inner.add_theme_constant_override("margin_top", 14)
	inner.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(inner)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	var back := Button.new()
	back.text = "< " + tr("UI_BACK")
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", UiScale.font(16))
	back.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	var empty := StyleBoxEmpty.new()
	back.add_theme_stylebox_override("normal", empty)
	back.add_theme_stylebox_override("hover", empty)
	back.add_theme_stylebox_override("pressed", empty)
	back.pressed.connect(_close_friend_requests_page)
	PressScaleUtil.wire(back, self)
	header.add_child(back)

	var page_title := Label.new()
	page_title.text = tr("UI_SOCIAL_FRIEND_REQUESTS").to_upper()
	page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_title.add_theme_font_size_override("font_size", UiScale.font(20))
	page_title.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	header.add_child(page_title)

	var spacer := Control.new()
	spacer.custom_minimum_size.x = 72
	header.add_child(spacer)

	var scroll_box := ScrollContainer.new()
	scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_box.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	vbox.add_child(scroll_box)

	_friend_requests_list = VBoxContainer.new()
	_friend_requests_list.add_theme_constant_override("separation", 10)
	_friend_requests_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_box.add_child(_friend_requests_list)


func _populate_friend_requests_page() -> void:
	if _friend_requests_list == null:
		return
	while _friend_requests_list.get_child_count() > 0:
		var child := _friend_requests_list.get_child(0)
		_friend_requests_list.remove_child(child)
		child.queue_free()
	if _friend_requests.is_empty():
		var empty := Label.new()
		empty.text = tr("UI_SOCIAL_FRIEND_REQUESTS_EMPTY")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", UiScale.font(18))
		empty.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
		_friend_requests_list.add_child(empty)
		return
	for request in _friend_requests:
		if typeof(request) != TYPE_DICTIONARY:
			continue
		_friend_requests_list.add_child(_friend_request_row(request))
	ScrollTouch.let_drags_through(_friend_requests_list)


func _open_challenge_requests_page() -> void:
	_ensure_challenge_requests_page()
	_populate_challenge_requests_page()
	_challenge_requests_page.visible = true
	_challenge_requests_page.move_to_front()
	_set_shell_swipe_enabled(false)


func _close_challenge_requests_page() -> void:
	_close_friend_detail()
	if _challenge_requests_page != null:
		_challenge_requests_page.visible = false
	if (_friends_page == null or not _friends_page.visible) and (
		_friend_requests_page == null or not _friend_requests_page.visible
	):
		_set_shell_swipe_enabled(true)


func _ensure_challenge_requests_page() -> void:
	if _challenge_requests_page != null and is_instance_valid(_challenge_requests_page):
		return

	_challenge_requests_page = Control.new()
	_challenge_requests_page.name = "ChallengeRequestsPage"
	_challenge_requests_page.visible = false
	_challenge_requests_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_challenge_requests_page.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_challenge_requests_page)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.WHITE
	bg.material = UiTokens.page_bg_material_for_tab(ScenePaths.Tab.SOCIAL)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_challenge_requests_page.add_child(bg)

	var page_margin := MarginContainer.new()
	page_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_margin.add_theme_constant_override("margin_left", 10)
	page_margin.add_theme_constant_override("margin_right", 10)
	page_margin.add_theme_constant_override("margin_top", 10)
	page_margin.add_theme_constant_override("margin_bottom", 10)
	_challenge_requests_page.add_child(page_margin)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(true, 14))
	page_margin.add_child(panel)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 14)
	inner.add_theme_constant_override("margin_right", 14)
	inner.add_theme_constant_override("margin_top", 14)
	inner.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(inner)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	var back := Button.new()
	back.text = "< " + tr("UI_BACK")
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", UiScale.font(16))
	back.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	var empty := StyleBoxEmpty.new()
	back.add_theme_stylebox_override("normal", empty)
	back.add_theme_stylebox_override("hover", empty)
	back.add_theme_stylebox_override("pressed", empty)
	back.pressed.connect(_close_challenge_requests_page)
	PressScaleUtil.wire(back, self)
	header.add_child(back)

	var page_title := Label.new()
	page_title.text = tr("UI_SOCIAL_CHALLENGE_REQUESTS").to_upper()
	page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_title.add_theme_font_size_override("font_size", UiScale.font(20))
	page_title.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	header.add_child(page_title)

	var spacer := Control.new()
	spacer.custom_minimum_size.x = 72
	header.add_child(spacer)

	var scroll_box := ScrollContainer.new()
	scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_box.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	vbox.add_child(scroll_box)

	_challenge_requests_list = VBoxContainer.new()
	_challenge_requests_list.add_theme_constant_override("separation", 10)
	_challenge_requests_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_box.add_child(_challenge_requests_list)


func _populate_challenge_requests_page() -> void:
	if _challenge_requests_list == null:
		return
	_prune_expired_challenge_requests()
	while _challenge_requests_list.get_child_count() > 0:
		var child := _challenge_requests_list.get_child(0)
		_challenge_requests_list.remove_child(child)
		child.queue_free()
	if _challenge_requests.is_empty():
		var empty := Label.new()
		empty.text = tr("UI_SOCIAL_CHALLENGE_REQUESTS_EMPTY")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", UiScale.font(18))
		empty.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
		_challenge_requests_list.add_child(empty)
		return
	for request in _challenge_requests:
		if typeof(request) != TYPE_DICTIONARY:
			continue
		_challenge_requests_list.add_child(_challenge_request_row(request))
	ScrollTouch.let_drags_through(_challenge_requests_list)


func _friend_chip(friend: Dictionary) -> Control:
	## Framed avatar from cosmetics (demo look keyed by name when missing).
	const AVATAR := 80.0
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(96, 138)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(col)

	var friend_name := str(friend.get("name", ""))
	var cosmetics: Dictionary = friend.get("cosmetics", {})
	if cosmetics.is_empty():
		cosmetics = ShopCatalog.demo_cosmetics_for(friend_name)

	var avatar := CosmeticsView.avatar(cosmetics, AVATAR)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	match str(friend.get("presence", "offline")):
		"online":
			avatar.set_presence(CircularAvatar.Presence.ONLINE)
		"away":
			avatar.set_presence(CircularAvatar.Presence.AWAY)
		_:
			avatar.set_presence(CircularAvatar.Presence.OFFLINE)
	col.add_child(avatar)

	var name_label := Label.new()
	name_label.text = friend_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override(
		"font_size",
		UiScale.font(UiTokens.pseudo_font_size(name_label.text))
	)
	name_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	col.add_child(name_label)

	var level_label := Label.new()
	level_label.text = "Lv.%d" % int(friend.get("level", 1))
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.add_theme_font_size_override("font_size", UiScale.font(13))
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
	_friend_backdrop.color = Color(0, 0, 0, 0.5)
	_friend_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_friend_backdrop.gui_input.connect(_on_friend_backdrop_gui_input)
	add_child(_friend_backdrop)

	## Full-rect center host so the sheet stays dead-center of the Social page.
	var center := CenterContainer.new()
	center.name = "FriendDetailCenter"
	center.visible = false
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_friend_detail_panel = PanelContainer.new()
	_friend_detail_panel.visible = true
	_friend_detail_panel.custom_minimum_size = Vector2(480, 0)
	var surface := UiStyle.social_surface(true, 0)
	## Transparent fill so the friend's banner reads as the sheet background.
	surface.bg_color = Color(0, 0, 0, 0)
	_friend_detail_panel.add_theme_stylebox_override("panel", surface)
	center.add_child(_friend_detail_panel)

	_friend_detail_banner = CosmeticsView.banner("", Vector2.ZERO, UiTokens.PROFILE_CARD_RADIUS)
	_friend_detail_panel.add_child(_friend_detail_banner)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 20)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 18)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friend_detail_panel.add_child(pad)

	_friend_detail_body = VBoxContainer.new()
	_friend_detail_body.add_theme_constant_override("separation", 14)
	_friend_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(_friend_detail_body)


func _friend_detail_center() -> CenterContainer:
	return get_node_or_null("FriendDetailCenter") as CenterContainer


func _open_friend_detail(friend: Dictionary) -> void:
	_ensure_friend_detail_overlay()
	_selected_friend = friend.duplicate(true)
	_apply_friend_detail_banner(friend)
	_populate_friend_detail(friend)
	_friend_backdrop.visible = true
	var center := _friend_detail_center()
	if center != null:
		center.visible = true
	_friend_detail_panel.visible = true
	_friend_backdrop.move_to_front()
	if center != null:
		center.move_to_front()
	_set_shell_swipe_enabled(false)
	call_deferred("_fit_friend_detail_panel")


func _apply_friend_detail_banner(friend: Dictionary) -> void:
	if _friend_detail_banner == null:
		return
	var cosmetics: Dictionary = friend.get("cosmetics", {})
	if cosmetics.is_empty():
		cosmetics = ShopCatalog.demo_cosmetics_for(str(friend.get("name", "")))
	_friend_detail_banner.set_banner(str(cosmetics.get("banner", "")))


func _fit_friend_detail_panel() -> void:
	## Shrink sheet height to content so no empty band sits above the CTA.
	if _friend_detail_panel == null or _friend_detail_body == null:
		return
	var pad_h := 38.0 ## top 20 + bottom 18
	var content_h := _friend_detail_body.get_combined_minimum_size().y
	if content_h < 1.0:
		content_h = _friend_detail_body.size.y
	var h := maxf(content_h + pad_h, 120.0)
	var max_w := maxf(size.x - 32.0, 320.0)
	var w := minf(480.0, max_w)
	_friend_detail_panel.custom_minimum_size = Vector2(w, h)


func _close_friend_detail() -> void:
	if _friend_backdrop != null:
		_friend_backdrop.visible = false
	var center := _friend_detail_center()
	if center != null:
		center.visible = false
	if _friend_detail_panel != null:
		_friend_detail_panel.visible = false
	_selected_friend.clear()
	var friends_open := _friends_page != null and _friends_page.visible
	var requests_open := _friend_requests_page != null and _friend_requests_page.visible
	var challenge_requests_open := (
		_challenge_requests_page != null and _challenge_requests_page.visible
	)
	if not friends_open and not requests_open and not challenge_requests_open:
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


func _open_friends_page() -> void:
	_ensure_friends_page()
	_populate_friends_page()
	_friends_page.visible = true
	_friends_page.move_to_front()
	_set_shell_swipe_enabled(false)


func _close_friends_page() -> void:
	_close_friend_detail()
	if _friends_page != null:
		_friends_page.visible = false
	if (_friend_requests_page == null or not _friend_requests_page.visible) and (
		_challenge_requests_page == null or not _challenge_requests_page.visible
	):
		_set_shell_swipe_enabled(true)


func _ensure_friends_page() -> void:
	if _friends_page != null and is_instance_valid(_friends_page):
		return

	_friends_page = Control.new()
	_friends_page.name = "FriendsPage"
	_friends_page.visible = false
	_friends_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_friends_page.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_friends_page)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.WHITE
	bg.material = UiTokens.page_bg_material_for_tab(ScenePaths.Tab.SOCIAL)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_friends_page.add_child(bg)

	var page_margin := MarginContainer.new()
	page_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_margin.add_theme_constant_override("margin_left", 10)
	page_margin.add_theme_constant_override("margin_right", 10)
	page_margin.add_theme_constant_override("margin_top", 10)
	page_margin.add_theme_constant_override("margin_bottom", 10)
	_friends_page.add_child(page_margin)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(true, 14))
	page_margin.add_child(panel)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 14)
	inner.add_theme_constant_override("margin_right", 14)
	inner.add_theme_constant_override("margin_top", 14)
	inner.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(inner)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	var back := Button.new()
	back.text = "< " + tr("UI_BACK")
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", UiScale.font(16))
	back.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	var empty := StyleBoxEmpty.new()
	back.add_theme_stylebox_override("normal", empty)
	back.add_theme_stylebox_override("hover", empty)
	back.add_theme_stylebox_override("pressed", empty)
	back.pressed.connect(_close_friends_page)
	PressScaleUtil.wire(back, self)
	header.add_child(back)

	var title_row := HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(title_row)

	var page_title := Label.new()
	page_title.text = tr("UI_SOCIAL_FRIENDS").to_upper()
	page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_title.add_theme_font_size_override("font_size", UiScale.font(20))
	page_title.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	title_row.add_child(page_title)

	var spacer := Control.new()
	spacer.custom_minimum_size.x = 72
	header.add_child(spacer)

	var scroll_box := ScrollContainer.new()
	scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_box.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll_box.resized.connect(_fit_friends_page_grid)
	vbox.add_child(scroll_box)
	_friends_page_scroll = scroll_box

	_friends_page_grid = GridContainer.new()
	_friends_page_grid.columns = 4
	_friends_page_grid.add_theme_constant_override("h_separation", 10)
	_friends_page_grid.add_theme_constant_override("v_separation", 14)
	_friends_page_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_box.add_child(_friends_page_grid)


func _populate_friends_page() -> void:
	if _friends_page_grid == null:
		return
	while _friends_page_grid.get_child_count() > 0:
		var child := _friends_page_grid.get_child(0)
		_friends_page_grid.remove_child(child)
		child.queue_free()
	for friend in _get_friends():
		if typeof(friend) != TYPE_DICTIONARY:
			continue
		_friends_page_grid.add_child(_friend_chip(friend))
	ScrollTouch.let_drags_through(_friends_page_grid)
	call_deferred("_fit_friends_page_grid")


func _fit_friends_page_grid() -> void:
	## Stretch chips so each row fills the sheet width (GridContainer won't do it alone).
	if _friends_page_scroll == null or _friends_page_grid == null:
		return
	var width := _friends_page_scroll.size.x
	if width <= 1.0:
		return
	var cols := maxi(_friends_page_grid.columns, 1)
	var sep := _friends_page_grid.get_theme_constant("h_separation")
	var cell_w := floorf((width - float(sep * (cols - 1))) / float(cols))
	cell_w = maxf(cell_w, 72.0)
	for child in _friends_page_grid.get_children():
		if child is Control:
			(child as Control).custom_minimum_size.x = cell_w
	_friends_page_grid.custom_minimum_size.x = width


func _populate_friend_detail(friend: Dictionary) -> void:
	while _friend_detail_body.get_child_count() > 0:
		var child := _friend_detail_body.get_child(0)
		_friend_detail_body.remove_child(child)
		child.free()

	var cat_id := str(friend.get("best_category_id", ""))
	var cat_accent := UiTokens.accent_for_category(cat_id) if not cat_id.is_empty() else UiTokens.ACCENT_SOCIAL
	var last_won := bool(friend.get("last_won", false))

	## Header: framed avatar + name/meta + menu.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	_friend_detail_body.add_child(header)

	var friend_name := str(friend.get("name", ""))
	var cosmetics: Dictionary = friend.get("cosmetics", {})
	if cosmetics.is_empty():
		cosmetics = ShopCatalog.demo_cosmetics_for(friend_name)

	var avatar := CosmeticsView.avatar(cosmetics, 128.0)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	match str(friend.get("presence", "offline")):
		"online":
			avatar.set_presence(CircularAvatar.Presence.ONLINE)
		"away":
			avatar.set_presence(CircularAvatar.Presence.AWAY)
		_:
			avatar.set_presence(CircularAvatar.Presence.OFFLINE)
	header.add_child(avatar)

	var identity := VBoxContainer.new()
	identity.add_theme_constant_override("separation", 4)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(identity)

	var name_label := Label.new()
	name_label.text = friend_name
	name_label.add_theme_font_size_override(
		"font_size",
		UiScale.font(UiTokens.pseudo_font_size(name_label.text, UiTokens.PSEUDO_FONT_SIZE_DETAIL))
	)
	name_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	identity.add_child(name_label)

	var meta := Label.new()
	meta.text = "%s %d" % [
		tr("UI_PROFILE_LEVEL_CAPTION"),
		int(friend.get("level", 1)),
	]
	meta.add_theme_font_size_override("font_size", UiScale.font(16))
	meta.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	identity.add_child(meta)

	var menu := Button.new()
	menu.text = "⋮"
	menu.flat = true
	menu.focus_mode = Control.FOCUS_NONE
	menu.custom_minimum_size = Vector2(34, 34)
	menu.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	menu.add_theme_font_size_override("font_size", UiScale.font(22))
	menu.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	var menu_bg := StyleBoxFlat.new()
	menu_bg.bg_color = Color(1, 1, 1, 0.06)
	menu_bg.set_corner_radius_all(17)
	var menu_empty := StyleBoxEmpty.new()
	menu.add_theme_stylebox_override("normal", menu_bg)
	menu.add_theme_stylebox_override("hover", menu_bg)
	menu.add_theme_stylebox_override("pressed", menu_empty)
	menu.add_theme_stylebox_override("focus", menu_empty)
	header.add_child(menu)

	## Best subject row.
	_friend_detail_body.add_child(_friend_best_subject_card(friend, cat_accent))

	## Three stat tiles.
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friend_detail_body.add_child(stats)

	stats.add_child(_friend_stat_tile(
		"🎯",
		Color(1.0, 0.55, 0.22, 1),
		tr("UI_SOCIAL_FRIEND_ACCURACY").to_upper(),
		"%.0f%%" % float(friend.get("best_accuracy", 0.0)),
		"",
		UiTokens.PROFILE_TEXT
	))
	stats.add_child(_friend_stat_tile(
		"⚔️",
		UiTokens.ACCENT_SOCIAL,
		tr("UI_SOCIAL_FRIEND_H2H").to_upper(),
		_friend_h2h_label(friend),
		"",
		UiTokens.PROFILE_TEXT
	))
	stats.add_child(_friend_stat_tile(
		"🎮",
		UiTokens.FEEDBACK_WRONG,
		tr("UI_SOCIAL_FRIEND_LAST_GAME").to_upper(),
		tr("UI_PROFILE_WIN") if last_won else tr("UI_PROFILE_LOSS"),
		str(friend.get("last_game_subject", "")),
		UiTokens.FEEDBACK_CORRECT if last_won else UiTokens.FEEDBACK_WRONG
	))

	## Challenge CTA.
	var challenge := Button.new()
	challenge.focus_mode = Control.FOCUS_NONE
	challenge.custom_minimum_size.y = 56
	challenge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var challenge_style := StyleBoxFlat.new()
	challenge_style.bg_color = UiTokens.ACCENT_SOCIAL
	challenge_style.set_corner_radius_all(16)
	challenge_style.content_margin_left = 16
	challenge_style.content_margin_right = 16
	challenge_style.content_margin_top = 12
	challenge_style.content_margin_bottom = 12
	challenge_style.shadow_color = Color(UiTokens.ACCENT_SOCIAL.r, UiTokens.ACCENT_SOCIAL.g, UiTokens.ACCENT_SOCIAL.b, 0.35)
	challenge_style.shadow_size = 10
	challenge_style.shadow_offset = Vector2(0, 4)
	var challenge_hover := challenge_style.duplicate() as StyleBoxFlat
	challenge_hover.bg_color = UiTokens.ACCENT_SOCIAL.lightened(0.08)
	challenge.add_theme_stylebox_override("normal", challenge_style)
	challenge.add_theme_stylebox_override("hover", challenge_hover)
	challenge.add_theme_stylebox_override("pressed", challenge_style)
	challenge.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	challenge.pressed.connect(_on_challenge_friend_pressed)
	PressScaleUtil.wire(challenge, self)
	_friend_detail_body.add_child(challenge)

	var challenge_row := HBoxContainer.new()
	challenge_row.add_theme_constant_override("separation", 10)
	challenge_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	challenge_row.alignment = BoxContainer.ALIGNMENT_CENTER
	challenge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	challenge.add_child(challenge_row)

	var swords := Label.new()
	swords.text = "⚔"
	swords.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swords.add_theme_font_size_override("font_size", UiScale.font(22))
	swords.add_theme_color_override("font_color", Color(0.12, 0.06, 0.1, 1))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		swords.add_theme_font_override("font", emoji_font)
	challenge_row.add_child(swords)

	var challenge_label := Label.new()
	challenge_label.text = tr("UI_SOCIAL_FRIEND_CHALLENGE").to_upper()
	challenge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	challenge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	challenge_label.add_theme_font_size_override("font_size", UiScale.font(20))
	challenge_label.add_theme_color_override("font_color", Color(0.12, 0.06, 0.1, 1))
	challenge_row.add_child(challenge_label)

	## Divider + back.
	var divider := ColorRect.new()
	divider.custom_minimum_size.y = 1
	divider.color = Color(1, 1, 1, 0.12)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_friend_detail_body.add_child(divider)

	var close_btn := Button.new()
	close_btn.text = tr("UI_BACK")
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_btn.add_theme_font_size_override("font_size", UiScale.font(18))
	close_btn.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	var empty := StyleBoxEmpty.new()
	close_btn.add_theme_stylebox_override("normal", empty)
	close_btn.add_theme_stylebox_override("hover", empty)
	close_btn.add_theme_stylebox_override("pressed", empty)
	close_btn.pressed.connect(_close_friend_detail)
	_friend_detail_body.add_child(close_btn)
	call_deferred("_fit_friend_detail_panel")


func _friend_best_subject_card(friend: Dictionary, cat_accent: Color) -> Control:
	var cat_id := str(friend.get("best_category_id", ""))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 100
	var style := StyleBoxFlat.new()
	## Solid social tile fill so content stays readable on the full-brightness banner.
	style.bg_color = UiTokens.SOCIAL_CARD_BG_RAISED
	style.set_corner_radius_all(14)
	style.set_border_width_all(1)
	style.border_color = UiTokens.SOCIAL_CARD_BORDER
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(row)

	var cat_icon := _friend_category_icon(
		cat_id,
		str(friend.get("best_subject_icon", "🧠")),
		cat_accent,
		68
	)
	cat_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cat_icon)

	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 4)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(texts)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_BEST_CATEGORY").to_upper()
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", UiScale.font(17))
	caption.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	texts.add_child(caption)

	var subject := Label.new()
	subject.text = str(friend.get("best_subject", "—"))
	subject.clip_text = true
	subject.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subject.add_theme_font_size_override("font_size", UiScale.font(22))
	subject.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	texts.add_child(subject)

	return card


func _friend_stat_tile(
	icon_text: String,
	_icon_color: Color,
	caption: String,
	value: String,
	subtitle: String,
	value_color: Color,
	with_chevron: bool = false
) -> Control:
	const ICON_SIZE := 48.0
	const CAPTION_H := 48.0
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 172
	var style := StyleBoxFlat.new()
	## Solid social tile fill so content stays readable on the full-brightness banner.
	style.bg_color = UiTokens.SOCIAL_CARD_BG_RAISED
	style.set_corner_radius_all(14)
	style.set_border_width_all(1)
	style.border_color = UiTokens.SOCIAL_CARD_BORDER
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(col)

	## Fixed-height icon band so the 3 sibling tiles share the same icon baseline.
	var icon_row := HBoxContainer.new()
	icon_row.custom_minimum_size.y = ICON_SIZE
	icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(icon_row)

	if with_chevron:
		var lead := Control.new()
		lead.custom_minimum_size.x = 16
		lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon_row.add_child(lead)

	var icon_slot := Control.new()
	icon_slot.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_row.add_child(icon_slot)
	var icon := Label.new()
	icon.text = icon_text
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_font_size_override("font_size", UiScale.font(28))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		icon.add_theme_font_override("font", emoji_font)
	icon_slot.add_child(icon)

	if with_chevron:
		var trail := HBoxContainer.new()
		trail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trail.alignment = BoxContainer.ALIGNMENT_END
		icon_row.add_child(trail)
		var chevron := Label.new()
		chevron.text = ">"
		chevron.add_theme_font_size_override("font_size", UiScale.font(16))
		chevron.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
		trail.add_child(chevron)

	## Fixed caption band tall enough for 2 wrapped lines on all 3 tiles.
	var caption_slot := Control.new()
	caption_slot.custom_minimum_size.y = CAPTION_H
	caption_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(caption_slot)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_label.max_lines_visible = 2
	caption_label.clip_text = false
	caption_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption_label.add_theme_font_size_override("font_size", UiScale.font(15))
	caption_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	caption_slot.add_child(caption_label)

	## Fixed value band so the 3 results share one baseline.
	var value_slot := Control.new()
	value_slot.custom_minimum_size.y = 34
	value_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(value_slot)

	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value_label.add_theme_font_size_override("font_size", UiScale.font(28))
	value_label.add_theme_color_override("font_color", value_color)
	value_slot.add_child(value_label)

	## Always reserve subtitle height so tiles without one stay aligned.
	var sub_slot := Control.new()
	sub_slot.custom_minimum_size.y = 18
	sub_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(sub_slot)

	var sub := Label.new()
	sub.text = subtitle
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.clip_text = true
	sub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.add_theme_font_size_override("font_size", UiScale.font(14))
	sub.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	sub_slot.add_child(sub)
	return card


func _friend_category_icon(
	category_id: String,
	icon_text: String,
	accent: Color,
	size_px: float = 36.0
) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(size_px, size_px)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r, accent.g, accent.b, 0.28)
	style.set_corner_radius_all(int(size_px * 0.5))
	bg.add_theme_stylebox_override("panel", style)
	slot.add_child(bg)

	var icon := GameAssets.make_icon_display(
		GameAssets.category_texture(category_id),
		icon_text,
		size_px,
		int(size_px * 0.72),
		0.84
	)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	_pending_challenge_friend = _selected_friend.duplicate(true)
	_challenge_friend_key = _friend_rivalry_key(_pending_challenge_friend)
	_close_friend_detail()
	_open_challenge_mode_picker()


func _open_challenge_mode_picker() -> void:
	_ensure_challenge_mode_picker()
	_challenge_mode_picker.visible = true
	_challenge_mode_picker.move_to_front()
	_set_shell_swipe_enabled(false)


func _close_challenge_mode_picker() -> void:
	if _challenge_mode_picker != null:
		_challenge_mode_picker.visible = false
	_pending_challenge_friend.clear()
	var friends_open := _friends_page != null and _friends_page.visible
	var requests_open := _friend_requests_page != null and _friend_requests_page.visible
	var challenge_requests_open := (
		_challenge_requests_page != null and _challenge_requests_page.visible
	)
	if not friends_open and not requests_open and not challenge_requests_open:
		_set_shell_swipe_enabled(true)


func _ensure_challenge_mode_picker() -> void:
	if _challenge_mode_picker != null and is_instance_valid(_challenge_mode_picker):
		return

	_challenge_mode_picker = Control.new()
	_challenge_mode_picker.name = "ChallengeModePicker"
	_challenge_mode_picker.visible = false
	_challenge_mode_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_challenge_mode_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_challenge_mode_picker)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.5)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close_challenge_mode_picker()
	)
	_challenge_mode_picker.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_challenge_mode_picker.add_child(center)

	var sheet := PanelContainer.new()
	sheet.custom_minimum_size = Vector2(360, 0)
	sheet.add_theme_stylebox_override("panel", UiStyle.social_surface(true, 0))
	center.add_child(sheet)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 16)
	sheet.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)

	var title := Label.new()
	title.text = tr("UI_SOCIAL_PICK_CHALLENGE_MODE").to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiScale.font(18))
	title.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	column.add_child(title)

	for mode in range(3):
		column.add_child(_challenge_mode_picker_btn(mode))

	var cancel := Button.new()
	cancel.text = tr("UI_SOCIAL_PICK_CHALLENGE_CANCEL").to_upper()
	cancel.flat = true
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel.add_theme_font_size_override("font_size", UiScale.font(16))
	cancel.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	var empty := StyleBoxEmpty.new()
	cancel.add_theme_stylebox_override("normal", empty)
	cancel.add_theme_stylebox_override("hover", empty)
	cancel.add_theme_stylebox_override("pressed", empty)
	cancel.pressed.connect(_close_challenge_mode_picker)
	PressScaleUtil.wire(cancel, self)
	column.add_child(cancel)


func _challenge_mode_picker_btn(mode: int) -> Button:
	var meta := _challenge_mode_meta(mode)
	var accent: Color = meta["accent"]
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size.y = 56
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = accent
	style.set_corner_radius_all(14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = accent.lightened(0.08)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = accent.darkened(0.06)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(_on_challenge_mode_picked.bind(mode))
	PressScaleUtil.wire(btn, self)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var ink := Color(0.10, 0.08, 0.12, 1)
	var icon := Label.new()
	icon.text = str(meta["icon"])
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_font_size_override("font_size", UiScale.font(22))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		icon.add_theme_font_override("font", emoji_font)
	row.add_child(icon)

	var label := Label.new()
	label.text = tr(str(meta["key"])).to_upper()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", UiScale.font(18))
	label.add_theme_color_override("font_color", ink)
	row.add_child(label)
	return btn


func _on_challenge_mode_picked(mode: int) -> void:
	if _pending_challenge_friend.is_empty():
		_close_challenge_mode_picker()
		return
	var friend := _pending_challenge_friend.duplicate(true)
	_close_challenge_mode_picker()
	_send_friend_challenge(friend, mode)


func _send_friend_challenge(friend: Dictionary, mode: int) -> void:
	## Persist outbox + stub network; inbox stays server/demo (no self-receive).
	var friend_key := _friend_rivalry_key(friend)
	var friend_name := str(friend.get("name", ""))
	_challenge_friend_key = friend_key
	SaveManager.record_outgoing_challenge(
		friend_key,
		friend_name,
		mode,
		int(friend.get("level", 1))
	)
	NetworkManager.send_friend_challenge(friend_key, mode)
	_show_status(tr("UI_SOCIAL_FRIEND_CHALLENGE_SENT").format({"name": friend_name}))


func _friend_rivalry_key(friend: Dictionary) -> String:
	var id := str(friend.get("id", "")).strip_edges()
	if not id.is_empty():
		return id
	return str(friend.get("name", "")).strip_edges().to_lower()


func _friend_h2h_label(friend: Dictionary) -> String:
	var row := SaveManager.get_friend_rivalry(_friend_rivalry_key(friend))
	return "%d-%d" % [int(row.get("wins", 0)), int(row.get("losses", 0))]


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
		"best_subject_level": maxi(1, int(round(best_accuracy * 0.32))),
		"last_won": last_won,
		"last_category_id": last_category_id,
		"last_game_subject": ProfileSnapshot._resolve_category_name(last_category_id, locale),
		"wins": wins,
	}


func _create_section() -> PanelContainer:
	## Kept for SHOW_ASYNC_CHALLENGE_TILES — not mounted while the flag is false.
	## Category picker: icon disc + name under (not chip pills).
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 0))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	pad.add_child(vbox)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_CREATE_CHALLENGE").to_upper()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_theme_font_size_override("font_size", UiScale.font(18))
	caption.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(caption)

	var category_scroll := ScrollContainer.new()
	category_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	category_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	category_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_scroll.custom_minimum_size.y = 164
	vbox.add_child(category_scroll)

	var category_row := HBoxContainer.new()
	category_row.add_theme_constant_override("separation", 22)
	category_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	category_scroll.add_child(category_row)
	for category in _categories:
		if typeof(category) != TYPE_DICTIONARY:
			continue
		category_row.add_child(_challenge_category_chip(category))

	var create_button := Button.new()
	create_button.text = tr("UI_SOCIAL_CREATE_BUTTON").to_upper()
	create_button.focus_mode = Control.FOCUS_NONE
	create_button.custom_minimum_size.y = 52
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## Theme Button hover is translucent cyan + dark ink — unreadable on social tiles.
	var create_style := StyleBoxFlat.new()
	create_style.bg_color = UiTokens.ACCENT_SOCIAL
	create_style.set_corner_radius_all(16)
	create_style.content_margin_left = 16
	create_style.content_margin_right = 16
	create_style.content_margin_top = 12
	create_style.content_margin_bottom = 12
	var create_hover := create_style.duplicate() as StyleBoxFlat
	create_hover.bg_color = UiTokens.ACCENT_SOCIAL.lightened(0.10)
	var create_pressed := create_style.duplicate() as StyleBoxFlat
	create_pressed.bg_color = UiTokens.ACCENT_SOCIAL.darkened(0.06)
	create_button.add_theme_stylebox_override("normal", create_style)
	create_button.add_theme_stylebox_override("hover", create_hover)
	create_button.add_theme_stylebox_override("pressed", create_pressed)
	create_button.add_theme_stylebox_override("focus", create_hover)
	create_button.add_theme_color_override("font_color", Color(0.12, 0.06, 0.1, 1))
	create_button.add_theme_color_override("font_hover_color", Color(0.12, 0.06, 0.1, 1))
	create_button.add_theme_color_override("font_pressed_color", Color(0.12, 0.06, 0.1, 1))
	create_button.add_theme_color_override("font_focus_color", Color(0.12, 0.06, 0.1, 1))
	create_button.add_theme_font_size_override("font_size", UiScale.font(18))
	create_button.pressed.connect(_on_create_pressed)
	PressScaleUtil.wire(create_button, self)
	vbox.add_child(create_button)

	return panel


func _challenge_category_chip(category: Dictionary) -> Control:
	const ICON := 72.0
	const CHIP_W := 118.0
	var category_id := str(category.get("id", ""))
	var accent := UiTokens.accent_for_category(category_id)
	var selected := category_id == _selected_category_id

	var wrap := Control.new()
	## Fixed width so neighbour labels never collide; names wrap inside.
	wrap.custom_minimum_size = Vector2(CHIP_W, 152)
	wrap.clip_contents = true

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(col)

	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(ICON, ICON)
	icon_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon_wrap)

	var disc := Panel.new()
	disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc_style := StyleBoxFlat.new()
	disc_style.bg_color = Color(accent.r, accent.g, accent.b, 0.55 if selected else 0.28)
	disc_style.set_corner_radius_all(int(ICON * 0.5))
	disc_style.set_border_width_all(3 if selected else 2)
	disc_style.border_color = accent if selected else Color(accent.r, accent.g, accent.b, 0.55)
	if selected:
		disc_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
		disc_style.shadow_size = 8
	disc.add_theme_stylebox_override("panel", disc_style)
	icon_wrap.add_child(disc)

	var icon_display := GameAssets.make_circular_icon_display(
		GameAssets.category_texture(category_id),
		ProfileSnapshot._category_icon(category_id),
		ICON,
		34,
		GameAssets.ROUND_ICON_INSET
	)
	icon_display.modulate.a = 1.0 if selected else 0.72
	icon_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_wrap.add_child(icon_display)

	var name_label := Label.new()
	name_label.text = str(category.get("name", category_id))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	## Constrain width so long names wrap instead of stretching the chip.
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.clip_text = false
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size = Vector2(CHIP_W, 44)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", UiScale.font(17))
	name_label.add_theme_color_override(
		"font_color",
		UiTokens.PROFILE_TEXT if selected else UiTokens.PROFILE_TEXT_MUTED
	)
	col.add_child(name_label)

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
	hit.pressed.connect(_on_category_pressed.bind(category_id))
	PressScaleUtil.wire(hit, self)
	wrap.add_child(hit)
	wrap.set_meta("category_chip", true)
	wrap.set_meta("category_id", category_id)
	wrap.set_meta("accent", accent)
	wrap.set_meta("disc", disc)
	wrap.set_meta("icon_display", icon_display)
	wrap.set_meta("name_label", name_label)
	return wrap


func _apply_category_chip_selection() -> void:
	_apply_category_chip_selection_in(content)


func _apply_category_chip_selection_in(node: Node) -> void:
	if node is Control and bool(node.get_meta("category_chip", false)):
		_paint_category_chip(node as Control)
	for child in node.get_children():
		_apply_category_chip_selection_in(child)


func _paint_category_chip(wrap: Control) -> void:
	var category_id := str(wrap.get_meta("category_id", ""))
	var accent: Color = wrap.get_meta("accent")
	var selected := category_id == _selected_category_id
	var disc: Panel = wrap.get_meta("disc")
	var icon_display: Control = wrap.get_meta("icon_display")
	var name_label: Label = wrap.get_meta("name_label")
	if disc == null or icon_display == null or name_label == null:
		return
	const ICON := 72.0
	var disc_style := StyleBoxFlat.new()
	disc_style.bg_color = Color(accent.r, accent.g, accent.b, 0.55 if selected else 0.28)
	disc_style.set_corner_radius_all(int(ICON * 0.5))
	disc_style.set_border_width_all(3 if selected else 2)
	disc_style.border_color = accent if selected else Color(accent.r, accent.g, accent.b, 0.55)
	if selected:
		disc_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
		disc_style.shadow_size = 8
	disc.add_theme_stylebox_override("panel", disc_style)
	icon_display.modulate.a = 1.0 if selected else 0.72
	name_label.add_theme_color_override(
		"font_color",
		UiTokens.PROFILE_TEXT if selected else UiTokens.PROFILE_TEXT_MUTED
	)


func _live_search_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 10))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_LIVE_TITLE").to_upper()
	caption.add_theme_font_size_override("font_size", UiScale.font(18))
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
			var range_cups := NetworkManager.live_trophy_range
			var searching := tr("UI_SOCIAL_LIVE_SEARCHING_RANGE").format({"range": range_cups})
			if searching.begins_with("UI_SOCIAL_"):
				searching = tr("UI_SOCIAL_LIVE_SEARCHING") + " (±%d 🏆)" % range_cups
			label.text = searching
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
	vbox.add_child(_live_face_off(str(_live_my_score), str(_live_opponent_score)))

	_countdown_label = Label.new()
	_countdown_label.text = "%d" % ceili(_live_countdown)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", UiScale.font(22))
	_countdown_label.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	vbox.add_child(_countdown_label)

	var question_label := Label.new()
	question_label.text = str(_live_question.get("text", ""))
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_label.add_theme_font_size_override("font_size", UiScale.font(17))
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
		points_label.add_theme_font_size_override("font_size", UiScale.font(13))
		points_label.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
		vbox.add_child(points_label)


## Me vs opponent, each with banner, framed avatar and current score.
func _live_face_off(my_value: String, opponent_value: String, my_highlight: Color = Color(0, 0, 0, 0)) -> Control:
	return CosmeticsView.face_off(
		SaveManager.player_name, SaveManager.get_cosmetics(), my_value,
		_live_opponent_name, _live_opponent_cosmetics, opponent_value,
		640.0, my_highlight
	)


func _build_live_over_view(vbox: VBoxContainer) -> void:
	var won: bool = bool(_live_over_data.get("won", false))
	var my_score: int = int(_live_over_data.get("your_score", 0))
	var opponent_score: int = int(_live_over_data.get("opponent_score", 0))
	vbox.add_child(_live_face_off(
		str(my_score), str(opponent_score), UiTokens.PODIUM_GOLD if won else Color(0, 0, 0, 0)
	))

	var key := "UI_SOCIAL_RESULT_LOSS"
	if won:
		key = "UI_SOCIAL_RESULT_WIN"
	elif my_score == opponent_score:
		key = "UI_SOCIAL_RESULT_TIE"

	var label := Label.new()
	label.text = tr(key).format({"my_score": my_score, "opponent_score": opponent_score})
	label.add_theme_font_size_override("font_size", UiScale.font(18))
	label.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	vbox.add_child(label)

	## Clash-style settle as soon as the live match ends.
	## Prefer opponent cups from match_over, else the value cached at match_found.
	var match_id := "live:%s" % str(_live_over_data.get("match_id", "%d-%d" % [my_score, opponent_score]))
	var opp_cups := _live_opponent_trophies_from(_live_over_data)
	if opp_cups < 0:
		opp_cups = _live_opponent_trophies
	var delta := SaveManager.settle_versus_trophies(match_id, my_score, opponent_score, opp_cups)
	if delta != 0:
		var cups := Label.new()
		var sign := "+" if delta > 0 else ""
		var line := "%s%d 🏆" % [sign, delta]
		var streak_bonus := SaveManager.last_trophy_streak_bonus
		if streak_bonus > 0:
			var bonus_label := tr("UI_TROPHY_STREAK_BONUS").format({"streak": SaveManager.versus_win_streak})
			if bonus_label.begins_with("UI_TROPHY_"):
				bonus_label = "streak x%d" % SaveManager.versus_win_streak
			line += "  ·  +%d (%s)" % [streak_bonus, bonus_label]
		var consolation := SaveManager.last_trophy_loss_consolation
		if consolation > 0:
			var cons_label := tr("UI_TROPHY_LOSS_CONSOLATION")
			if cons_label.begins_with("UI_TROPHY_"):
				cons_label = "keep going" if LocaleManager.current_locale != "fr" else "courage"
			line += "  ·  +%d (%s)" % [consolation, cons_label]
		cups.text = line
		cups.add_theme_font_size_override("font_size", UiScale.font(16))
		cups.add_theme_color_override("font_color", UiTokens.PODIUM_GOLD)
		vbox.add_child(cups)

	var close_button := Button.new()
	close_button.text = tr("UI_SOCIAL_LIVE_CLOSE")
	close_button.pressed.connect(_on_live_close_pressed)
	vbox.add_child(close_button)


func _join_section() -> PanelContainer:
	## Kept for SHOW_ASYNC_CHALLENGE_TILES — not mounted while the flag is false.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.social_surface(false, 10))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_JOIN_CHALLENGE").to_upper()
	caption.add_theme_font_size_override("font_size", UiScale.font(18))
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
	join_button.text = tr("UI_SOCIAL_JOIN_BUTTON").to_upper()
	join_button.focus_mode = Control.FOCUS_NONE
	join_button.custom_minimum_size = Vector2(120, 52)
	## Same opaque CTA as Create — theme hover is unreadable on social tiles.
	var join_style := StyleBoxFlat.new()
	join_style.bg_color = UiTokens.ACCENT_SOCIAL
	join_style.set_corner_radius_all(16)
	join_style.content_margin_left = 16
	join_style.content_margin_right = 16
	join_style.content_margin_top = 12
	join_style.content_margin_bottom = 12
	var join_hover := join_style.duplicate() as StyleBoxFlat
	join_hover.bg_color = UiTokens.ACCENT_SOCIAL.lightened(0.10)
	var join_pressed := join_style.duplicate() as StyleBoxFlat
	join_pressed.bg_color = UiTokens.ACCENT_SOCIAL.darkened(0.06)
	join_button.add_theme_stylebox_override("normal", join_style)
	join_button.add_theme_stylebox_override("hover", join_hover)
	join_button.add_theme_stylebox_override("pressed", join_pressed)
	join_button.add_theme_stylebox_override("focus", join_hover)
	join_button.add_theme_color_override("font_color", Color(0.12, 0.06, 0.1, 1))
	join_button.add_theme_color_override("font_hover_color", Color(0.12, 0.06, 0.1, 1))
	join_button.add_theme_color_override("font_pressed_color", Color(0.12, 0.06, 0.1, 1))
	join_button.add_theme_color_override("font_focus_color", Color(0.12, 0.06, 0.1, 1))
	join_button.add_theme_font_size_override("font_size", UiScale.font(18))
	join_button.pressed.connect(_on_join_pressed.bind(code_input))
	PressScaleUtil.wire(join_button, self)
	row.add_child(join_button)

	return panel


func _challenge_card() -> PanelContainer:
	## Kept for SHOW_ASYNC_CHALLENGE_TILES — active challenge sheet after create/join.
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
	header.add_theme_font_size_override("font_size", UiScale.font(18))
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
		status_label.add_theme_font_size_override("font_size", UiScale.font(13))
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
	var text := tr(key).format({"my_score": my_score, "opponent_score": opponent_score})
	## Ensure H2H is recorded (idempotent) then show the running tally.
	_record_friend_challenge_if_needed()
	var friend_key := _challenge_friend_key
	if friend_key.is_empty():
		var code := str(_current_challenge.get("code", ""))
		var theirs := str(
			_current_challenge.get("opponent_id" if is_challenger else "challenger_id", "")
		).strip_edges()
		friend_key = theirs if not theirs.is_empty() else ("challenge:%s" % code)
	var h2h := SaveManager.get_friend_rivalry(friend_key)
	var h2h_caption := tr("UI_SOCIAL_FRIEND_H2H_SCORE").format({
		"wins": int(h2h.get("wins", 0)),
		"losses": int(h2h.get("losses", 0)),
	})
	if h2h_caption.begins_with("UI_SOCIAL_"):
		h2h_caption = "H2H %d-%d" % [int(h2h.get("wins", 0)), int(h2h.get("losses", 0))]
	text += "  ·  " + h2h_caption
	label.text = text
	label.add_theme_font_size_override("font_size", UiScale.font(15))
	label.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	return label


func _is_challenger() -> bool:
	return not NetworkManager.player_id.is_empty() \
		and str(_current_challenge.get("challenger_id", "")) == NetworkManager.player_id


func _my_score_submitted() -> bool:
	var field := "challenger_score" if _is_challenger() else "opponent_score"
	return typeof(_current_challenge.get(field)) != TYPE_NIL


func _on_category_pressed(category_id: String) -> void:
	if _selected_category_id == category_id:
		return
	_selected_category_id = category_id
	## Update chips in place — full rebuild was resetting scroll to top.
	_apply_category_chip_selection()


func _on_create_pressed() -> void:
	if _selected_category_id.is_empty():
		return
	_show_status(tr("UI_SOCIAL_CREATING"))
	NetworkManager.create_challenge(_selected_category_id)


func _on_challenge_created(challenge: Dictionary) -> void:
	_current_challenge = challenge
	_status_text = ""
	_rebuild_content(true)


func _on_challenge_create_failed() -> void:
	_show_status(tr("UI_SOCIAL_ERROR_OFFLINE"))


func _on_join_pressed(code_input: LineEdit) -> void:
	var code := code_input.text.strip_edges().to_upper()
	if code.is_empty():
		return
	_show_status(tr("UI_SOCIAL_JOINING"))
	NetworkManager.join_challenge(code)


func _on_challenge_joined(challenge: Dictionary) -> void:
	_current_challenge = challenge
	_status_text = ""
	_rebuild_content(true)


func _on_challenge_join_failed(_error_code: int) -> void:
	_show_status(tr("UI_SOCIAL_ERROR_JOIN"))


func _on_refresh_pressed() -> void:
	NetworkManager.fetch_challenge(str(_current_challenge.get("code", "")))


func _on_challenge_fetched(challenge: Dictionary) -> void:
	_current_challenge = challenge
	_record_friend_challenge_if_needed()
	_rebuild_content()


func _record_friend_challenge_if_needed() -> void:
	## Casual friend challenges: H2H + XP only — never Clash trophies (anti-farm).
	if str(_current_challenge.get("status", "")) != "completed":
		return
	var code := str(_current_challenge.get("code", ""))
	if code.is_empty():
		return
	var is_challenger := _is_challenger()
	var my_score: int = int(_current_challenge.get("challenger_score" if is_challenger else "opponent_score", 0))
	var opponent_score: int = int(_current_challenge.get("opponent_score" if is_challenger else "challenger_score", 0))
	var friend_key := _challenge_friend_key
	if friend_key.is_empty():
		## Fallback: other player's id from payload, else challenge code namespace.
		var theirs := str(
			_current_challenge.get("opponent_id" if is_challenger else "challenger_id", "")
		).strip_edges()
		friend_key = theirs if not theirs.is_empty() else ("challenge:%s" % code)
	SaveManager.record_friend_rivalry(friend_key, my_score, opponent_score, code)


func _on_challenge_fetch_failed(_code: String) -> void:
	_status_text = tr("UI_SOCIAL_ERROR_OFFLINE")
	_rebuild_content()


func _on_copy_code_pressed(code: String) -> void:
	DisplayServer.clipboard_set(code)


func _on_new_challenge_pressed() -> void:
	_current_challenge = {}
	_challenge_friend_key = ""
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


func _on_live_search_range_changed(_trophy_range: int) -> void:
	if _live_state == "searching":
		_rebuild_content()


func _on_live_cancel_pressed() -> void:
	NetworkManager.stop_live_matchmaking()
	_live_state = "idle"
	_live_opponent_trophies = -1
	_rebuild_content()


func _on_live_match_found(data: Dictionary) -> void:
	_live_opponent_name = str(data.get("opponent_name", ""))
	_live_opponent_trophies = _live_opponent_trophies_from(data)
	var cosmetics: Variant = data.get("opponent_cosmetics", {})
	_live_opponent_cosmetics = cosmetics if typeof(cosmetics) == TYPE_DICTIONARY else {}
	_live_my_score = 0
	_live_opponent_score = 0


func _live_opponent_trophies_from(data: Dictionary) -> int:
	## Server contract: top-level opponent_trophies, or nested under opponent {}.
	if data.has("opponent_trophies"):
		return maxi(int(data.get("opponent_trophies", -1)), -1)
	var nested: Variant = data.get("opponent", {})
	if typeof(nested) == TYPE_DICTIONARY and nested.has("trophies"):
		return maxi(int(nested.get("trophies", -1)), -1)
	return -1


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
	var cups := _live_opponent_trophies_from(data)
	if cups >= 0:
		_live_opponent_trophies = cups
	_live_state = "over"
	_rebuild_content()


func _on_live_error(_reason: String) -> void:
	_live_state = "idle"
	_live_opponent_trophies = -1
	_status_text = tr("UI_SOCIAL_ERROR_OFFLINE")
	_rebuild_content()


func _on_live_close_pressed() -> void:
	_live_state = "idle"
	_live_over_data = {}
	_live_opponent_trophies = -1
	_rebuild_content()


func _on_locale_changed(_locale: String) -> void:
	_apply()
