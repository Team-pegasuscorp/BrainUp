extends Control

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const ScenePaths = preload("res://scripts/config/scene_paths.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const NewsPopupPolicy = preload("res://scripts/profile/news_popup_policy.gd")
const AuthGatePolicy = preload("res://scripts/profile/auth_gate_policy.gd")

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
var _sign_out_button: Button
var _settings_title: Label
@onready var shell_background: ColorRect = $Background
@onready var main_column: VBoxContainer = $MainColumn

var _brand_bg_material: Material
## News popup kept built but disabled at launch (NewsPopupPolicy.ENABLED).
var _news_backdrop: ColorRect
var _news_panel: PanelContainer
var _news_title: Label
var _news_body: Label
var _news_dismiss: Button
var _auth_backdrop: ColorRect
var _auth_panel: PanelContainer
var _auth_title: Label
var _auth_switch_row: HBoxContainer
var _auth_switch_label: Label
var _auth_switch_button: Button
var _auth_user_field: VBoxContainer
var _auth_user_label: Label
var _auth_user_input: LineEdit
var _auth_email_label: Label
var _auth_email_input: LineEdit
var _auth_password_label: Label
var _auth_password_input: LineEdit
var _auth_create_button: Button
var _auth_create_gap: Control
var _auth_google_button: Button
var _auth_error_label: Label
var _auth_guest_gap: Control
var _auth_guest_button: Button
var _auth_is_login: bool = false
const _AUTH_PANEL_HALF_W: float = 210.0
const _AUTH_PANEL_HALF_H_SIGNUP: float = 360.0
const _AUTH_PANEL_HALF_H_LOGIN: float = 265.0
var _shop_page: ShopPage

## Same sheet as the top header / Quiz FAB brand bar.
const _AUTH_BG := UiTokens.HEADER_BANNER_BG
const _AUTH_FIELD_BG := UiTokens.BRAND_BG_RAISED
const _AUTH_FIELD_BORDER := Color(0.22, 0.18, 0.38, 1)
## Same light blue as Quiz tiles / FAB accent.
const _AUTH_ACCENT := UiTokens.ACCENT_QUIZ
const _AUTH_ACCENT_HOVER := Color(0.48, 0.82, 1.0, 1)
const _AUTH_ACCENT_PRESSED := UiTokens.ACCENT_QUIZ_DEEP
const _AUTH_TEXT := Color(0.96, 0.96, 0.96, 1)
const _AUTH_MUTED := Color(0.70, 0.70, 0.70, 1)


func _ready() -> void:
	_brand_bg_material = shell_background.material
	SafeArea.changed.connect(_apply_safe_area)
	_apply_safe_area()
	tab_swipe.swipe_threshold = UiTokens.TAB_SWIPE_THRESHOLD
	tab_swipe.drag_lock_threshold = UiTokens.TAB_SWIPE_DRAG_LOCK
	tab_swipe.animation_duration = UiTokens.TAB_SWIPE_DURATION
	_configure_chrome()
	_install_settings_close_cross()
	_build_sound_settings()
	_style_settings_on_dark()
	_build_news_popup()
	_build_auth_gate()
	_build_shop_page()
	_apply_page_backgrounds()
	_apply_translations()
	_setup_language_option()
	_wire_navigation()
	_connect_settings()
	LocaleManager.locale_changed.connect(_on_locale_changed)
	PlayGamesAuth.signed_in.connect(_on_play_games_signed_in)
	PlayGamesAuth.sign_in_failed.connect(_on_play_games_sign_in_failed)
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
	call_deferred("_maybe_show_auth_gate_on_launch")
	call_deferred("_sync_named_profile_to_server")
	## News: re-enable with NewsPopupPolicy.ENABLED and call _maybe_show_news_on_launch.


func _sync_named_profile_to_server() -> void:
	if SaveManager.player_name.strip_edges().is_empty():
		return
	if SaveManager.player_name == UiTokens.DEFAULT_PLAYER_NAME:
		return
	NetworkManager.sync_player_profile()


func _apply_page_backgrounds() -> void:
	## Experiment: every tab shares the Quiz brand-navy canvas (no per-tab wash).
	var pages: Control = tab_swipe.pages_row
	for page_index in range(pages.get_child_count()):
		var page := pages.get_child(page_index) as Control
		if page == null:
			continue
		var old_particles := page.get_node_or_null("TabPageParticles")
		if old_particles != null:
			old_particles.queue_free()
		var old_bg := page.get_node_or_null("TabPageBackground")
		if old_bg != null:
			old_bg.queue_free()
		if page.has_meta("tab_page_bg"):
			page.remove_meta("tab_page_bg")


func _sync_shell_background(_page_index: int) -> void:
	## Same Quiz brand navy for every tab (shell shows through all pages).
	shell_background.material = _brand_bg_material
	shell_background.color = UiTokens.BG_CREAM


func _wire_navigation() -> void:
	bottom_nav.tab_selected.connect(_on_bottom_nav_selected)
	tab_swipe.tab_changed.connect(_on_tab_changed)
	tab_swipe.tab_settled.connect(_notify_tab_shown)


func _connect_settings() -> void:
	top_app_bar.settings_pressed.connect(_on_settings_pressed)
	top_app_bar.shop_pressed.connect(_open_shop)
	settings_backdrop.gui_input.connect(_on_settings_backdrop_gui_input)
	close_settings_button.pressed.connect(_on_close_settings_pressed)
	language_option.item_selected.connect(_on_language_selected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		## Auth gate requires an explicit choice — Back does not dismiss it.
		if _auth_panel != null and _auth_panel.visible:
			get_viewport().set_input_as_handled()
			return
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


## Top-right ✕ like shop / profile (replaces the old bottom "Back" button).
func _install_settings_close_cross() -> void:
	var column := language_label.get_parent() as VBoxContainer
	if column == null or close_settings_button == null:
		return

	var header := HBoxContainer.new()
	header.name = "SettingsHeader"
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	column.move_child(header, 0)

	_settings_title = Label.new()
	_settings_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_settings_title.add_theme_font_size_override("font_size", UiScale.font(22))
	_settings_title.add_theme_color_override("font_color", _AUTH_TEXT)
	header.add_child(_settings_title)

	close_settings_button.reparent(header)
	close_settings_button.text = "✕"
	close_settings_button.flat = true
	close_settings_button.focus_mode = Control.FOCUS_ALL
	close_settings_button.custom_minimum_size = Vector2(44, 44)
	close_settings_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_settings_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_settings_close_cross(close_settings_button)


## Sound on/off and volume, then sign-out (after language controls).
func _build_sound_settings() -> void:
	var column := language_option.get_parent() as VBoxContainer
	var insert_at := language_option.get_index() + 1

	sound_toggle = CheckButton.new()
	sound_toggle.button_pressed = SaveManager.sound_enabled
	sound_toggle.toggled.connect(_on_sound_toggled)

	volume_label = Label.new()
	volume_label.add_theme_font_size_override("font_size", UiScale.font(15))

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
	volume_slider.editable = SaveManager.sound_enabled
	volume_slider.value_changed.connect(func(value: float) -> void: SaveManager.set_sound_volume(value))
	## Preview at the new level once the player lets go of the handle.
	volume_slider.drag_ended.connect(func(_changed: bool) -> void: AudioManager.play("correct"))

	_sign_out_button = Button.new()
	_sign_out_button.focus_mode = Control.FOCUS_ALL
	_sign_out_button.custom_minimum_size = Vector2(0, 44)
	_style_sign_out_button(_sign_out_button)
	_sign_out_button.pressed.connect(_on_sign_out_pressed)
	PressScaleUtil.wire(_sign_out_button, self)

	for node in [sound_toggle, volume_label, volume_slider, _sign_out_button]:
		column.add_child(node)
		column.move_child(node, insert_at)
		insert_at += 1
	_refresh_sign_out_button()


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
	## Same sheet as the auth popup (header brand navy).
	var settings_style := StyleBoxFlat.new()
	settings_style.bg_color = _AUTH_BG
	settings_style.set_border_width_all(1)
	settings_style.border_color = Color(0.22, 0.22, 0.24, 1)
	settings_style.set_corner_radius_all(20)
	settings_style.shadow_color = Color(0, 0, 0, 0.45)
	settings_style.shadow_size = 18
	settings_style.shadow_offset = Vector2(0, 6)
	settings_panel.add_theme_stylebox_override("panel", settings_style)
	settings_backdrop.color = Color(0.02, 0.02, 0.03, 0.72)
	_style_settings_on_dark()


func _style_settings_on_dark() -> void:
	if language_label != null:
		language_label.add_theme_font_size_override("font_size", UiScale.font(15))
		language_label.add_theme_color_override("font_color", _AUTH_TEXT)
	if volume_label != null:
		volume_label.add_theme_font_size_override("font_size", UiScale.font(15))
		volume_label.add_theme_color_override("font_color", _AUTH_TEXT)
	if sound_toggle != null:
		sound_toggle.add_theme_color_override("font_color", _AUTH_TEXT)
		sound_toggle.add_theme_color_override("font_pressed_color", _AUTH_TEXT)
		sound_toggle.add_theme_color_override("font_hover_color", _AUTH_TEXT)
	if _settings_title != null:
		_settings_title.add_theme_color_override("font_color", _AUTH_TEXT)
	if close_settings_button != null:
		_style_settings_close_cross(close_settings_button)
	if _sign_out_button != null:
		_style_sign_out_button(_sign_out_button)
	_style_settings_option(language_option)


func _style_settings_option(option: OptionButton) -> void:
	if option == null:
		return
	option.add_theme_color_override("font_color", _AUTH_TEXT)
	option.add_theme_color_override("font_hover_color", _AUTH_TEXT)
	option.add_theme_color_override("font_pressed_color", _AUTH_TEXT)
	option.add_theme_color_override("font_focus_color", _AUTH_TEXT)
	var normal := _auth_input_style(false)
	var focus := _auth_input_style(true)
	option.add_theme_stylebox_override("normal", normal)
	option.add_theme_stylebox_override("hover", focus)
	option.add_theme_stylebox_override("pressed", focus)
	option.add_theme_stylebox_override("focus", focus)


func _style_sign_out_button(button: Button) -> void:
	if button == null:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.78, 0.22, 0.28, 1)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.90, 0.30, 0.36, 1)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.62, 0.16, 0.20, 1)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_font_size_override("font_size", UiScale.font(15))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)


