class_name ShopPage
extends Control

## Full-screen shop opened from the top bar, in two tabs:
## - Boutique: coin balance, featured items, then a grid of items coloured by rarity.
## - Casier: the player's animal with its frame, slots (avatar / frame) and owned items.
## Items come from ShopCatalog; purchases are local (SaveManager.buy_item) for now.

signal closed

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const CircularAvatarScript = preload("res://scripts/ui/circular_avatar.gd")

const ACCENT := UiTokens.PODIUM_GOLD
const COIN_FILL := Color(0.97, 0.78, 0.26, 1)
const COIN_EDGE := Color(0.78, 0.52, 0.08, 1)
const TAB_STORE := "store"
const TAB_LOCKER := "locker"
const TAB_PASS := "pass"
const PASS_GOLD := Color(1.0, 0.78, 0.2, 1)
const PASS_FREE := Color(0.36, 0.75, 1.0, 1)
const PASS_COLUMN_WIDTH := 150.0
const PAGE_WIDTH := 680.0

var _tab: String = TAB_STORE
var _locker_slot: String = ShopCatalog.KIND_AVATAR

var _margin: MarginContainer
var _back_button: Button
var _coin_label: Label
var _tab_buttons: Dictionary = {}
var _scroll: ScrollContainer
var _content: VBoxContainer

var _detail_backdrop: ColorRect
var _detail_panel: PanelContainer
var _detail_item: Dictionary = {}


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/tab_page_bg.gdshader") as Shader
	mat.set_shader_parameter("accent", ACCENT)
	mat.set_shader_parameter("deep", UiTokens.BG_CREAM)
	bg.material = mat
	add_child(bg)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_margin.add_child(column)

	column.add_child(_build_header())
	column.add_child(_build_tabs())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 14)
	_scroll.add_child(_content)

	_build_detail_popup()

	SafeArea.changed.connect(_apply_safe_area)
	_apply_safe_area()
	LocaleManager.locale_changed.connect(func(_locale: String) -> void: _rebuild())
	NetworkManager.pass_received.connect(func(_state: Dictionary) -> void:
		if visible and _tab == TAB_PASS:
			_rebuild()
	)
	NetworkManager.pass_reward_claimed.connect(func(_result: Dictionary) -> void: AudioManager.play("correct"))
	NetworkManager.pass_claim_failed.connect(func(_reason: String) -> void: AudioManager.play("wrong"))


func open(tab: String = TAB_STORE) -> void:
	_tab = tab
	NetworkManager.fetch_pass()
	_close_detail()
	_rebuild()
	visible = true
	move_to_front()
	_back_button.grab_focus()


## Back closes the purchase popup first, then the page.
func close() -> void:
	if _detail_panel.visible:
		_close_detail()
		return
	if not visible:
		return
	visible = false
	closed.emit()


func _apply_safe_area() -> void:
	_margin.add_theme_constant_override("margin_left", 20)
	_margin.add_theme_constant_override("margin_right", 20)
	_margin.add_theme_constant_override("margin_top", 14 + int(SafeArea.top))
	_margin.add_theme_constant_override("margin_bottom", 14 + int(SafeArea.bottom))


# --- Chrome -----------------------------------------------------------------

func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	_back_button = Button.new()
	_back_button.focus_mode = Control.FOCUS_ALL
	_back_button.pressed.connect(close)
	row.add_child(_back_button)
	PressScaleUtil.wire(_back_button, self)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var pill := PanelContainer.new()
	var pill_style := UiStyle.filled(Color(0.05, 0.04, 0.12, 0.55), 22)
	pill_style.content_margin_left = 14
	pill_style.content_margin_right = 18
	pill_style.content_margin_top = 6
	pill_style.content_margin_bottom = 6
	pill.add_theme_stylebox_override("panel", pill_style)
	row.add_child(pill)
	var coins := HBoxContainer.new()
	coins.add_theme_constant_override("separation", 8)
	pill.add_child(coins)
	coins.add_child(_make_coin(26))
	_coin_label = Label.new()
	_coin_label.add_theme_font_size_override("font_size", UiScale.font(20))
	_coin_label.add_theme_color_override("font_color", Color.WHITE)
	coins.add_child(_coin_label)
	return row


func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for tab in [TAB_STORE, TAB_PASS, TAB_LOCKER]:
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 56
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", UiScale.font(19))
		button.pressed.connect(_on_tab_pressed.bind(tab))
		row.add_child(button)
		_tab_buttons[tab] = button
	return row


func _style_tabs() -> void:
	for tab in _tab_buttons:
		var button: Button = _tab_buttons[tab]
		var active: bool = tab == _tab
		button.text = tr({TAB_STORE: "UI_SHOP_STORE", TAB_PASS: "UI_PASS_TAB", TAB_LOCKER: "UI_SHOP_LOCKER"}[tab]).to_upper()
		var style := UiStyle.filled(ACCENT if active else Color(0.05, 0.04, 0.12, 0.45), 18)
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, style)
		var ink := UiTokens.INK if active else Color(1, 1, 1, 0.8)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(key, ink)


