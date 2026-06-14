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
	_add_action("jump",   [KEY_L])
	_add_action("dash",   [KEY_K])
	_add_action("attack", [KEY_J])

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
	_build_sandbox()                                                  # new weapon-reactive toys (walk LEFT)

# --- A no-stakes strip LEFT of spawn to try the new weapon-reactive gadgets ---
func _build_sandbox() -> void:
	var ground := Color(0.20, 0.23, 0.30)
	_add_solid(Vector2(-210, 470), Vector2(400, 60), ground)          # sandbox floor (joins the spawn floor)
	_add_solid(Vector2(-408, 400), Vector2(20, 200), ground)          # left wall cap
	# Slash the YELLOW switch to open the DOOR, then continue left.
	var gate := _add_gate(Vector2(-150, 404), Vector2(32, 72))
	_add_switch(Vector2(-70, 424), gate)
	# BROWN breakable wall — slash it twice to smash through.
	_add_breakable(Vector2(-260, 404), Vector2(40, 72), 2)
	# VIOLET directional spring — slash it to launch opposite the slash, hard.
	_add_spring(Vector2(-360, 416), Vector2(48, 48))

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

# --- Weapon-reactive gadgets (layer 3). Each carries an "on_slash" Callable the
#     player invokes; it returns whether the player should also pogo-bounce. ---
func _add_spring(center: Vector2, size: Vector2) -> StaticBody2D:
	var b := _add_solid(center, size, Color(0.55, 0.35, 0.95))        # violet
	b.set_collision_layer_value(3, true)
	var react := func(p: Node, dir: Vector2) -> bool:
		p.velocity = -dir * 640.0                                     # opposite the slash, hard
		p.bounce_timer = maxf(p.bounce_timer, 0.18)                  # let the launch carry
		return false
	b.set_meta("on_slash", react)
	return b

func _add_breakable(center: Vector2, size: Vector2, hits: int) -> StaticBody2D:
	var b := _add_solid(center, size, Color(0.62, 0.47, 0.34))        # brown
	b.set_collision_layer_value(3, true)
	b.set_meta("hp", hits)
	var react := func(p: Node, dir: Vector2) -> bool:
		var hp: int = int(b.get_meta("hp")) - 1
		b.set_meta("hp", hp)
		if hp <= 0:
			b.set_collision_layer_value(1, false)                    # stop blocking
			b.set_collision_layer_value(3, false)
			var tw := b.create_tween()
			tw.tween_property(b, "modulate:a", 0.0, 0.12)
			tw.tween_callback(b.queue_free)
			return false                                             # broke through — keep momentum
		b.modulate = Color(1.0, 0.6, 0.6)                            # cracked
		return false                                                 # no knockback — stand and keep slashing
	b.set_meta("on_slash", react)
	return b

func _add_gate(center: Vector2, size: Vector2) -> StaticBody2D:
	var g := _add_solid(center, size, Color(0.50, 0.42, 0.62))        # dim violet door
	g.set_meta("open", false)
	g.set_meta("shut_y", center.y)
	g.set_meta("open_y", center.y + size.y + 8.0)                     # slide fully below the floor
	return g

func _set_gate(g: StaticBody2D, open: bool) -> void:
	g.set_meta("open", open)
	g.set_collision_layer_value(1, not open)                          # passable when open
	var target_y: float = g.get_meta("open_y") if open else g.get_meta("shut_y")
	var tw := g.create_tween()
	tw.tween_property(g, "position:y", target_y, 0.25).set_trans(Tween.TRANS_QUAD)

func _add_switch(center: Vector2, gate: StaticBody2D) -> StaticBody2D:
	var s := _add_solid(center, Vector2(26, 26), Color(0.95, 0.80, 0.30))   # yellow knob
	s.set_collision_layer_value(1, false)                            # not solid — just a slash target
	s.set_collision_layer_value(3, true)
	var react := func(p: Node, dir: Vector2) -> bool:
		var now_open: bool = not bool(gate.get_meta("open"))
		_set_gate(gate, now_open)
		s.modulate = Color(0.5, 1.0, 0.6) if now_open else Color(1, 1, 1)
		return false                                                 # flip it like a lever — no launch
	s.set_meta("on_slash", react)
	return s

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
	hud.text = "PogoGame prototype v5\nMove WASD  |  Jump L (hold = higher)  |  Dash K (8-way)  |  Attack J  (hold a direction to aim — incl. diagonals)\nRIGHT = main course.   LEFT = NEW gadget sandbox.\nORANGE pogo block  |  PINK launch pad  |  GREEN crystal = refill dash  |  RED spikes\nNEW →  VIOLET spring (slash = big launch opposite the slash)  |  BROWN breakable (slash x2)  |  YELLOW switch opens the DOOR\nPOGO SWEET SPOT: hit with the blade TIP (outer edge) for a full launch + flash — inner hits bounce weak."
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