func _style_settings_close_cross(button: Button) -> void:
	if button == null:
		return
	button.text = "✕"
	button.add_theme_font_size_override("font_size", UiScale.font(28))
	button.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.75))
	var close_empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", close_empty)
	button.add_theme_stylebox_override("hover", close_empty)
	button.add_theme_stylebox_override("pressed", close_empty)
	button.add_theme_stylebox_override("focus", close_empty)


func _apply_translations() -> void:
	sound_toggle.text = tr("UI_SETTINGS_SOUND")
	volume_label.text = tr("UI_SETTINGS_VOLUME")
	language_label.text = tr("UI_LANGUAGE")
	if _settings_title != null:
		_settings_title.text = tr("UI_SETTINGS")
	if close_settings_button != null:
		close_settings_button.text = "✕"
	if _sign_out_button != null:
		_sign_out_button.text = tr("UI_SETTINGS_SIGN_OUT")
	if _news_title != null:
		_news_title.text = tr("UI_HOME_NEWS")
	if _news_body != null:
		_news_body.text = tr("UI_NEWS_POPUP_BODY")
	if _news_dismiss != null:
		_news_dismiss.text = tr("UI_NEWS_POPUP_DISMISS")
	_apply_auth_copy()
	_refresh_sign_out_button()


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
	_shop_page.closed.connect(_on_shop_closed)