func _on_tab_pressed(tab: String) -> void:
	if tab == _tab:
		return
	_tab = tab
	AudioManager.play("click")
	_rebuild()
	_scroll.scroll_vertical = 0


func _rebuild() -> void:
	_back_button.text = "‹  " + tr("UI_BACK")
	_coin_label.text = _format_amount(SaveManager.coins)
	_style_tabs()
	for child in _content.get_children():
		child.queue_free()
	match _tab:
		TAB_LOCKER:
			_build_locker()
		TAB_PASS:
			_build_pass()
		_:
			_build_store()
	ScrollTouch.let_drags_through(_content)


# --- Passe de combat ------------------------------------------------------------

func _build_pass() -> void:
	var state: Dictionary = NetworkManager.pass_state
	if state.is_empty():
		_content.add_child(_pass_message("UI_PASS_LOADING"))
		NetworkManager.fetch_pass()
		return
	if not bool(state.get("active", false)):
		_content.add_child(_pass_message("UI_PASS_NO_SEASON"))
		return
	_content.add_child(_pass_header(state))
	_content.add_child(_section_label("UI_PASS_REWARDS"))
	_content.add_child(_pass_track(state))
	_content.add_child(_section_label_text(tr("UI_PASS_WEEKLY").format({"week": int(state.get("week", 1))})))
	for challenge in state.get("weekly", []):
		_content.add_child(_pass_challenge_row(challenge))
	_content.add_child(_pass_xp_legend(state))


func _pass_message(key: String) -> Control:
	var label := Label.new()
	label.text = tr(key)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 200
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", UiScale.font(18))
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	return label


## Season name, days left, current tier, XP inside the tier and the premium state.
func _pass_header(state: Dictionary) -> Control:
	var tier := int(state.get("tier", 0))
	var tier_xp := int(state.get("tier_xp", 800))
	var xp := int(state.get("xp", 0))
	var max_tier := (state.get("tiers", []) as Array).size()
	var premium := bool(state.get("premium", false))

	var card := PanelContainer.new()
	var style := UiStyle.filled(Color(0.16, 0.10, 0.30, 1), 24)
	style.set_border_width_all(3)
	style.border_color = PASS_GOLD if premium else Color(1, 1, 1, 0.18)
	style.set_content_margin_all(18)
	style.shadow_color = Color(PASS_GOLD.r, PASS_GOLD.g, PASS_GOLD.b, 0.35 if premium else 0.1)
	style.shadow_size = 14
	card.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	column.add_child(top)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(96, 96)
	badge.add_theme_stylebox_override("panel", UiStyle.filled(PASS_GOLD if premium else Color(1, 1, 1, 0.12), 48))
	top.add_child(badge)
	var badge_col := VBoxContainer.new()
	badge_col.alignment = BoxContainer.ALIGNMENT_CENTER
	badge.add_child(badge_col)
	var badge_caption := Label.new()
	badge_caption.text = tr("UI_PASS_TIER").to_upper()
	badge_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_caption.add_theme_font_size_override("font_size", UiScale.font(12))
	badge_caption.add_theme_color_override("font_color", UiTokens.INK if premium else Color(1, 1, 1, 0.7))
	badge_col.add_child(badge_caption)
	var badge_value := Label.new()
	badge_value.text = str(tier)
	badge_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_value.add_theme_font_size_override("font_size", UiScale.font(34))
	badge_value.add_theme_color_override("font_color", UiTokens.INK if premium else Color.WHITE)
	badge_col.add_child(badge_value)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 4)
	top.add_child(info)
	var names: Dictionary = state.get("name", {})
	var title := Label.new()
	title.text = str(names.get(str(LocaleManager.current_locale).substr(0, 2), names.get("en", "")))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", UiScale.font(24))
	title.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(title)
	var when := Label.new()
	when.text = tr("UI_PASS_WEEK_DAYS").format({"week": int(state.get("week", 1)), "days": int(state.get("days_left", 0))})
	when.add_theme_font_size_override("font_size", UiScale.font(14))
	when.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	info.add_child(when)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 16
	bar.max_value = float(tier_xp)
	bar.value = float(tier_xp) if tier >= max_tier else float(xp % tier_xp)
	bar.add_theme_stylebox_override("background", UiStyle.progress_bg())
	bar.add_theme_stylebox_override("fill", UiStyle.progress_fill(PASS_GOLD))
	column.add_child(bar)
	var xp_line := Label.new()
	xp_line.text = tr("UI_PASS_MAXED") if tier >= max_tier else tr("UI_PASS_XP_TO_NEXT").format({
		"xp": xp % tier_xp, "need": tier_xp, "next": tier + 1,
	})
	xp_line.add_theme_font_size_override("font_size", UiScale.font(15))
	xp_line.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	column.add_child(xp_line)

	var waiting := _pass_claimables(state)
	if not waiting.is_empty():
		var claim_all := Button.new()
		claim_all.custom_minimum_size.y = 56
		claim_all.focus_mode = Control.FOCUS_NONE
		claim_all.text = tr("UI_PASS_CLAIM_ALL").format({"n": waiting.size()})
		claim_all.add_theme_font_size_override("font_size", UiScale.font(18))
		var claim_style := UiStyle.filled(UiTokens.FEEDBACK_CORRECT, 20)
		for button_state in ["normal", "hover", "pressed", "focus", "disabled"]:
			claim_all.add_theme_stylebox_override(button_state, claim_style)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
			claim_all.add_theme_color_override(key, Color.WHITE)
		claim_all.pressed.connect(func() -> void:
			claim_all.disabled = true
			_claim_all(waiting)
		)
		PressScaleUtil.wire(claim_all, self)
		column.add_child(claim_all)

	if premium:
		var owned := Label.new()
		owned.text = "★ " + tr("UI_PASS_PREMIUM_ACTIVE")
		owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		owned.add_theme_font_size_override("font_size", UiScale.font(17))
		owned.add_theme_color_override("font_color", PASS_GOLD)
		column.add_child(owned)
	else:
		var unlock := Button.new()
		unlock.custom_minimum_size.y = 60
		unlock.focus_mode = Control.FOCUS_NONE
		unlock.add_theme_font_size_override("font_size", UiScale.font(19))
		var dev := bool(state.get("dev_unlock", false))
		unlock.text = tr("UI_PASS_UNLOCK_DEV") if dev else tr("UI_PASS_UNLOCK_SOON")
		unlock.disabled = not dev
		var fill := UiStyle.filled(PASS_GOLD, 20)
		for button_state in ["normal", "hover", "pressed", "focus"]:
			unlock.add_theme_stylebox_override(button_state, fill)
		unlock.add_theme_stylebox_override("disabled", UiStyle.filled(Color(1, 1, 1, 0.12), 20))
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			unlock.add_theme_color_override(key, UiTokens.INK)
		unlock.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
		unlock.pressed.connect(func() -> void: NetworkManager.unlock_pass_premium("dev"))
		PressScaleUtil.wire(unlock, self)
		column.add_child(unlock)
	return card


