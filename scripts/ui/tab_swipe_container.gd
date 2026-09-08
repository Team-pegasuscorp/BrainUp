extends Control
class_name TabSwipeContainer

## Horizontal pager with touch swipe and animated tab transitions.

signal tab_changed(index: int)

@export var swipe_threshold: float = 80.0
@export var animation_duration: float = 0.28
@export var drag_lock_threshold: float = 14.0
## Fade duration when jumping more than one tab (nav tap).
@export var jump_fade_duration: float = 0.11

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

	var distance := absi(next_tab - current_tab)
	## Multi-tab jump (bottom nav): fade instead of sliding through every page.
	if animate and distance > 1:
		_jump_direct(next_tab)
		return

	current_tab = next_tab
	_snap_to_tab(current_tab, animate)
	tab_changed.emit(current_tab)


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
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(pages_row, "position:x", target_x, animation_duration)
	_tween.finished.connect(_on_tween_finished)


func _jump_direct(next_tab: int) -> void:
	if _page_width <= 0.0:
		current_tab = next_tab
		tab_changed.emit(current_tab)
		return
	if _tween:
		_tween.kill()
	_animating = true
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "modulate:a", 0.0, jump_fade_duration)
	_tween.tween_callback(_apply_direct_jump.bind(next_tab))
	_tween.tween_property(self, "modulate:a", 1.0, jump_fade_duration)
	_tween.finished.connect(_on_tween_finished)


func _apply_direct_jump(next_tab: int) -> void:
	current_tab = next_tab
	pages_row.position.x = -next_tab * _page_width
	tab_changed.emit(current_tab)


func _on_tween_finished() -> void:
	_animating = false
	modulate.a = 1.0


func _gui_input(event: InputEvent) -> void:
	if not _input_enabled or _animating or tab_count <= 1:
		return

	if event is InputEventScreenTouch:
		_handle_press(event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.position)
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_handle_press(mouse_event.position, mouse_event.pressed)
	elif event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		if motion_event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_handle_drag(motion_event.position)


func _handle_press(position: Vector2, pressed: bool) -> void:
	if pressed:
		_dragging = true
		_drag_locked = false
		_drag_cancelled = false
		_drag_start = position
		_drag_base_x = pages_row.position.x
		if _tween:
			_tween.kill()
		_animating = false
		modulate.a = 1.0
	else:
		if not _dragging:
			return
		_dragging = false
		if _drag_cancelled or not _drag_locked:
			_snap_to_tab(current_tab, true)
			return
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
		if absf(delta.y) > absf(delta.x):
			_drag_cancelled = true
			_dragging = false
			_snap_to_tab(current_tab, true)
			return
		_drag_locked = true

	if not _drag_locked:
		return

	var min_x := -(tab_count - 1) * _page_width
	var max_x := 0.0
	var next_x := clampf(_drag_base_x + delta.x, min_x, max_x)
	pages_row.position.x = next_x