func _build_auth_gate() -> void:
	## Dark create-account mock as a centered popup + Google / guest escapes.
	_auth_backdrop = ColorRect.new()
	_auth_backdrop.name = "AuthBackdrop"
	_auth_backdrop.visible = false
	_auth_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_auth_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_auth_backdrop.color = Color(0.02, 0.02, 0.03, 0.72)
	add_child(_auth_backdrop)

	_auth_panel = PanelContainer.new()
	_auth_panel.name = "AuthPanel"
	_auth_panel.visible = false
	_auth_panel.set_anchors_preset(Control.PRESET_CENTER)
	_auth_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_auth_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_auth_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_fit_auth_panel_height(false)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _AUTH_BG
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(0.22, 0.22, 0.24, 1)
	panel_style.set_corner_radius_all(20)
	panel_style.shadow_color = Color(0, 0, 0, 0.45)
	panel_style.shadow_size = 18
	panel_style.shadow_offset = Vector2(0, 6)
	_auth_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_auth_panel)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 20)
	outer.add_theme_constant_override("margin_top", 22)
	outer.add_theme_constant_override("margin_right", 20)
	outer.add_theme_constant_override("margin_bottom", 18)
	_auth_panel.add_child(outer)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	outer.add_child(vbox)

	_auth_title = Label.new()
	_auth_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_auth_title.add_theme_font_size_override("font_size", UiScale.font(30))
	_auth_title.add_theme_color_override("font_color", _AUTH_TEXT)
	vbox.add_child(_auth_title)

	_auth_switch_row = HBoxContainer.new()
	_auth_switch_row.add_theme_constant_override("separation", 4)
	vbox.add_child(_auth_switch_row)

	_auth_switch_label = Label.new()
	_auth_switch_label.add_theme_font_size_override("font_size", UiScale.font(17))
	_auth_switch_label.add_theme_color_override("font_color", _AUTH_MUTED)
	_auth_switch_row.add_child(_auth_switch_label)

	_auth_switch_button = Button.new()
	_auth_switch_button.flat = true
	_auth_switch_button.focus_mode = Control.FOCUS_ALL
	_auth_switch_button.add_theme_font_size_override("font_size", UiScale.font(17))
	_auth_switch_button.add_theme_color_override("font_color", _AUTH_ACCENT)
	_auth_switch_button.add_theme_color_override("font_hover_color", _AUTH_ACCENT_HOVER)
	_auth_switch_row.add_child(_auth_switch_button)
	_auth_switch_button.pressed.connect(_on_auth_switch_mode_pressed)

	vbox.add_child(_auth_make_field("user"))
	vbox.add_child(_auth_make_field("email"))
	vbox.add_child(_auth_make_field("password"))

	## Breathing room where the age / CGU block used to sit.
	_auth_create_gap = Control.new()
	_auth_create_gap.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(_auth_create_gap)

	_auth_create_button = Button.new()
	_auth_create_button.focus_mode = Control.FOCUS_ALL
	_auth_create_button.custom_minimum_size = Vector2(0, 50)
	_style_auth_accent_button(_auth_create_button)
	vbox.add_child(_auth_create_button)
	PressScaleUtil.wire(_auth_create_button, self)
	_auth_create_button.pressed.connect(_on_auth_create_pressed)

	var after_create_gap := Control.new()
	after_create_gap.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(after_create_gap)

	_auth_google_button = Button.new()
	_auth_google_button.focus_mode = Control.FOCUS_ALL
	_auth_google_button.custom_minimum_size = Vector2(0, 44)
	_style_auth_outline_button(_auth_google_button)
	vbox.add_child(_auth_google_button)
	PressScaleUtil.wire(_auth_google_button, self)
	_auth_google_button.pressed.connect(_on_auth_google_pressed)

	_auth_error_label = Label.new()
	_auth_error_label.visible = false
	_auth_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_auth_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_auth_error_label.add_theme_font_size_override("font_size", UiScale.font(13))
	_auth_error_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55, 1))
	vbox.add_child(_auth_error_label)

	_auth_guest_gap = Control.new()
	_auth_guest_gap.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(_auth_guest_gap)

	_auth_guest_button = Button.new()
	_auth_guest_button.focus_mode = Control.FOCUS_ALL
	_auth_guest_button.flat = true
	_auth_guest_button.add_theme_font_size_override("font_size", UiScale.font(14))
	_auth_guest_button.add_theme_color_override("font_color", _AUTH_MUTED)
	_auth_guest_button.add_theme_color_override("font_hover_color", _AUTH_ACCENT)
	_auth_guest_button.add_theme_color_override("font_pressed_color", _AUTH_ACCENT)
	vbox.add_child(_auth_guest_button)
	PressScaleUtil.wire(_auth_guest_button, self)
	_auth_guest_button.pressed.connect(_on_auth_guest_pressed)


