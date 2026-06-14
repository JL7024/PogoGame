class_name Player
extends CharacterBody2D
# Celeste-style movement + a 4-directional attack that bounces you off
# "bounceable" gadgets. v2 adds wall-jump, dash-refill crystals, launch pads,
# spikes, and a bit of juice. Tune everything from the values below.

# ─────────── Tunable feel parameters — edit, then press F5 ───────────
@export_group("Run")
@export var max_speed := 220.0
@export var accel := 1800.0
@export var friction := 2200.0
@export var air_accel := 1500.0
@export var air_friction := 800.0

@export_group("Jump / Gravity")
@export var jump_velocity := -430.0
@export var rise_gravity := 1100.0
@export var fall_gravity := 1600.0
@export var max_fall := 700.0
@export var jump_cut_mult := 0.45
@export var coyote_time := 0.10
@export var jump_buffer := 0.12

@export_group("Wall")
@export var wall_slide_speed := 120.0
@export var wall_jump_velocity := -430.0
@export var wall_jump_push := 280.0
@export var wall_jump_lock := 0.16

@export_group("Dash")
@export var dash_speed := 560.0
@export var dash_time := 0.14
@export var dash_cooldown := 0.10
@export var max_dashes := 1
@export var crystal_cooldown := 2.5

@export_group("Attack / Pogo")
@export var attack_time := 0.16
@export var attack_cooldown := 0.22
@export var attack_reach := 40.0                    # how far the hitbox sits from the body
@export var attack_size_diag := Vector2(50, 50)     # diagonal slash hitbox
@export var attack_size_vert := Vector2(50, 46)     # up / down slash hitbox
@export var attack_size_horiz := Vector2(46, 50)    # left / right slash hitbox
@export var pogo_up := -470.0
@export var pogo_down := 560.0
@export var pogo_side := 380.0
@export var pogo_diag_mult := 1.3                   # extra punch for diagonal bounces (down-right -> up-left, etc.)
@export var bounce_lock := 0.15

@export_group("Juice")
@export var shake_on_pogo := 7.0
@export var shake_decay := 38.0

@export_group("Looks")
@export var body_size := Vector2(28, 44)
@export var body_color := Color(0.36, 0.78, 1.0)

const KILL_Y := 900.0

signal cleared

var facing := 1.0
var dashes_left := 1
var dashing := false
var dash_dir := Vector2.ZERO
var attacking := false
var attack_dir := Vector2.DOWN
var bounced := false
var spawn_point := Vector2.ZERO
var was_on_floor := false
var shake := 0.0

var coyote_timer := 0.0
var buffer_timer := 0.0
var dash_cd_timer := 0.0
var dash_timer := 0.0
var attack_timer := 0.0
var attack_cd_timer := 0.0
var bounce_timer := 0.0

var body_vis: Polygon2D
var hitbox: Area2D
var hitbox_shape: CollisionShape2D
var hb_rect: RectangleShape2D
var hitbox_vis: Polygon2D
var sensor: Area2D
var cam: Camera2D

func _ready() -> void:
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = body_size
	cs.shape = r
	add_child(cs)
	body_vis = _rect_poly(body_size, body_color)
	add_child(body_vis)
	# layers: player on 2, collides with solids on 1
	set_collision_layer_value(1, false)
	set_collision_layer_value(2, true)
	set_collision_mask_value(1, true)
	# attack hitbox detects bounceable gadgets on layer 3
	hitbox = Area2D.new()
	hitbox.monitoring = false
	hitbox.collision_layer = 0
	hitbox.collision_mask = 0
	hitbox.set_collision_mask_value(3, true)
	add_child(hitbox)
	hitbox_shape = CollisionShape2D.new()
	hb_rect = RectangleShape2D.new()
	hb_rect.size = Vector2(40, 36)
	hitbox_shape.shape = hb_rect
	hitbox.add_child(hitbox_shape)
	hitbox_vis = Polygon2D.new()
	hitbox_vis.color = Color(1.0, 0.95, 0.4, 0.45)
	hitbox_vis.visible = false
	add_child(hitbox_vis)
	# sensor for pickups (layer 4) and hazards/goal (layer 5)
	sensor = Area2D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = 0
	sensor.set_collision_mask_value(4, true)
	sensor.set_collision_mask_value(5, true)
	var ss := CollisionShape2D.new()
	var sr := RectangleShape2D.new()
	sr.size = body_size
	ss.shape = sr
	sensor.add_child(ss)
	add_child(sensor)
	sensor.area_entered.connect(_on_sensor_area)
	# camera
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 9.0
	add_child(cam)
	dashes_left = max_dashes
	spawn_point = global_position

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_handle_attack(delta)
	if dashing:
		_do_dash(delta)
	else:
		_do_move(delta)
	_update_juice(delta)
	if global_position.y > KILL_Y:
		_respawn()