## Horizontal track: one column per tier, premium reward on top, free reward below.
func _pass_track(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 470
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	scroll.add_child(row)

	var tier := int(state.get("tier", 0))
	var premium := bool(state.get("premium", false))
	var claimed: Dictionary = state.get("claimed", {})
	for entry in state.get("tiers", []):
		var number := int(entry.get("tier", 0))
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = PASS_COLUMN_WIDTH
		column.add_theme_constant_override("separation", 8)
		row.add_child(column)
		var reached := number <= tier
		var head := Label.new()
		head.text = str(number)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_size_override("font_size", UiScale.font(18))
		head.add_theme_color_override("font_color", PASS_GOLD if reached else Color(1, 1, 1, 0.45))
		column.add_child(head)
		column.add_child(_pass_reward_tile(entry.get("premium"), number, "premium",
			reached and premium, (claimed.get("premium", []) as Array).has(float(number)) or (claimed.get("premium", []) as Array).has(number), not premium))
		column.add_child(_pass_reward_tile(entry.get("free"), number, "free",
			reached, (claimed.get("free", []) as Array).has(float(number)) or (claimed.get("free", []) as Array).has(number), false))

	## Start on the first reward waiting to be claimed, else on the current tier.
	var focus_tier := tier
	var claimables := _pass_claimables(state)
	if not claimables.is_empty():
		focus_tier = int(claimables[0][0])
	var target_x := maxf(float(focus_tier - 1) * (PASS_COLUMN_WIDTH + 10.0) - 40.0, 0.0)
	scroll.ready.connect(func() -> void:
		await get_tree().process_frame
		scroll.scroll_horizontal = int(target_x)
	)
	return scroll


func _pass_reward_tile(reward: Variant, tier: int, track: String, claimable_now: bool, claimed: bool, locked: bool) -> Control:
	var accent := PASS_GOLD if track == "premium" else PASS_FREE
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(PASS_COLUMN_WIDTH, 200)
	tile.focus_mode = Control.FOCUS_NONE
	var has_reward := typeof(reward) == TYPE_DICTIONARY
	var ready_to_claim := has_reward and claimable_now and not claimed
	var style := UiStyle.filled(Color(accent.r, accent.g, accent.b, 0.30 if ready_to_claim else 0.12), 18)
	style.set_border_width_all(3 if ready_to_claim else 1)
	style.border_color = accent if ready_to_claim else Color(accent.r, accent.g, accent.b, 0.35)
	if ready_to_claim:
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.5)
		style.shadow_size = 12
	for button_state in ["normal", "hover", "pressed", "focus", "disabled"]:
		tile.add_theme_stylebox_override(button_state, style)
	tile.disabled = not ready_to_claim
	if ready_to_claim:
		tile.pressed.connect(_on_pass_claim.bind(tier, track))

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(column)
	if not has_reward:
		return tile
	var art := CenterContainer.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(art)
	art.add_child(_pass_reward_art(reward))
	var caption := Label.new()
	caption.text = _pass_reward_name(reward)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", UiScale.font(13))
	caption.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(caption)
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", UiScale.font(13))
	if claimed:
		status.text = "✓ " + tr("UI_PASS_CLAIMED")
		status.add_theme_color_override("font_color", UiTokens.FEEDBACK_CORRECT)
	elif ready_to_claim:
		status.text = tr("UI_PASS_CLAIM")
		status.add_theme_color_override("font_color", accent)
	elif locked:
		status.text = "🔒 " + tr("UI_PASS_PREMIUM")
		status.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	column.add_child(status)
	if claimed or (not ready_to_claim):
		art.modulate.a = 0.55 if not claimed else 0.8
	return tile


