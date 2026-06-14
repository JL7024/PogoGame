extends Node2D
# Builds the test course, controls, gadgets and HUD in code (no fragile scene files).

var player: Player
var hud: Label

func _ready() -> void:
	_setup_input()
	_build_level()
	_spawn_player()
	_build_hud()

# --- Controls (registered at runtime) ---
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

# --- The course (left -> right). Spacing may need a tuning pass after playtest. ---
func _build_level() -> void:
	var ground := Color(0.20, 0.23, 0.30)
	# Start
	_add_solid(Vector2(180, 470), Vector2(400, 60), ground)            # spawn floor
	# C1: down-pogo across a spike gap
	_add_spikes(Vector2(455, 505), Vector2(170, 26))
	_add_bounce_block(Vector2(455, 390), Vector2(56, 56))
	_add_solid(Vector2(800, 470), Vector2(540, 60), ground)            # landing + chimney base
	# C2: wall-jump chimney — walk in under the left wall, then climb
	_add_solid(Vector2(960, 290), Vector2(40, 180), ground)           # left wall (gap below it)
	_add_solid(Vector2(1080, 305), Vector2(40, 270), ground)          # right wall
	_add_solid(Vector2(1180, 180), Vector2(220, 40), ground)          # top exit ledge
	# C3: dash through a refill crystal to cross a gap
	_add_dash_crystal(Vector2(1370, 120))
	_add_solid(Vector2(1500, 180), Vector2(220, 40), ground)          # far ledge
	# C4: hit the launch pad, ride it up to the goal
	_add_launch_pad(Vector2(1560, 142), Vector2(56, 24), Vector2(150, -780))
	_add_solid(Vector2(1640, -60), Vector2(240, 40), ground)          # high goal ledge
	_add_goal(Vector2(1640, -110), Vector2(64, 64))

func _spawn_player() -> void:
	player = Player.new()
	player.position = Vector2(140, 360)
	add_child(player)
	player.cleared.connect(_on_cleared)

# --- Builders ---
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
	var b := _add_solid(center, size, Color(0.90, 0.42, 0.18))   # orange
	b.set_collision_layer_value(3, true)                          # bounceable
	return b

func _add_launch_pad(center: Vector2, size: Vector2, launch: Vector2) -> StaticBody2D:
	var b := _add_solid(center, size, Color(0.85, 0.30, 0.55))   # pink
	b.set_collision_layer_value(3, true)
	b.set_meta("launch", launch)                                 # fixed launch velocity
	return b

func _add_spikes(center: Vector2, size: Vector2) -> Area2D:
	return _add_area(center, size, Color(0.85, 0.20, 0.22), "hazard", 5)   # red, layer 5

func _add_goal(center: Vector2, size: Vector2) -> Area2D:
	return _add_area(center, size, Color(0.45, 0.90, 0.45), "goal", 5)     # bright green

func _add_dash_crystal(center: Vector2) -> Area2D:
	var a := _add_area(center, Vector2(30, 30), Color(0.40, 0.85, 0.55), "dash_crystal", 4)
	a.set_meta("active", true)
	return a

func _add_area(center: Vector2, size: Vector2, color: Color, group: String, layer: int) -> Area2D:
	var a := Area2D.new()
	a.position = center
	a.collision_layer = 0
	a.collision_mask = 0
	a.set_collision_layer_value(layer, true)
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	a.add_child(cs)
	a.add_child(_rect_poly(size, color))
	a.add_to_group(group)
	add_child(a)
	return a

func _on_cleared() -> void:
	if hud:
		hud.text = "CLEARED!  You chained pogo + wall-jump + dash-refill + launch pad.  (fall off to replay)"

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.text = "PogoGame prototype v2\nMove A/D or Arrows  |  Jump Space (hold = higher)  |  Dash Shift (8-way)  |  Attack J  (hold Up/Down to aim)\nORANGE = down-slash to pogo.   PINK = launch pad.   GREEN crystal = refill dash.   RED = spikes.\nGoal: pogo over the spikes, wall-jump up the chimney, dash through the crystal, ride the launch pad to the GREEN goal."
	cl.add_child(hud)

func _rect_poly(size: Vector2, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	p.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)
	])
	p.color = color
	return p
