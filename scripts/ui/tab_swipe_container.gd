extends Control
class_name TabSwipeContainer

const UiTokens = preload("res://scripts/config/ui_tokens.gd")

## Horizontal pager with touch swipe and animated tab transitions.

signal tab_changed(index: int)
signal tab_slide_started(from_index: int, to_index: int)
## The page has finished sliding in: the moment for heavy refreshes, so they never
## run during the slide (tab_changed fires at its start, for the nav highlight).
signal tab_settled(index: int)

@export var swipe_threshold: float = 80.0
@export var animation_duration: float = UiTokens.TAB_SWIPE_DURATION
@export var drag_lock_threshold: float = 14.0

@onready var pages_row: Control = %PagesRow

var tab_count: int = 0
var current_tab: int = 0

var _page_width: float = 0.0
var _dragging: bool = false
var _drag_locked: bool = false
var _drag_cancelled: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_base_x: float = 0.0
var _tween: Tween
var _animating: bool = false
var _input_enabled: bool = true
var _settle_pending: bool = false
var _slide_from_tab: int = 0


func _ready() -> void:
	clip_contents = true
	resized.connect(_on_resized)
	call_deferred("_on_resized")


func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled


func set_tab(index: int, animate: bool = true) -> void:
	if tab_count == 0:
		current_tab = index
		return
	var next_tab := clampi(index, 0, tab_count - 1)
	if next_tab == current_tab and not _dragging and not _animating:
		return

	_slide_from_tab = current_tab
	current_tab = next_tab
	_settle_pending = animate and _page_width > 0.0
	if animate and _slide_from_tab != current_tab:
		tab_slide_started.emit(_slide_from_tab, current_tab)
	_snap_to_tab(current_tab, animate)
	tab_changed.emit(current_tab)
	if not _settle_pending:
		tab_settled.emit(current_tab)


func get_tab() -> int:
	return current_tab


func _on_resized() -> void:
	_page_width = size.x
	tab_count = pages_row.get_child_count()
	## Manual page slots: HBox would expand past viewport when a tab's min width grows
	## (e.g. category chip rows on Classement / Social) and bleed onto neighbours.
	for i in range(tab_count):
		var child := pages_row.get_child(i)
		if not (child is Control):
			continue
		var page := child as Control
		page.clip_contents = true
		page.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		page.position = Vector2(float(i) * _page_width, 0.0)
		page.size = Vector2(_page_width, size.y)
		page.custom_minimum_size = Vector2(_page_width, size.y)
	pages_row.custom_minimum_size = Vector2(_page_width * float(tab_count), size.y)
	pages_row.size = Vector2(_page_width * float(tab_count), size.y)
	pages_row.position.y = 0.0
	_snap_to_tab(current_tab, false)


func _snap_to_tab(index: int, animate: bool) -> void:
	if _page_width <= 0.0:
		return
	var target_x := -index * _page_width
	if not animate:
		if _tween:
			_tween.kill()
		_animating = false
		pages_row.position.x = target_x
		modulate.a = 1.0
		return
	if _tween:
		_tween.kill()
	_animating = true
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUINT)
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(pages_row, "position:x", target_x, animation_duration)
	_tween.finished.connect(_on_tween_finished, CONNECT_ONE_SHOT)


func _on_tween_finished() -> void:
	_animating = false
	modulate.a = 1.0
	if _settle_pending:
		_settle_pending = false
		tab_settled.emit(current_tab)


func is_animating() -> bool:
	return _animating or _dragging


func _page_at(index: int) -> Control:
	if index < 0 or index >= tab_count:
		return null
	var child := pages_row.get_child(index)
	return child as Control if child is Control else null


## Gestures are read in _input, before the GUI: every page is a ScrollContainer full
## of buttons that swallow the drag, so _gui_input never saw a swipe. Once a drag is
## clearly horizontal the pager takes it over (see _take_over_drag).
func _input(event: InputEvent) -> void:
	if not _input_enabled or tab_count <= 1 or _page_width <= 0.0:
		return
	if event.has_meta(_SYNTHETIC_META):
		return
	var touchscreen := DisplayServer.is_touchscreen_available()
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index == 0:
			_handle_press(touch.position, touch.pressed)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == 0:
			_handle_drag(drag.position)
			if _drag_locked:
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if touchscreen:
			## Mouse emulated from the finger: keep it from the page while we own the drag.
			if _drag_locked and _dragging:
				get_viewport().set_input_as_handled()
		elif (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			_handle_drag((event as InputEventMouseMotion).position)
			if _drag_locked:
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not touchscreen:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_handle_press(mouse_event.position, mouse_event.pressed)


const _SYNTHETIC_META := &"tab_swipe_synthetic"


## A swipe must not end as a tap: move the pointer far away for the control that got
## the press (a Button then sees the release outside itself and does not fire).
## relative stays zero so a ScrollContainer in drag mode does not jump.
func _take_over_drag() -> void:
	var away := InputEventMouseMotion.new()
	away.position = Vector2(-100000, -100000)
	away.global_position = away.position
	away.button_mask = MOUSE_BUTTON_MASK_LEFT
	away.set_meta(_SYNTHETIC_META, true)
	get_viewport().push_input(away)


## The drag started on something that scrolls sideways itself, or not on a page.
func _drag_belongs_elsewhere() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	if not pages_row.is_ancestor_of(hovered):
		return true  ## Settings, shop, news… drawn over the pages.
	var node: Node = hovered
	while node != null and node != pages_row:
		if node is ScrollContainer:
			var sc := node as ScrollContainer
			if sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED \
					and sc.get_h_scroll_bar().max_value > sc.size.x + 1.0:
				return true
		node = node.get_parent()
	return false


func _handle_press(position: Vector2, pressed: bool) -> void:
	if pressed:
		if _animating or not get_global_rect().has_point(position):
			return
		_dragging = true
		_drag_locked = false
		_drag_cancelled = false
		_drag_start = position
		_drag_base_x = pages_row.position.x
		if _tween:
			_tween.kill()
		_animating = false
		modulate.a = 1.0
		## A new touch interrupted a slide: the page is on screen, refresh it now.
		if _settle_pending:
			_settle_pending = false
			tab_settled.emit(current_tab)
	else:
		if not _dragging:
			return
		_dragging = false
		if _drag_cancelled or not _drag_locked:
			return  ## A tap or a vertical scroll: the pages never moved.
		var delta_x := position.x - _drag_start.x
		if absf(delta_x) >= swipe_threshold:
			if delta_x < 0.0:
				set_tab(current_tab + 1, true)
			else:
				set_tab(current_tab - 1, true)
		else:
			_snap_to_tab(current_tab, true)


func _handle_drag(position: Vector2) -> void:
	if not _dragging or _page_width <= 0.0:
		return

	var delta := position - _drag_start
	if not _drag_locked and not _drag_cancelled:
		if absf(delta.x) < drag_lock_threshold and absf(delta.y) < drag_lock_threshold:
			return
		if absf(delta.y) > absf(delta.x) or _drag_belongs_elsewhere():
			_drag_cancelled = true
			_dragging = false
			return
		_drag_locked = true
		_take_over_drag()

	if not _drag_locked:
		return

	var min_x := -(tab_count - 1) * _page_width
	var max_x := 0.0
	var next_x := clampf(_drag_base_x + delta.x, min_x, max_x)
	pages_row.position.x = next_x