func _auth_make_field(kind: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.add_theme_font_size_override("font_size", UiScale.font(15))
	label.add_theme_color_override("font_color", _AUTH_TEXT)
	col.add_child(label)

	var input := LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 44)
	input.focus_mode = Control.FOCUS_ALL
	input.add_theme_font_size_override("font_size", UiScale.font(15))
	input.add_theme_color_override("font_color", _AUTH_TEXT)
	input.add_theme_color_override("font_placeholder_color", Color(0.45, 0.45, 0.45, 1))
	input.add_theme_color_override("caret_color", _AUTH_ACCENT)
	input.add_theme_stylebox_override("normal", _auth_input_style(false))
	input.add_theme_stylebox_override("focus", _auth_input_style(true))
	col.add_child(input)

	match kind:
		"user":
			_auth_user_field = col
			_auth_user_label = label
			_auth_user_input = input
			input.max_length = UiTokens.MAX_PLAYER_NAME_LENGTH
		"email":
			_auth_email_label = label
			_auth_email_input = input
		"password":
			_auth_password_label = label
			_auth_password_input = input
			input.secret = true
	return col


func _auth_input_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _AUTH_FIELD_BG
	style.border_color = _AUTH_ACCENT if focused else _AUTH_FIELD_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _style_auth_accent_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = _AUTH_ACCENT
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 14
	normal.content_margin_bottom = 14
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = _AUTH_ACCENT_HOVER
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = _AUTH_ACCENT_PRESSED
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_font_size_override("font_size", UiScale.font(17))
	button.add_theme_color_override("font_color", Color(0.05, 0.08, 0.14, 1))
	button.add_theme_color_override("font_hover_color", Color(0.05, 0.08, 0.14, 1))
	button.add_theme_color_override("font_pressed_color", Color.WHITE)