func _pass_reward_art(reward: Dictionary) -> Control:
	match str(reward.get("type", "")):
		"coins":
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 6)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(_make_coin(34))
			var amount := Label.new()
			amount.text = str(int(reward.get("amount", 0)))
			amount.add_theme_font_size_override("font_size", UiScale.font(24))
			amount.add_theme_color_override("font_color", Color.WHITE)
			row.add_child(amount)
			return row
		"joker":
			var joker := PanelContainer.new()
			joker.custom_minimum_size = Vector2(84, 84)
			joker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			joker.add_theme_stylebox_override("panel", UiStyle.filled(Color(0.55, 0.32, 0.95, 1), 42))
			var label := Label.new()
			label.text = "50/50" if str(reward.get("id", "")) == "joker_5050" else "+5 s"
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", UiScale.font(20))
			label.add_theme_color_override("font_color", Color.WHITE)
			joker.add_child(label)
			return joker
		"item":
			var item := ShopCatalog.get_item(str(reward.get("id", "")))
			if not item.is_empty():
				return _item_preview(item, 88)
	return Control.new()


func _pass_reward_name(reward: Dictionary) -> String:
	match str(reward.get("type", "")):
		"coins":
			return tr("UI_PASS_COINS")
		"joker":
			var count := int(reward.get("amount", 1))
			return tr("UI_PASS_JOKER") + (" ×%d" % count if count > 1 else "")
		"item":
			return ShopCatalog.display_name(ShopCatalog.get_item(str(reward.get("id", ""))))
	return ""


## [[tier, track], …] reached, not yet claimed (premium only once unlocked).
func _pass_claimables(state: Dictionary) -> Array:
	var out := []
	var tier := int(state.get("tier", 0))
	var premium := bool(state.get("premium", false))
	var claimed: Dictionary = state.get("claimed", {})
	for entry in state.get("tiers", []):
		var number := int(entry.get("tier", 0))
		if number > tier:
			break
		for track in ["free", "premium"]:
			if typeof(entry.get(track)) != TYPE_DICTIONARY or (track == "premium" and not premium):
				continue
			var done: Array = claimed.get(track, [])
			if not (done.has(number) or done.has(float(number))):
				out.append([number, track])
	return out


func _claim_all(waiting: Array) -> void:
	for pair in waiting:
		await NetworkManager.claim_pass_reward(int(pair[0]), str(pair[1]))


func _on_pass_claim(tier: int, track: String) -> void:
	AudioManager.play("click")
	NetworkManager.claim_pass_reward(tier, track)


