extends Control

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const ScenePaths = preload("res://scripts/config/scene_paths.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const NewsPopupPolicy = preload("res://scripts/profile/news_popup_policy.gd")

@onready var top_app_bar: TopAppBar = %TopAppBar
@onready var tab_swipe: TabSwipeContainer = %TabSwipeContainer
@onready var bottom_nav: Control = %BottomNavBar
@onready var settings_backdrop: ColorRect = %SettingsBackdrop
@onready var language_option: OptionButton = %LanguageOption
@onready var language_label: Label = %LanguageLabel
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var close_settings_button: Button = %CloseSettingsButton

var sound_toggle: CheckButton
var volume_label: Label
var volume_slider: HSlider
@onready var shell_background: ColorRect = $Background
@onready var main_column: VBoxContainer = $MainColumn

var _brand_bg_material: Material
var _news_backdrop: ColorRect
var _news_panel: PanelContainer
var _news_title: Label
var _news_body: Label
var _news_dismiss: Button
var _shop_page: ShopPage


func _ready() -> void:
	_brand_bg_material = shell_background.material
	SafeArea.changed.connect(_apply_safe_area)
	_apply_safe_area()
	tab_swipe.swipe_threshold = UiTokens.TAB_SWIPE_THRESHOLD
	tab_swipe.drag_lock_threshold = UiTokens.TAB_SWIPE_DRAG_LOCK
	tab_swipe.animation_duration = UiTokens.TAB_SWIPE_DURATION
	_configure_chrome()
	_build_sound_settings()
	_build_news_popup()
	_build_shop_page()
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
	call_deferred("_maybe_show_news_on_launch")


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
		## Remove experimental particle overlays if present.
		var old_particles := page.get_node_or_null("TabPageParticles")
		if old_particles != null:
			old_particles.queue_free()
		if page.has_meta("tab_page_bg"):
			continue
		var bg := ColorRect.new()
		bg.name = "TabPageBackground"
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.color = Color.WHITE
		bg.material = UiTokens.page_bg_material_for_tab(tab_id)
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
		shell_background.color = Color.WHITE
		shell_background.material = UiTokens.page_bg_material_for_tab(tab_id)


func _wire_navigation() -> void:
	bottom_nav.tab_selected.connect(_on_bottom_nav_selected)
	tab_swipe.tab_changed.connect(_on_tab_changed)


func _connect_settings() -> void:
	top_app_bar.settings_pressed.connect(_on_settings_pressed)
	top_app_bar.shop_pressed.connect(_open_shop)
	settings_backdrop.gui_input.connect(_on_settings_backdrop_gui_input)
	close_settings_button.pressed.connect(_on_close_settings_pressed)
	language_option.item_selected.connect(_on_language_selected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _news_panel != null and _news_panel.visible:
			_close_news_popup()
			get_viewport().set_input_as_handled()
			return
		if settings_panel.visible:
			_close_settings()
			get_viewport().set_input_as_handled()
			return
		if _shop_page.visible:
			_shop_page.close()
			get_viewport().set_input_as_handled()


## Sound on/off and volume, inserted above the Back button.
func _build_sound_settings() -> void:
	var column := close_settings_button.get_parent()
	var insert_at := close_settings_button.get_index()

	sound_toggle = CheckButton.new()
	sound_toggle.button_pressed = SaveManager.sound_enabled
	sound_toggle.toggled.connect(_on_sound_toggled)

	volume_label = Label.new()
	volume_label.theme_type_variation = &"MonoLabel"
	volume_label.add_theme_font_size_override("font_size", UiScale.font(14))

	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = SaveManager.sound_volume
	volume_slider.custom_minimum_size = Vector2(0, 32)
	var track := UiStyle.progress_bg()
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := UiStyle.progress_fill(UiTokens.ACCENT_QUIZ)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	volume_slider.add_theme_stylebox_override("slider", track)
	volume_slider.add_theme_stylebox_override("grabber_area", fill)
	volume_slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	sound_toggle.add_theme_font_size_override("font_size", UiScale.font(18))
	sound_toggle.add_theme_color_override("font_color", UiTokens.INK)
	volume_slider.editable = SaveManager.sound_enabled
	volume_slider.value_changed.connect(func(value: float) -> void: SaveManager.set_sound_volume(value))
	## Preview at the new level once the player lets go of the handle.
	volume_slider.drag_ended.connect(func(_changed: bool) -> void: AudioManager.play("correct"))

	for node in [sound_toggle, volume_label, volume_slider]:
		column.add_child(node)
		column.move_child(node, insert_at)
		insert_at += 1


func _on_sound_toggled(enabled: bool) -> void:
	SaveManager.set_sound_enabled(enabled)
	volume_slider.editable = enabled
	AudioManager.play("click")


## Small protected band under the bottom menu (nothing from pages draws there), lifted
## above the system gesture / navigation bar.
func _apply_safe_area() -> void:
	main_column.offset_bottom = -(UiTokens.BOTTOM_NAV_SAFE_ZONE + SafeArea.bottom)
	bottom_nav.offset_top = -UiTokens.BOTTOM_NAV_TOTAL_HEIGHT - SafeArea.bottom
	bottom_nav.offset_bottom = -SafeArea.bottom


func _configure_chrome() -> void:
	settings_panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_QUIZ))
	settings_backdrop.color = Color(0.12, 0.13, 0.15, 0.28)