func _style_auth_outline_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.border_color = _AUTH_FIELD_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = _AUTH_ACCENT
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_font_size_override("font_size", UiScale.font(15))
	button.add_theme_color_override("font_color", _AUTH_TEXT)
	button.add_theme_color_override("font_hover_color", _AUTH_ACCENT)
	button.add_theme_color_override("font_pressed_color", _AUTH_ACCENT)


func _apply_auth_copy() -> void:
	if _auth_title == null:
		return
	if _auth_is_login:
		_auth_title.text = tr("UI_AUTH_LOGIN_TITLE")
		_auth_switch_label.text = tr("UI_AUTH_NEED_ACCOUNT")
		_auth_switch_button.text = tr("UI_AUTH_CREATE_LINK")
		_auth_create_button.text = tr("UI_AUTH_LOGIN_ACTION")
		if _auth_user_field != null:
			_auth_user_field.visible = false
		if _auth_create_gap != null:
			_auth_create_gap.custom_minimum_size.y = 12
		if _auth_guest_gap != null:
			_auth_guest_gap.visible = false
		if _auth_guest_button != null:
			_auth_guest_button.visible = false
	else:
		_auth_title.text = tr("UI_AUTH_TITLE")
		_auth_switch_label.text = tr("UI_AUTH_ALREADY")
		_auth_switch_button.text = tr("UI_AUTH_LOGIN_LINK")
		_auth_create_button.text = tr("UI_AUTH_CREATE_ACTION")
		if _auth_user_field != null:
			_auth_user_field.visible = true
		if _auth_create_gap != null:
			_auth_create_gap.custom_minimum_size.y = 28
		if _auth_guest_gap != null:
			_auth_guest_gap.visible = true
		if _auth_guest_button != null:
			_auth_guest_button.visible = true

	if _auth_user_label != null:
		_auth_user_label.text = tr("UI_AUTH_USERNAME")
	if _auth_user_input != null:
		_auth_user_input.placeholder_text = tr("UI_AUTH_USERNAME_PH")
	if _auth_email_label != null:
		_auth_email_label.text = tr("UI_AUTH_EMAIL")
	if _auth_email_input != null:
		_auth_email_input.placeholder_text = tr("UI_AUTH_EMAIL_PH")
	if _auth_password_label != null:
		_auth_password_label.text = tr("UI_AUTH_PASSWORD")
	if _auth_password_input != null:
		_auth_password_input.placeholder_text = tr("UI_AUTH_PASSWORD_PH")
	if _auth_google_button != null:
		_auth_google_button.text = tr("UI_AUTH_GOOGLE")
	if _auth_guest_button != null:
		_auth_guest_button.text = tr("UI_AUTH_GUEST")
	_fit_auth_panel_height(_auth_is_login)


