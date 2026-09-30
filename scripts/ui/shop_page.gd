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


func open(tab: String = TAB_STORE) -> void:
	_tab = tab
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
	for tab in [TAB_STORE, TAB_LOCKER]:
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
		button.text = tr("UI_SHOP_STORE" if tab == TAB_STORE else "UI_SHOP_LOCKER").to_upper()
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
	if _tab == TAB_LOCKER:
		_build_locker()
	else:
		_build_store()
	ScrollTouch.let_drags_through(_content)


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
	var stage := PanelContainer.new()
	var stage_style := UiStyle.profile_surface(ACCENT, true, 18)
	stage.add_theme_stylebox_override("panel", stage_style)
	_content.add_child(stage)

	var stage_col := VBoxContainer.new()
	stage_col.alignment = BoxContainer.ALIGNMENT_CENTER
	stage_col.add_theme_constant_override("separation", 10)
	stage.add_child(stage_col)

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
	stage_col.add_child(name_label)

	## Slots: which part of the look the grid below edits.
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 12)
	_content.add_child(slots)
	var avatar_item := _locker_entry_for_avatar(SaveManager.profile_avatar_id)
	var frame_item := ShopCatalog.get_item(SaveManager.get_equipped_frame())
	slots.add_child(_make_slot(ShopCatalog.KIND_AVATAR, "UI_SHOP_KIND_AVATAR", avatar_item))
	slots.add_child(_make_slot(ShopCatalog.KIND_FRAME, "UI_SHOP_KIND_FRAME", frame_item))

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
	slot.custom_minimum_size.y = 112
	slot.focus_mode = Control.FOCUS_NONE
	var style := UiStyle.profile_surface(ACCENT if selected else Color(0, 0, 0, 0), selected, 10)
	if selected:
		style.set_border_width_all(3)
		style.border_color = ACCENT
	for state in ["normal", "hover", "pressed", "focus"]:
		slot.add_theme_stylebox_override(state, style)
	slot.pressed.connect(_on_slot_pressed.bind(kind))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(row)
	var preview_box := CenterContainer.new()
	preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(preview_box)
	preview_box.add_child(_item_preview(item, 80))

	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var title := Label.new()
	title.text = tr(title_key).to_upper()
	title.add_theme_font_size_override("font_size", UiScale.font(13))
	title.add_theme_color_override("font_color", ACCENT if selected else UiTokens.PROFILE_TITLE_CAPS)
	texts.add_child(title)
	var value := Label.new()
	value.text = _entry_name(item)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_size_override("font_size", UiScale.font(16))
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
	if str(entry.get("kind", "")) == ShopCatalog.KIND_FRAME:
		return item_id == SaveManager.get_equipped_frame()
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
	var avatar := _new_avatar(side)
	if bool(item.get("starter", false)):
		avatar.set_avatar(SaveManager.avatar_texture_for(str(item.get("id", ""))))
	else:
		avatar.set_avatar(ShopCatalog.avatar_texture(item))
	ShopCatalog.apply_frame(avatar, SaveManager.get_equipped_frame())
	return avatar


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
	var kind_key := "UI_SHOP_KIND_FRAME" if str(item.get("kind", "")) == ShopCatalog.KIND_FRAME else "UI_SHOP_KIND_AVATAR"
	return "%s · %s" % [tr(kind_key), tr(ShopCatalog.rarity_key(item))]


func _format_amount(amount: int) -> String:
	## 12500 -> "12 500" (thin grouping, same in FR and EN UI).
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = " " + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if amount < 0 else "") + digits + out