func _tick_timers(delta: float) -> void:
	coyote_timer -= delta
	buffer_timer -= delta
	dash_cd_timer -= delta
	attack_cd_timer -= delta
	bounce_timer -= delta

func _do_move(delta: float) -> void:
	var dir := Input.get_axis("left", "right")
	if dir != 0.0:
		facing = signf(dir)
	if bounce_timer > 0.0:
		pass
	elif dir != 0.0:
		var a := (accel if is_on_floor() else air_accel)
		velocity.x = move_toward(velocity.x, dir * max_speed, a * delta)
	else:
		var f := (friction if is_on_floor() else air_friction)
		velocity.x = move_toward(velocity.x, 0.0, f * delta)
	# gravity
	if velocity.y < 0.0:
		velocity.y += rise_gravity * delta
	else:
		velocity.y += fall_gravity * delta
	velocity.y = minf(velocity.y, max_fall)
	# wall slide (pressing into the wall while falling)
	var on_wall := is_on_wall_only()
	if on_wall and velocity.y > 0.0 and dir != 0.0 and signf(dir) == -signf(get_wall_normal().x):
		velocity.y = minf(velocity.y, wall_slide_speed)
	# grounded refills
	if is_on_floor():
		coyote_timer = coyote_time
		dashes_left = max_dashes
	# jump: ground/coyote first, otherwise wall jump
	if Input.is_action_just_pressed("jump"):
		buffer_timer = jump_buffer
	if buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = jump_velocity
		buffer_timer = 0.0
		coyote_timer = 0.0
	elif buffer_timer > 0.0 and on_wall:
		var n := get_wall_normal()
		velocity.y = wall_jump_velocity
		velocity.x = n.x * wall_jump_push
		bounce_timer = wall_jump_lock
		buffer_timer = 0.0
		dashes_left = max_dashes
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_mult
	if Input.is_action_just_pressed("dash") and dashes_left > 0 and dash_cd_timer <= 0.0:
		_start_dash()
	move_and_slide()
	_check_land()

func _check_land() -> void:
	if not was_on_floor and is_on_floor():
		_squash(Vector2(1.22, 0.8))
	was_on_floor = is_on_floor()

func _start_dash() -> void:
	var d := Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
	if d == Vector2.ZERO:
		d = Vector2(facing, 0.0)
	dash_dir = d.normalized()
	dashing = true
	dash_timer = dash_time
	dash_cd_timer = dash_cooldown
	dashes_left -= 1

func _do_dash(delta: float) -> void:
	dash_timer -= delta
	velocity = dash_dir * dash_speed
	move_and_slide()
	_check_land()
	if dash_timer <= 0.0:
		dashing = false
		velocity.x = clampf(velocity.x, -max_speed, max_speed)
		if velocity.y < 0.0:
			velocity.y *= 0.6

func _handle_attack(delta: float) -> void:
	if Input.is_action_just_pressed("attack") and not attacking and attack_cd_timer <= 0.0:
		_start_attack()
	if attacking:
		attack_timer -= delta
		if not bounced:
			_poll_bounce()
		if attack_timer <= 0.0:
			attacking = false
			hitbox.monitoring = false
			hitbox_vis.visible = false