func _apply_translations() -> void:
	sound_toggle.text = tr("UI_SETTINGS_SOUND")
	volume_label.text = tr("UI_SETTINGS_VOLUME")
	language_label.text = tr("UI_LANGUAGE")
	close_settings_button.text = tr("UI_BACK")
	if _news_title != null:
		_news_title.text = tr("UI_HOME_NEWS")
	if _news_body != null:
		_news_body.text = tr("UI_NEWS_POPUP_BODY")
	if _news_dismiss != null:
		_news_dismiss.text = tr("UI_NEWS_POPUP_DISMISS")


func _build_news_popup() -> void:
	_news_backdrop = ColorRect.new()
	_news_backdrop.name = "NewsBackdrop"
	_news_backdrop.visible = false
	_news_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_news_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_news_backdrop.color = Color(0.12, 0.13, 0.15, 0.36)
	_news_backdrop.gui_input.connect(_on_news_backdrop_gui_input)
	add_child(_news_backdrop)

	_news_panel = PanelContainer.new()
	_news_panel.name = "NewsPanel"
	_news_panel.visible = false
	_news_panel.set_anchors_preset(Control.PRESET_CENTER)
	_news_panel.offset_left = -168.0
	_news_panel.offset_top = -150.0
	_news_panel.offset_right = 168.0
	_news_panel.offset_bottom = 150.0
	_news_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_news_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_news_panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_HOME))
	add_child(_news_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_news_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	_news_title = Label.new()
	_news_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_news_title.add_theme_font_size_override("font_size", UiScale.font(22))
	_news_title.add_theme_color_override("font_color", UiTokens.INK)
	vbox.add_child(_news_title)

	_news_body = Label.new()
	_news_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_news_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_news_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_news_body.add_theme_font_size_override("font_size", UiScale.font(15))
	_news_body.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	vbox.add_child(_news_body)

	_news_dismiss = Button.new()
	_news_dismiss.focus_mode = Control.FOCUS_ALL
	vbox.add_child(_news_dismiss)
	PressScaleUtil.wire(_news_dismiss, self)
	_news_dismiss.pressed.connect(_on_news_dismiss_pressed)


func _build_shop_page() -> void:
	_shop_page = ShopPage.new()
	_shop_page.name = "ShopPage"
	add_child(_shop_page)
	_shop_page.closed.connect(func() -> void: tab_swipe.set_input_enabled(true))


func _open_shop() -> void:
	if settings_panel.visible:
		_close_settings()
	top_app_bar.release_settings_focus()
	tab_swipe.set_input_enabled(false)
	_shop_page.open()


func _maybe_show_news_on_launch() -> void:
	if not NewsPopupPolicy.should_show_on_launch():
		return
	_open_news_popup()
	NewsPopupPolicy.mark_shown()


func _open_news_popup() -> void:
	if settings_panel.visible:
		_close_settings()
	tab_swipe.set_input_enabled(false)
	_news_backdrop.visible = true
	_news_panel.visible = true
	_news_backdrop.move_to_front()
	_news_panel.move_to_front()
	_news_dismiss.grab_focus()


func _close_news_popup() -> void:
	_news_backdrop.visible = false
	_news_panel.visible = false
	if not settings_panel.visible:
		tab_swipe.set_input_enabled(true)


func _on_news_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_close_news_popup()


func _on_news_dismiss_pressed() -> void:
	_close_news_popup()


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
	var tab_id: int = ScenePaths.tab_for_page_index(page_index)
	## Leaderboard owns header-margin wash for Général / Amis; clear elsewhere.
	if tab_id != ScenePaths.Tab.LEADERBOARD:
		top_app_bar.clear_margin_wash()
	if page.has_method("on_tab_shown"):
		page.call("on_tab_shown")


func _on_settings_pressed() -> void:
	_open_settings()


func _open_settings() -> void:
	if _news_panel != null and _news_panel.visible:
		_close_news_popup()
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
