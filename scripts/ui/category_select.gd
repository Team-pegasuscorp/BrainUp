extends Control

signal back_requested

const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")
const ScenePaths = preload("res://scripts/config/scene_paths.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")

@export var embedded_mode: bool = false

@onready var background: ColorRect = $Background
@onready var title_label: Label = %TitleLabel
@onready var category_list: VBoxContainer = %CategoryList
@onready var back_button: Button = %BackButton
@onready var description_label: Label = %DescriptionLabel
@onready var start_button: Button = %StartButton

var categories: Array[Dictionary] = []
var _selected_index: int = 0
var _tile_buttons: Array[Button] = []


func _ready() -> void:
	_apply_embedded_layout()
	_apply_translations()
	_load_categories()
	back_button.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)
	LocaleManager.locale_changed.connect(_on_locale_changed)
	PressScaleUtil.wire(start_button, self)
	if not embedded_mode:
		PressScaleUtil.wire(back_button, self)


func _apply_embedded_layout() -> void:
	if not embedded_mode:
		return
	background.visible = false
	## The embedded page sits on the dark shell, so the title must be light.
	title_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	back_button.visible = false
	description_label.visible = false


func _apply_translations() -> void:
	title_label.text = tr("UI_CHOOSE_CATEGORY")
	back_button.text = tr("UI_BACK")
	start_button.text = tr("UI_PLAY")


func refresh() -> void:
	_apply_translations()
	_load_categories()


func _load_categories() -> void:
	categories = QuestionLoaderScript.get_categories(LocaleManager.get_content_locale())
	for child in category_list.get_children():
		child.queue_free()
	_tile_buttons.clear()

	if categories.is_empty():
		description_label.text = tr("UI_NO_CATEGORIES")
		start_button.disabled = true
		return

	for index in range(categories.size()):
		var category: Dictionary = categories[index]
		var tile := _make_category_tile(index, category)
		category_list.add_child(tile)
		_tile_buttons.append(tile)

	_selected_index = clampi(_selected_index, 0, categories.size() - 1)
	_on_category_selected(_selected_index)


func _make_category_tile(index: int, category: Dictionary) -> Button:
	var category_id := str(category.get("id", ""))
	var accent := UiTokens.accent_for_category(category_id)
	var button := Button.new()
	button.custom_minimum_size.y = 92
	button.text = ""
	button.pressed.connect(_on_category_selected.bind(index))
	PressScaleUtil.wire(button, self)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(10, 0)
	swatch.color = accent
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)

	row.add_child(GameAssets.make_circular_icon_display(GameAssets.category_texture(category_id), "🧠", 64.0))

	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(labels)

	var name_label := Label.new()
	name_label.text = str(category.get("name", category_id))
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(name_label)

	var desc := Label.new()
	desc.text = str(category.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(desc)

	button.set_meta("accent", accent)
	button.set_meta("name_label", name_label)
	button.set_meta("desc_label", desc)
	return button


func _on_category_selected(index: int) -> void:
	if index < 0 or index >= categories.size():
		return
	_selected_index = index
	description_label.text = categories[index].get("description", "")
	start_button.disabled = false
	for tile_index in range(_tile_buttons.size()):
		var tile := _tile_buttons[tile_index]
		var accent: Color = tile.get_meta("accent")
		var selected := tile_index == index
		tile.add_theme_stylebox_override(
			"normal",
			UiStyle.category_tile_selected(accent) if selected else UiStyle.category_tile(accent)
		)
		tile.add_theme_stylebox_override(
			"hover",
			UiStyle.category_tile_selected(accent) if selected else UiStyle.category_tile(accent)
		)
		tile.add_theme_stylebox_override(
			"pressed",
			UiStyle.category_tile_selected(accent)
		)
		var name_label: Label = tile.get_meta("name_label")
		var desc_label: Label = tile.get_meta("desc_label")
		name_label.add_theme_color_override("font_color", UiTokens.INK)
		desc_label.add_theme_color_override("font_color", UiTokens.INK_MUTED)


func _on_start_pressed() -> void:
	if _selected_index < 0 or _selected_index >= categories.size():
		return
	var category_id: String = str(categories[_selected_index].get("id", ""))
	GameManager.start_round(category_id)
	if not GameManager.has_questions():
		description_label.text = tr("UI_EMPTY_QUESTIONS")
		return
	get_tree().change_scene_to_file(ScenePaths.QUIZ_GAME)


func _on_back_pressed() -> void:
	if embedded_mode:
		back_requested.emit()
	else:
		ScenePaths.go_to_shell(get_tree(), ScenePaths.Tab.HOME)


func _on_locale_changed(_locale: String) -> void:
	refresh()
