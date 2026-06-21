extends Control

@export var queue_manager: QueueManager

const WIDGET_SIZE := Vector2(84, 84)
const GAP := 16.0
const ARC_R := 26.0
const LINE_W := 4.5
const ARC_SPAN := deg_to_rad(120.0)

var _direction := 1
var _active := false
var _anchor_top_left := Vector2(-99999.0, -99999.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = 12
	custom_minimum_size = WIDGET_SIZE
	size = WIDGET_SIZE
	pivot_offset = WIDGET_SIZE * 0.5
	if queue_manager == null:
		queue_manager = get_tree().get_first_node_in_group("queue_manager") as QueueManager
	Signals.TURN_changed.connect(_on_turn_changed)
	Signals.MATCH_direction_changed.connect(_on_direction_changed)
	call_deferred("_refresh_after_layout")


func _refresh_after_layout() -> void:
	for _i in range(8):
		await get_tree().process_frame
	_refresh(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_refresh", true)


func _on_turn_changed(_holder: HandCardHolder) -> void:
	call_deferred("_refresh", true)


func _on_direction_changed(new_direction: int) -> void:
	if new_direction != _direction:
		_direction = new_direction
		_pulse()
		queue_redraw()


func _pulse() -> void:
	scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.25, 1.25), 0.12).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2.ONE, 0.22)


func _should_show() -> bool:
	if queue_manager == null:
		return false
	if queue_manager.turn_order.size() >= 2:
		return true
	return queue_manager.player_count >= 2


func _refresh(reposition: bool = false) -> void:
	if queue_manager == null:
		_active = false
		visible = false
		queue_redraw()
		return

	_active = _should_show()
	visible = _active
	if !_active:
		queue_redraw()
		return

	_direction = queue_manager.get_direction()

	if reposition or _anchor_top_left.x < -9000.0:
		var anchor := _compute_anchor_top_left()
		if anchor == Vector2.ZERO:
			_active = false
			visible = false
			queue_redraw()
			return
		_anchor_top_left = anchor
		global_position = _anchor_top_left

	queue_redraw()


func _compute_anchor_top_left() -> Vector2:
	if queue_manager == null or queue_manager.card_manager == null:
		return Vector2.ZERO

	var draw := queue_manager.card_manager.draw_button
	if draw == null or !is_instance_valid(draw):
		return Vector2.ZERO

	var draw_rect := draw.get_global_rect()
	# Centered above the draw pile — keeps arrows clear of the deck card.
	return Vector2(
		draw_rect.position.x + draw_rect.size.x * 0.5 - WIDGET_SIZE.x * 0.5,
		draw_rect.position.y - WIDGET_SIZE.y - GAP
	)


func _draw() -> void:
	if !_active:
		return

	var hub := size * 0.5
	var col := Color(1.0, 1.0, 1.0, 0.97)
	var shadow := Color(0.0, 0.0, 0.0, 0.6)
	# In Godot, +Y points down — invert vs. game direction so arrows match turn order.
	var cw := _direction < 0

	# Shadow pass for contrast against any background.
	_draw_arc_arrow(hub + Vector2(1.5, 1.5), deg_to_rad(-35.0), cw, shadow, 1.5)
	_draw_arc_arrow(hub + Vector2(1.5, 1.5), deg_to_rad(145.0), cw, shadow, 1.5)
	# Two opposite arcs — like the reverse card symbol.
	_draw_arc_arrow(hub, deg_to_rad(-35.0), cw, col)
	_draw_arc_arrow(hub, deg_to_rad(145.0), cw, col)


func _draw_arc_arrow(hub: Vector2, start_a: float, clockwise: bool, col: Color, width_scale: float = 1.0) -> void:
	var span := ARC_SPAN if clockwise else -ARC_SPAN
	var end_a := start_a + span
	var pts := PackedVector2Array()
	const STEPS := 18

	for i in range(STEPS + 1):
		var t := float(i) / float(STEPS)
		var angle := lerpf(start_a, end_a, t)
		pts.append(hub + Vector2(cos(angle), sin(angle)) * ARC_R)

	if pts.size() < 2:
		return

	draw_polyline(pts, col, LINE_W * width_scale, true)

	var tip := pts[pts.size() - 1]
	var prev := pts[pts.size() - 2]
	var dir := (tip - prev).normalized()
	var side := Vector2(-dir.y, dir.x)
	var s := width_scale
	draw_colored_polygon(PackedVector2Array([
		tip + dir * 7.0 * s,
		tip - dir * 3.5 * s + side * 5.0 * s,
		tip - dir * 3.5 * s - side * 5.0 * s,
	]), col)
