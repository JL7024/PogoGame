extends Node2D
# Builds the test level, sets up controls, and spawns the player — all in code
# so there are no fragile scene files to hand-edit.

var player: Player

func _ready() -> void:
	_setup_input()
	_build_level()
	_spawn_player()
	_build_hud()

# --- Controls (registered at runtime, so nothing to configure in the editor) ---
func _setup_input() -> void:
	_add_action("left",   [KEY_A, KEY_LEFT])
	_add_action("right",  [KEY_D, KEY_RIGHT])
	_add_action("up",     [KEY_W, KEY_UP])
	_add_action("down",   [KEY_S, KEY_DOWN])
	_add_action("jump",   [KEY_SPACE, KEY_Z])
	_add_action("dash",   [KEY_SHIFT, KEY_L])
	_add_action("attack", [KEY_J, KEY_X])

func _add_action(act: String, keys: Array) -> void:
	if not InputMap.has_action(act):
		InputMap.add_action(act)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(act, ev)

# --- Level geometry ---
func _build_level() -> void:
	var ground := Color(0.20, 0.23, 0.30)
	_add_solid(Vector2(250, 470), Vector2(540, 60), ground)    # left floor  (x ~ -20..520)
	_add_solid(Vector2(965, 470), Vector2(610, 60), ground)    # right floor (x ~ 660..1270)
	_add_solid(Vector2(-30, 300), Vector2(40, 400), ground)    # left wall
	_add_solid(Vector2(1090, 280), Vector2(300, 40), ground)   # high platform (top y ~ 260)
	# Bounce blocks = the "机关" gadgets. Down-slash one in mid-air to pogo upward.
	_add_bounce_block(Vector2(590, 380), Vector2(56, 56))      # over the gap
	_add_bounce_block(Vector2(900, 360), Vector2(56, 56))      # to reach the high platform

func _spawn_player() -> void:
	player = Player.new()
	player.position = Vector2(140, 360)
	add_child(player)

func _add_solid(center: Vector2, size: Vector2, color: Color) -> StaticBody2D:
	var s := StaticBody2D.new()
	s.position = center
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	s.add_child(cs)
	s.add_child(_rect_poly(size, color))
	s.set_collision_layer_value(1, true)
	add_child(s)
	return s

func _add_bounce_block(center: Vector2, size: Vector2) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.position = center
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	b.add_child(cs)
	b.add_child(_rect_poly(size, Color(0.90, 0.42, 0.18)))    # orange = bounceable
	b.set_collision_layer_value(1, true)     # solid: you can stand on it / it blocks you
	b.set_collision_layer_value(3, true)     # bounceable: the attack hitbox detects layer 3
	add_child(b)
	return b

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var label := Label.new()
	label.position = Vector2(16, 12)
	label.text = "PogoGame prototype\nMove: A/D or Arrows    Jump: Space (hold = higher)    Dash: Shift (8-way)    Attack: J\nAim: hold Up or Down for an up/down slash; otherwise you slash where you face.\nDown-slash an ORANGE block in mid-air = bounce UP (pogo). Try: Jump -> (Dash) -> Pogo across the gap.\nFall off the bottom = respawn."
	cl.add_child(label)

func _rect_poly(size: Vector2, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	p.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)
	])
	p.color = color
	return p