func _fit_auth_panel_height(is_login: bool) -> void:
	if _auth_panel == null:
		return
	var half_h := _AUTH_PANEL_HALF_H_LOGIN if is_login else _AUTH_PANEL_HALF_H_SIGNUP
	_auth_panel.offset_left = -_AUTH_PANEL_HALF_W
	_auth_panel.offset_right = _AUTH_PANEL_HALF_W
	_auth_panel.offset_top = -half_h
	_auth_panel.offset_bottom = half_h


func _open_shop() -> void:
	open_shop_tab(ShopPage.TAB_STORE)


## Opens the shop on a given tab ("store", "pass", "locker"); used by the Quiz tab strip.
func open_shop_tab(tab: String) -> void:
	if _auth_panel != null and _auth_panel.visible:
		return
	if settings_panel.visible:
		_close_settings()
	top_app_bar.release_settings_focus()
	tab_swipe.set_input_enabled(false)
	_shop_page.open(tab)


func is_shop_open() -> bool:
	return _shop_page != null and is_instance_valid(_shop_page) and _shop_page.visible


## Avatar / frame may have changed in the locker: redraw the visible tab.
func _on_shop_closed() -> void:
	tab_swipe.set_input_enabled(true)
	_notify_tab_shown(tab_swipe.get_tab())
	_refresh_quiz_pass_strip_if_dirty()


## Quiz defers pass-strip rebuild while the shop is open; catch up after close.
func _refresh_quiz_pass_strip_if_dirty() -> void:
	var pages: Control = tab_swipe.pages_row
	var page_index := ScenePaths.page_index_for_tab(ScenePaths.Tab.QUIZ)
	if page_index < 0 or page_index >= pages.get_child_count():
		return
	var quiz_page := pages.get_child(page_index)
	var select := quiz_page.get_node_or_null("%CategorySelect")
	if select != null and select.has_method("refresh_pass_strip_if_dirty"):
		select.call("refresh_pass_strip_if_dirty")


## Kept for later: set NewsPopupPolicy.ENABLED and call from _ready instead of auth.
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
	if not settings_panel.visible and not (_auth_panel != null and _auth_panel.visible):
		tab_swipe.set_input_enabled(true)


func _on_news_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_close_news_popup()


func _on_news_dismiss_pressed() -> void:
	_close_news_popup()


func _maybe_show_auth_gate_on_launch() -> void:
	if not AuthGatePolicy.should_show_on_launch():
		return
	_open_auth_gate()
	AuthGatePolicy.mark_shown()


func _open_auth_gate() -> void:
	if settings_panel.visible:
		_close_settings()
	if _news_panel != null and _news_panel.visible:
		_close_news_popup()
	tab_swipe.set_input_enabled(false)
	_auth_backdrop.visible = true
	_auth_panel.visible = true
	_auth_backdrop.move_to_front()
	_auth_panel.move_to_front()
	_auth_is_login = false
	_set_auth_google_busy(false)
	_clear_auth_error()
	_apply_auth_copy()
	if _auth_user_input != null:
		_auth_user_input.grab_focus()


func _close_auth_gate() -> void:
	_auth_backdrop.visible = false
	_auth_panel.visible = false
	if not settings_panel.visible:
		tab_swipe.set_input_enabled(true)


func _finish_auth_gate() -> void:
	AudioManager.play("click")
	_close_auth_gate()
	NetworkManager.sync_player_profile()
	_notify_tab_shown(tab_swipe.get_tab())


func _on_auth_switch_mode_pressed() -> void:
	_auth_is_login = not _auth_is_login
	_apply_auth_copy()
	AudioManager.play("click")