func _pass_challenge_row(challenge: Dictionary) -> Control:
	var target := int(challenge.get("target", 1))
	var progress := int(challenge.get("progress", 0))
	var done := progress >= target
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.profile_surface(UiTokens.FEEDBACK_CORRECT if done else Color(0, 0, 0, 0), false, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	var label := Label.new()
	label.text = _challenge_text(challenge)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", UiScale.font(16))
	label.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 10
	bar.max_value = float(target)
	bar.value = float(progress)
	bar.add_theme_stylebox_override("background", UiStyle.progress_bg())
	bar.add_theme_stylebox_override("fill", UiStyle.progress_fill(UiTokens.FEEDBACK_CORRECT if done else PASS_GOLD))
	info.add_child(bar)
	var right := Label.new()
	right.text = "✓" if done else "%d / %d\n+%d XP" % [progress, target, int(challenge.get("xp", 0))]
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_theme_font_size_override("font_size", UiScale.font(14 if not done else 26))
	right.add_theme_color_override("font_color", UiTokens.FEEDBACK_CORRECT if done else PASS_GOLD)
	row.add_child(right)
	return card


func _challenge_text(challenge: Dictionary) -> String:
	var mode_names := {"classic": tr("UI_MODE_CLASSIC"), "survival": tr("UI_MODE_SURVIVAL"), "time_attack": tr("UI_MODE_TIME_ATTACK")}
	var key := "UI_PASS_CH_" + str(challenge.get("type", "")).to_upper()
	return tr(key).format({
		"n": int(challenge.get("target", 1)),
		"mode": str(mode_names.get(str(challenge.get("mode", "")), "")),
	})


func _pass_xp_legend(state: Dictionary) -> Control:
	var rules: Dictionary = state.get("xp_rules", {})
	var label := Label.new()
	label.text = tr("UI_PASS_XP_LEGEND").format({
		"duel": int(rules.get("duel", 0)), "win": int(rules.get("duel_win_bonus", 0)),
		"daily": int(rules.get("daily", 0)), "quest": int(rules.get("quest", 0)),
		"quests": int(rules.get("quests_per_day", 0)),
	})
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", UiScale.font(14))
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	return label


func _section_label_text(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", UiScale.font(16))
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	return label


# --- Boutique ---------------------------------------------------------------

func _build_store() -> void:
	var featured: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	for item in ShopCatalog.store_items():
		if bool(item.get("featured", false)):
			featured.append(item)
		else:
			others.append(item)

	if featured.is_empty() and others.is_empty():
		_content.add_child(_section_label("UI_SHOP_ITEMS"))
		_content.add_child(_empty_card())
		return

	if not featured.is_empty():
		_content.add_child(_section_label("UI_SHOP_FEATURED"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var w := (PAGE_WIDTH - 12.0) * 0.5
		for item in featured.slice(0, 2):
			row.add_child(_make_store_card(item, Vector2(w, 430), 210))
		_content.add_child(row)

	if not others.is_empty():
		_content.add_child(_section_label("UI_SHOP_ITEMS"))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		var w := (PAGE_WIDTH - 24.0) / 3.0
		for item in featured.slice(2) + others:
			grid.add_child(_make_store_card(item, Vector2(w, 300), 132))
		_content.add_child(grid)


func _make_store_card(item: Dictionary, card_size: Vector2, art_size: float) -> Control:
	var card := _rarity_card(item, card_size)
	var owned := SaveManager.is_item_owned(str(item["id"]))

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var art_box := CenterContainer.new()
	art_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(art_box)
	art_box.add_child(_item_preview(item, art_size))

	var band := PanelContainer.new()
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = Color(0.03, 0.02, 0.10, 0.62)
	band_style.content_margin_left = 10
	band_style.content_margin_right = 10
	band_style.content_margin_top = 8
	band_style.content_margin_bottom = 10
	band.add_theme_stylebox_override("panel", band_style)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(band)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	band.add_child(info)

	var big := card_size.y > 360.0
	var name_label := Label.new()
	name_label.text = ShopCatalog.display_name(item).to_upper()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", UiScale.font(20 if big else 15))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(name_label)

	var kind_label := Label.new()
	kind_label.text = _kind_text(item)
	kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind_label.add_theme_font_size_override("font_size", UiScale.font(13 if big else 11))
	kind_label.add_theme_color_override("font_color", ShopCatalog.rarity_color(item).lightened(0.45))
	info.add_child(kind_label)

	var price := HBoxContainer.new()
	price.alignment = BoxContainer.ALIGNMENT_CENTER
	price.add_theme_constant_override("separation", 6)
	info.add_child(price)
	var price_label := Label.new()
	price_label.add_theme_font_size_override("font_size", UiScale.font(17 if big else 14))
	if owned:
		price_label.text = tr("UI_SHOP_OWNED")
		price_label.add_theme_color_override("font_color", UiTokens.FEEDBACK_CORRECT.lightened(0.2))
	else:
		price.add_child(_make_coin(18 if big else 15))
		price_label.text = _format_amount(int(item.get("price", 0)))
		price_label.add_theme_color_override("font_color", Color.WHITE)
	price.add_child(price_label)

	card.pressed.connect(_open_detail.bind(item))
	return card


# --- Casier -----------------------------------------------------------------

func _build_locker() -> void:
	## Stage: the player's animal with the equipped frame, on a small pedestal.
	## The equipped banner is the stage background, as other players will see it.
	var stage := PanelContainer.new()
	var stage_style := StyleBoxFlat.new()
	stage_style.bg_color = Color(0, 0, 0, 0)
	stage_style.set_corner_radius_all(22)
	stage_style.shadow_color = Color(0, 0, 0, 0.3)
	stage_style.shadow_size = 12
	stage.add_theme_stylebox_override("panel", stage_style)
	_content.add_child(stage)
	stage.add_child(CosmeticsView.banner(SaveManager.get_equipped_banner(), Vector2.ZERO, 22))

	var stage_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		stage_margin.add_theme_constant_override("margin_" + side, 18)
	stage.add_child(stage_margin)

	var stage_col := VBoxContainer.new()
	stage_col.alignment = BoxContainer.ALIGNMENT_CENTER
	stage_col.add_theme_constant_override("separation", 10)
	stage_margin.add_child(stage_col)

	var hero_box := CenterContainer.new()
	stage_col.add_child(hero_box)
	hero_box.add_child(_player_avatar(280, SaveManager.get_equipped_frame()))

	var pedestal_box := CenterContainer.new()
	stage_col.add_child(pedestal_box)
	var pedestal := Panel.new()
	pedestal.custom_minimum_size = Vector2(300, 30)
	var pedestal_style := UiStyle.filled(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.28), 15)
	pedestal_style.shadow_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35)
	pedestal_style.shadow_size = 16
	pedestal.add_theme_stylebox_override("panel", pedestal_style)
	pedestal_box.add_child(pedestal)

	var name_label := Label.new()
	name_label.text = SaveManager.player_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", UiScale.font(24))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	name_label.add_theme_constant_override("outline_size", 5)
	stage_col.add_child(name_label)

	## Slots: which part of the look the grid below edits.
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 12)
	_content.add_child(slots)
	var avatar_item := _locker_entry_for_avatar(SaveManager.profile_avatar_id)
	var frame_item := ShopCatalog.get_item(SaveManager.get_equipped_frame())
	var banner_item := ShopCatalog.get_item(SaveManager.get_equipped_banner())
	slots.add_child(_make_slot(ShopCatalog.KIND_AVATAR, "UI_SHOP_KIND_AVATAR", avatar_item))
	slots.add_child(_make_slot(ShopCatalog.KIND_FRAME, "UI_SHOP_KIND_FRAME", frame_item))
	slots.add_child(_make_slot(ShopCatalog.KIND_BANNER, "UI_SHOP_KIND_BANNER", banner_item))

	var hint := Label.new()
	hint.text = tr("UI_SHOP_LOCKER_HINT")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", UiScale.font(14))
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	_content.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	var w := (PAGE_WIDTH - 30.0) / 4.0
	for entry in _owned_entries(_locker_slot):
		grid.add_child(_make_locker_tile(entry, Vector2(w, 200)))


func _make_slot(kind: String, title_key: String, item: Dictionary) -> Control:
	var selected := kind == _locker_slot
	var slot := Button.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.custom_minimum_size.y = 168
	slot.focus_mode = Control.FOCUS_NONE
	var style := UiStyle.profile_surface(ACCENT if selected else Color(0, 0, 0, 0), selected, 10)
	if selected:
		style.set_border_width_all(3)
		style.border_color = ACCENT
	for state in ["normal", "hover", "pressed", "focus"]:
		slot.add_theme_stylebox_override(state, style)
	slot.pressed.connect(_on_slot_pressed.bind(kind))

	var texts := VBoxContainer.new()
	texts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 4)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(texts)
	var preview_box := CenterContainer.new()
	preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(preview_box)
	preview_box.add_child(_item_preview(item, 72))
	var title := Label.new()
	title.text = tr(title_key).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiScale.font(13))
	title.add_theme_color_override("font_color", ACCENT if selected else UiTokens.PROFILE_TITLE_CAPS)
	texts.add_child(title)
	var value := Label.new()
	value.text = _entry_name(item)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.add_theme_font_size_override("font_size", UiScale.font(15))
	value.add_theme_color_override("font_color", Color.WHITE)
	texts.add_child(value)
	return slot