func _start_attack() -> void:
	# 8-directional aim: hold any combination of WASD; default = facing
	var ax := Input.get_axis("left", "right")
	var ay := Input.get_axis("up", "down")
	var v := Vector2(ax, ay)
	if v == Vector2.ZERO:
		v = Vector2(facing, 0.0)
	attack_dir = v.normalized()
	if absf(attack_dir.x) > 0.1 and absf(attack_dir.y) > 0.1:
		hb_rect.size = attack_size_diag       # diagonal
	elif absf(attack_dir.y) > absf(attack_dir.x):
		hb_rect.size = attack_size_vert       # up / down
	else:
		hb_rect.size = attack_size_horiz      # left / right
	hitbox_shape.position = attack_dir * attack_reach
	var hx := hb_rect.size.x * 0.5
	var hy := hb_rect.size.y * 0.5
	var c := hitbox_shape.position
	hitbox_vis.polygon = PackedVector2Array([
		c + Vector2(-hx, -hy), c + Vector2(hx, -hy), c + Vector2(hx, hy), c + Vector2(-hx, hy)
	])
	hitbox_vis.visible = true
	hitbox.monitoring = true
	attacking = true
	bounced = false
	attack_timer = attack_time
	attack_cd_timer = attack_cooldown

func _poll_bounce() -> void:
	var bodies := hitbox.get_overlapping_bodies()
	if bodies.is_empty():
		return
	var hit: Node = bodies[0]
	bounced = true
	dashing = false
	dashes_left = max_dashes
	bounce_timer = bounce_lock
	if hit.has_meta("launch"):
		velocity = hit.get_meta("launch")
		bounce_timer = maxf(bounce_timer, 0.18)
	else:
		_apply_bounce()
	shake = shake_on_pogo
	_squash(Vector2(0.8, 1.25))
	if hit is Node2D:
		var n := hit as Node2D
		n.scale = Vector2(1.25, 0.78)
		var tw := create_tween()
		tw.tween_property(n, "scale", Vector2.ONE, 0.16)

func _apply_bounce() -> void:
	# Bounce opposite the slash direction. Diagonals push both axes, so a
	# down-right slash launches you up-left, etc. — boosted by pogo_diag_mult.
	var diag := absf(attack_dir.x) > 0.1 and absf(attack_dir.y) > 0.1
	var m := pogo_diag_mult if diag else 1.0
	if absf(attack_dir.x) > 0.1:
		velocity.x = -signf(attack_dir.x) * pogo_side * m
	if attack_dir.y > 0.1:        # slashed downward -> launch up
		velocity.y = pogo_up * m
	elif attack_dir.y < -0.1:     # slashed upward -> slam down
		velocity.y = pogo_down * m

func _on_sensor_area(area: Area2D) -> void:
	if area.is_in_group("hazard"):
		_respawn()
	elif area.is_in_group("goal"):
		cleared.emit()
	elif area.is_in_group("dash_crystal") and area.get_meta("active", true):
		dashes_left = max_dashes
		_consume_crystal(area)

func _consume_crystal(area: Area2D) -> void:
	area.set_meta("active", false)
	area.modulate = Color(1, 1, 1, 0.2)
	get_tree().create_timer(crystal_cooldown).timeout.connect(_reactivate_crystal.bind(area))

func _reactivate_crystal(area: Area2D) -> void:
	if is_instance_valid(area):
		area.set_meta("active", true)
		area.modulate = Color(1, 1, 1, 1)

func _update_juice(delta: float) -> void:
	if shake > 0.0:
		shake = maxf(0.0, shake - shake_decay * delta)
		cam.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		cam.offset = Vector2.ZERO

func _squash(s: Vector2) -> void:
	if body_vis == null:
		return
	body_vis.scale = s
	var tw := create_tween()
	tw.tween_property(body_vis, "scale", Vector2.ONE, 0.14)

func _respawn() -> void:
	global_position = spawn_point
	velocity = Vector2.ZERO
	dashes_left = max_dashes
	dashing = false
	attacking = false
	hitbox.monitoring = false
	hitbox_vis.visible = false

func _rect_poly(size: Vector2, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	p.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)
	])
	p.color = color
	return p
