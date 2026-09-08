extends Control

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const ScenePaths = preload("res://scripts/config/scene_paths.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")

@onready var top_app_bar: TopAppBar = %TopAppBar
@onready var tab_swipe: TabSwipeContainer = %TabSwipeContainer
@onready var bottom_nav: Control = %BottomNavBar
@onready var settings_backdrop: ColorRect = %SettingsBackdrop
@onready var language_option: OptionButton = %LanguageOption
@onready var language_label: Label = %LanguageLabel
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var close_settings_button: Button = %CloseSettingsButton
@onready var shell_background: ColorRect = $Background
@onready var main_column: VBoxContainer = $MainColumn

var _brand_bg_material: Material


func _ready() -> void:
	_brand_bg_material = shell_background.material
	## Small protected band under the bottom menu — nothing from pages draws there.
	main_column.offset_bottom = -UiTokens.BOTTOM_NAV_SAFE_ZONE
	tab_swipe.swipe_threshold = UiTokens.TAB_SWIPE_THRESHOLD
	tab_swipe.drag_lock_threshold = UiTokens.TAB_SWIPE_DRAG_LOCK
	tab_swipe.animation_duration = UiTokens.TAB_SWIPE_DURATION
	_configure_chrome()
	_apply_page_backgrounds()
	_apply_translations()
	_setup_language_option()
	_wire_navigation()
	_connect_settings()
	LocaleManager.locale_changed.connect(_on_locale_changed)
	PressScaleUtil.wire(close_settings_button, self)

	if tab_swipe.pages_row.get_child_count() != ScenePaths.TAB_COUNT:
		push_warning(
			"AppShell: expected %d tab pages, found %d. Keep PagesRow in sync with ScenePaths.TAB_PAGE_ORDER."
			% [ScenePaths.TAB_COUNT, tab_swipe.pages_row.get_child_count()]
		)

	var initial_tab: int = clampi(GameManager.shell_tab_index, 0, ScenePaths.TAB_COUNT - 1)
	var initial_page: int = ScenePaths.page_index_for_tab(initial_tab)
	tab_swipe.set_tab(initial_page, false)
	bottom_nav.set_active_tab(initial_page)
	_sync_shell_background(initial_page)
	_notify_tab_shown(initial_page)


func _apply_page_backgrounds() -> void:
	var pages: Control = tab_swipe.pages_row
	for page_index in range(pages.get_child_count()):
		var tab_id: int = ScenePaths.tab_for_page_index(page_index)
		## Quiz keeps the shared brand navy canvas behind the pages.
		if tab_id == ScenePaths.Tab.QUIZ:
			continue
		var page := pages.get_child(page_index) as Control
		if page == null:
			continue
		if page.has_meta("tab_page_bg"):
			continue
		var bg := ColorRect.new()
		bg.name = "TabPageBackground"
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.color = UiTokens.page_bg_for_tab(tab_id)
		page.add_child(bg)
		page.move_child(bg, 0)
		page.set_meta("tab_page_bg", true)


func _sync_shell_background(page_index: int) -> void:
	## Pages stop above the bottom nav; tint the full-screen shell so the color
	## continues behind / below the floating dock.
	var tab_id: int = ScenePaths.tab_for_page_index(page_index)
	if tab_id == ScenePaths.Tab.QUIZ:
		shell_background.material = _brand_bg_material
		shell_background.color = UiTokens.BG_CREAM
	else:
		shell_background.material = null
		shell_background.color = UiTokens.page_bg_for_tab(tab_id)


func _wire_navigation() -> void:
	bottom_nav.tab_selected.connect(_on_bottom_nav_selected)
	tab_swipe.tab_changed.connect(_on_tab_changed)


func _connect_settings() -> void:
	top_app_bar.settings_pressed.connect(_on_settings_pressed)
	settings_backdrop.gui_input.connect(_on_settings_backdrop_gui_input)
	close_settings_button.pressed.connect(_on_close_settings_pressed)
	language_option.item_selected.connect(_on_language_selected)


func _unhandled_input(event: InputEvent) -> void:
	if not settings_panel.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_settings()
		get_viewport().set_input_as_handled()


func _configure_chrome() -> void:
	settings_panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_QUIZ))
	settings_backdrop.color = Color(0.12, 0.13, 0.15, 0.28)


func _apply_translations() -> void:
	language_label.text = tr("UI_LANGUAGE")
	close_settings_button.text = tr("UI_BACK")


func _setup_language_option() -> void:
	language_option.clear()
	var locales: Array[String] = LocaleManager.get_supported_locales()
	for index in range(locales.size()):
		var locale: String = locales[index]
		language_option.add_item(LocaleManager.get_locale_display_name(locale), index)
		language_option.set_item_metadata(index, locale)
		if locale == LocaleManager.current_locale:
			language_option.select(index)


func _on_bottom_nav_selected(index: int) -> void:
	tab_swipe.set_tab(index, true)


func _on_tab_changed(page_index: int) -> void:
	bottom_nav.set_active_tab(page_index)
	GameManager.shell_tab_index = ScenePaths.tab_for_page_index(page_index)
	_sync_shell_background(page_index)
	_notify_tab_shown(page_index)


func _notify_tab_shown(page_index: int) -> void:
	var pages: Control = tab_swipe.pages_row
	if page_index < 0 or page_index >= pages.get_child_count():
		return
	var page := pages.get_child(page_index)
	if page.has_method("on_tab_shown"):
		page.call("on_tab_shown")


func _on_settings_pressed() -> void:
	_open_settings()


func _open_settings() -> void:
	tab_swipe.set_input_enabled(false)
	settings_backdrop.visible = true
	settings_panel.visible = true
	settings_panel.move_to_front()
	top_app_bar.release_settings_focus()
	language_option.grab_focus()


func _close_settings() -> void:
	tab_swipe.set_input_enabled(true)
	settings_backdrop.visible = false
	settings_panel.visible = false


func _on_settings_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_close_settings()


func _on_close_settings_pressed() -> void:
	_close_settings()


func _on_language_selected(index: int) -> void:
	var locale: String = str(language_option.get_item_metadata(index))
	LocaleManager.set_locale(locale)


func _on_locale_changed(_locale: String) -> void:
	_apply_translations()
	_setup_language_option()
	_notify_tab_shown(tab_swipe.get_tab())