func _on_slot_pressed(kind: String) -> void:
	if kind == _locker_slot:
		return
	_locker_slot = kind
	AudioManager.play("click")
	_rebuild()


func _make_locker_tile(entry: Dictionary, tile_size: Vector2) -> Control:
	var equipped := _is_equipped(entry)
	var tile := Button.new()
	tile.custom_minimum_size = tile_size
	tile.focus_mode = Control.FOCUS_NONE
	var style := UiStyle.profile_surface(ShopCatalog.rarity_color(entry), equipped, 6)
	style.set_border_width_all(3 if equipped else 1)
	if equipped:
		style.border_color = ACCENT
	for state in ["normal", "hover", "pressed", "focus"]:
		tile.add_theme_stylebox_override(state, style)
	tile.pressed.connect(_on_locker_tile_pressed.bind(entry))

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(column)
	var art := CenterContainer.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(art)
	art.add_child(_item_preview(entry, 104))
	var label := Label.new()
	label.text = tr("UI_SHOP_EQUIPPED") if equipped else _entry_name(entry)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", UiScale.font(12))
	label.add_theme_color_override("font_color", ACCENT if equipped else Color(1, 1, 1, 0.85))
	column.add_child(label)
	return tile


func _on_locker_tile_pressed(entry: Dictionary) -> void:
	if _is_equipped(entry):
		return
	var item_id := str(entry.get("id", ""))
	if bool(entry.get("starter", false)):
		SaveManager.set_profile_avatar_id(item_id)
	else:
		SaveManager.equip_item(item_id)
	AudioManager.play("correct")
	_rebuild()