func _on_auth_create_pressed() -> void:
	var mail := _auth_email_input.text.strip_edges() if _auth_email_input != null else ""
	if not _auth_is_login:
		var pseudo := _auth_user_input.text.strip_edges() if _auth_user_input != null else ""
		if pseudo.is_empty():
			if _auth_user_input != null:
				_auth_user_input.grab_focus()
			return
		## Username field = in-game pseudo everywhere (home / profile / social).
		## TODO(auth): real signup against the backend.
		SaveManager.complete_email_sign_in_stub(pseudo, mail)
	else:
		## TODO(auth): real login against the backend (keeps existing pseudo).
		SaveManager.complete_email_sign_in_stub("", mail)
	_finish_auth_gate()


func _on_auth_google_pressed() -> void:
	if PlayGamesAuth.is_busy():
		return
	_clear_auth_error()
	_set_auth_google_busy(true)
	PlayGamesAuth.sign_in()


func _on_play_games_signed_in(profile: Dictionary) -> void:
	var display_name := str(profile.get("display_name", "")).strip_edges()
	var games_id := str(profile.get("play_games_player_id", "")).strip_edges()
	var auth_code := str(profile.get("server_auth_code", "")).strip_edges()
	SaveManager.complete_play_games_sign_in(display_name, games_id)
	NetworkManager.link_play_games(auth_code, games_id, display_name)
	_set_auth_google_busy(false)
	_finish_auth_gate()


func _on_play_games_sign_in_failed(message: String) -> void:
	_set_auth_google_busy(false)
	_show_auth_error(message)


func _set_auth_google_busy(busy: bool) -> void:
	if _auth_google_button != null:
		_auth_google_button.disabled = busy


func _clear_auth_error() -> void:
	if _auth_error_label != null:
		_auth_error_label.text = ""
		_auth_error_label.visible = false


func _show_auth_error(message: String) -> void:
	if _auth_error_label == null:
		return
	_auth_error_label.text = message
	_auth_error_label.visible = not message.is_empty()


func _on_auth_guest_pressed() -> void:
	SaveManager.continue_as_guest()
	_finish_auth_gate()


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
	## The page itself refreshes on tab_settled, once the slide is over.


var _last_settled_tab: int = -1


func _notify_tab_shown(page_index: int) -> void:
	var pages: Control = tab_swipe.pages_row
	if page_index < 0 or page_index >= pages.get_child_count():
		return
	if _last_settled_tab >= 0 and _last_settled_tab != page_index and _last_settled_tab < pages.get_child_count():
		var prev := pages.get_child(_last_settled_tab)
		if prev.has_method("on_tab_hidden"):
			prev.call("on_tab_hidden")
	_last_settled_tab = page_index
	for i in range(pages.get_child_count()):
		var tab_page := pages.get_child(i)
		if tab_page is CanvasItem:
			(tab_page as CanvasItem).visible = true
		if tab_page is Node:
			(tab_page as Node).process_mode = (
				Node.PROCESS_MODE_INHERIT if i == page_index else Node.PROCESS_MODE_DISABLED
			)
	var page := pages.get_child(page_index)
	## All tabs share the Quiz navy canvas — no per-tab header wash.
	top_app_bar.clear_margin_wash()
	## Let the slide finish painting before heavy tab rebuilds (Social, Classement…).
	if page.has_method("on_tab_shown"):
		page.call_deferred("on_tab_shown")


func _on_settings_pressed() -> void:
	_open_settings()


func _open_settings() -> void:
	if _auth_panel != null and _auth_panel.visible:
		return
	if _news_panel != null and _news_panel.visible:
		_close_news_popup()
	tab_swipe.set_input_enabled(false)
	_refresh_sign_out_button()
	settings_backdrop.visible = true
	settings_panel.visible = true
	settings_panel.move_to_front()
	top_app_bar.release_settings_focus()
	language_option.grab_focus()


func _refresh_sign_out_button() -> void:
	if _sign_out_button == null:
		return
	## Guest / Google / email — any chosen account can disconnect and reopen the gate.
	_sign_out_button.visible = not SaveManager.needs_auth_choice()


func _on_sign_out_pressed() -> void:
	AudioManager.play("click")
	SaveManager.sign_out()
	NetworkManager.sign_out_local()
	_close_settings()
	_open_auth_gate()
	_notify_tab_shown(tab_swipe.get_tab())


func _close_settings() -> void:
	settings_backdrop.visible = false
	settings_panel.visible = false
	if not (_auth_panel != null and _auth_panel.visible):
		tab_swipe.set_input_enabled(true)


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