## Owned things for a slot. Starter avatars (free profile set) are not shop items,
## so they get lightweight entries flagged "starter".
func _owned_entries(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if kind == ShopCatalog.KIND_AVATAR:
		out.append(_locker_entry_for_avatar(""))
		for slug in SaveManager.PROFILE_AVATAR_IDS:
			out.append(_locker_entry_for_avatar(slug))
	for item in ShopCatalog.items_of_kind(kind):
		if SaveManager.is_item_owned(str(item["id"])):
			out.append(item)
	return out


func _locker_entry_for_avatar(avatar_id: String) -> Dictionary:
	var shop_item := ShopCatalog.get_item(avatar_id)
	if not shop_item.is_empty():
		return shop_item
	return {"id": avatar_id, "kind": ShopCatalog.KIND_AVATAR, "rarity": "common", "starter": true}


func _is_equipped(entry: Dictionary) -> bool:
	var item_id := str(entry.get("id", ""))
	match str(entry.get("kind", "")):
		ShopCatalog.KIND_FRAME:
			return item_id == SaveManager.get_equipped_frame()
		ShopCatalog.KIND_BANNER:
			return item_id == SaveManager.get_equipped_banner()
	return item_id == SaveManager.profile_avatar_id


func _entry_name(entry: Dictionary) -> String:
	if bool(entry.get("starter", false)):
		return tr("UI_SHOP_STARTER") if not str(entry.get("id", "")).is_empty() else tr("UI_SHOP_DEFAULT_AVATAR")
	return ShopCatalog.display_name(entry)


# --- Purchase popup ---------------------------------------------------------

func _build_detail_popup() -> void:
	_detail_backdrop = ColorRect.new()
	_detail_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_backdrop.color = Color(0.02, 0.02, 0.06, 0.62)
	_detail_backdrop.visible = false
	_detail_backdrop.gui_input.connect(_on_detail_backdrop_input)
	add_child(_detail_backdrop)

	_detail_panel = PanelContainer.new()
	_detail_panel.visible = false
	_detail_panel.set_anchors_preset(Control.PRESET_CENTER)
	_detail_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_detail_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_detail_panel.custom_minimum_size = Vector2(560, 0)
	add_child(_detail_panel)


func _open_detail(item: Dictionary) -> void:
	_detail_item = item
	AudioManager.play("click")
	_fill_detail()
	_detail_backdrop.visible = true
	_detail_panel.visible = true
	_detail_backdrop.move_to_front()
	_detail_panel.move_to_front()


func _fill_detail() -> void:
	for child in _detail_panel.get_children():
		child.queue_free()
	var item := _detail_item
	var item_id := str(item.get("id", ""))
	var rarity := ShopCatalog.rarity_color(item)
	_detail_panel.add_theme_stylebox_override("panel", UiStyle.profile_surface(rarity, true, 24))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_detail_panel.add_child(column)

	var stage := _rarity_card(item, Vector2(0, 300))
	stage.disabled = true
	column.add_child(stage)
	var art := CenterContainer.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(art)
	art.add_child(_item_preview(item, 240))

	var name_label := Label.new()
	name_label.text = ShopCatalog.display_name(item).to_upper()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", UiScale.font(26))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(name_label)

	var kind_label := Label.new()
	kind_label.text = _kind_text(item)
	kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind_label.add_theme_font_size_override("font_size", UiScale.font(15))
	kind_label.add_theme_color_override("font_color", rarity.lightened(0.45))
	column.add_child(kind_label)

	var owned := SaveManager.is_item_owned(item_id)
	var price := int(item.get("price", 0))
	var action := Button.new()
	action.custom_minimum_size.y = 64
	action.add_theme_font_size_override("font_size", UiScale.font(20))
	if owned:
		var equipped := _is_equipped(item)
		action.text = tr("UI_SHOP_EQUIPPED" if equipped else "UI_SHOP_EQUIP")
		action.disabled = equipped
		action.pressed.connect(_on_detail_equip)
	else:
		action.text = "%s  ·  %s" % [tr("UI_SHOP_BUY"), _format_amount(price)]
		if SaveManager.coins < price:
			action.text = tr("UI_SHOP_NOT_ENOUGH")
			action.disabled = true
		action.pressed.connect(_on_detail_buy)
	var action_style := UiStyle.filled(ACCENT, 20)
	var disabled_style := UiStyle.filled(Color(1, 1, 1, 0.12), 20)
	for state in ["normal", "hover", "pressed", "focus"]:
		action.add_theme_stylebox_override(state, action_style)
	action.add_theme_stylebox_override("disabled", disabled_style)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		action.add_theme_color_override(key, UiTokens.INK)
	action.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
	column.add_child(action)
	PressScaleUtil.wire(action, self)

	var cancel := Button.new()
	cancel.text = tr("UI_SHOP_CANCEL")
	cancel.flat = true
	cancel.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	cancel.pressed.connect(_close_detail)
	column.add_child(cancel)


func _on_detail_buy() -> void:
	if not SaveManager.buy_item(str(_detail_item.get("id", ""))):
		AudioManager.play("wrong")
		return
	AudioManager.play("correct")
	_rebuild()
	_fill_detail()


func _on_detail_equip() -> void:
	SaveManager.equip_item(str(_detail_item.get("id", "")))
	AudioManager.play("correct")
	_rebuild()
	_fill_detail()


func _close_detail() -> void:
	_detail_backdrop.visible = false
	_detail_panel.visible = false
	_detail_item = {}


func _on_detail_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_detail()


# --- Building blocks --------------------------------------------------------

## Tappable card painted in the item's rarity colour, lighter towards the top.
func _rarity_card(item: Dictionary, card_size: Vector2) -> Button:
	var rarity := ShopCatalog.rarity_color(item)
	var card := Button.new()
	card.custom_minimum_size = card_size
	card.focus_mode = Control.FOCUS_NONE
	card.clip_contents = true
	var style := UiStyle.filled(rarity.darkened(0.25), 20)
	style.set_border_width_all(3)
	style.border_color = rarity.lightened(0.35)
	style.shadow_color = Color(rarity.r, rarity.g, rarity.b, 0.35)
	style.shadow_size = 10
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(state, style)

	var glow := TextureRect.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(rarity.lightened(0.4), 0.85))
	gradient.set_color(1, Color(rarity.lightened(0.4), 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.38)
	tex.fill_to = Vector2(1.05, 0.9)
	glow.texture = tex
	card.add_child(glow)
	return card


## Round preview: an avatar item shows its art; a frame shows the player's
## current animal wearing that frame.
func _item_preview(item: Dictionary, side: float) -> Control:
	var kind := str(item.get("kind", ""))
	if kind == ShopCatalog.KIND_FRAME:
		return _player_avatar(side, str(item.get("id", "")))
	if kind == ShopCatalog.KIND_BANNER:
		return _banner_preview(str(item.get("id", "")), side)
	var avatar := _new_avatar(side)
	if bool(item.get("starter", false)):
		avatar.set_avatar(SaveManager.avatar_texture_for(str(item.get("id", ""))))
	else:
		avatar.set_avatar(ShopCatalog.avatar_texture(item))
	ShopCatalog.apply_frame(avatar, SaveManager.get_equipped_frame())
	return avatar


## A banner with the player's small framed avatar on it (wider than tall).
func _banner_preview(banner_id: String, side: float) -> Control:
	var view := CosmeticsView.banner(banner_id, Vector2(side * 1.5, side), int(clampf(side * 0.14, 8.0, 20.0)))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(center)
	center.add_child(_player_avatar(side * 0.62, SaveManager.get_equipped_frame()))
	return view


func _player_avatar(side: float, frame_id: String) -> Control:
	var avatar := _new_avatar(side)
	avatar.set_avatar(SaveManager.get_profile_avatar_texture())
	ShopCatalog.apply_frame(avatar, frame_id)
	return avatar


func _new_avatar(side: float) -> CircularAvatar:
	var avatar := CircularAvatarScript.new()
	avatar.custom_minimum_size = Vector2(side, side)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.fill_color = UiTokens.PROFILE_CARD_BG_RAISED
	avatar.ring_gap = clampf(side * 0.016, 2.0, 4.0)
	return avatar


func _make_coin(side: float) -> Control:
	var coin := Panel.new()
	coin.custom_minimum_size = Vector2(side, side)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiStyle.filled(COIN_FILL, int(side * 0.5))
	style.set_border_width_all(maxi(2, int(side * 0.12)))
	style.border_color = COIN_EDGE
	coin.add_theme_stylebox_override("panel", style)
	return coin


func _section_label(key: String) -> Label:
	var label := Label.new()
	label.text = tr(key).to_upper()
	label.add_theme_font_size_override("font_size", UiScale.font(16))
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	return label


func _empty_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.profile_surface(ACCENT, false, 22))
	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.custom_minimum_size.y = 150
	card.add_child(inner)
	for spec in [["UI_SHOP_EMPTY", 20, ACCENT], ["UI_SHOP_EMPTY_HINT", 15, UiTokens.PROFILE_TEXT_MUTED]]:
		var label := Label.new()
		label.text = tr(spec[0])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", UiScale.font(spec[1]))
		label.add_theme_color_override("font_color", spec[2])
		inner.add_child(label)
	return card


func _kind_text(item: Dictionary) -> String:
	var kind_key := "UI_SHOP_KIND_AVATAR"
	match str(item.get("kind", "")):
		ShopCatalog.KIND_FRAME:
			kind_key = "UI_SHOP_KIND_FRAME"
		ShopCatalog.KIND_BANNER:
			kind_key = "UI_SHOP_KIND_BANNER"
	return "%s · %s" % [tr(kind_key), tr(ShopCatalog.rarity_key(item))]


func _format_amount(amount: int) -> String:
	## 12500 -> "12 500" (thin grouping, same in FR and EN UI).
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = " " + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if amount < 0 else "") + digits + out
