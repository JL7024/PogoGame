class_name Player
extends CharacterBody2D
# Celeste-style precise movement + a 4-directional attack that bounces you off
# "bounceable" gadgets (the orange blocks). Tune the feel from the values below.

# ─────────── Tunable feel parameters — edit, then press F5 to test ───────────
@export_group("Run")
@export var max_speed := 220.0
@export var accel := 1800.0
@export var friction := 2200.0
@export var air_accel := 1500.0
@export var air_friction := 800.0

@export_group("Jump / Gravity")
@export var jump_velocity := -430.0
@export var rise_gravity := 1100.0     # gravity while moving up (lower = floatier rise)
@export var fall_gravity := 1600.0     # gravity while falling (higher = snappier)
@export var max_fall := 700.0
@export var jump_cut_mult := 0.45      # variable height: cut up-speed when jump released early
@export var coyote_time := 0.10        # can still jump shortly after leaving a ledge
@export var jump_buffer := 0.12        # a jump press shortly before landing still counts

@export_group("Dash")
@export var dash_speed := 520.0
@export var dash_time := 0.14
@export var dash_cooldown := 0.10
@export var max_dashes := 1

@export_group("Attack / Pogo")
@export var attack_time := 0.16        # how long the hitbox stays active
@export var attack_cooldown := 0.22
@export var pogo_up := -470.0          # down-slash hit  -> launch UP
@export var pogo_down := 560.0         # up-slash hit    -> slam DOWN
@export var pogo_side := 380.0         # side-slash hit  -> push the opposite way
@export var bounce_lock := 0.12        # briefly keep bounce momentum (ignore friction)

@export_group("Looks")
@export var body_size := Vector2(28, 44)
@export var body_color := Color(0.36, 0.78, 1.0)

const KILL_Y := 760.0

# ─────────── State ───────────
var facing := 1.0
var dashes_left := 1
var dashing := false
var dash_dir := Vector2.ZERO
var attacking := false
var attack_dir := Vector2.DOWN
var bounced := false
var spawn_point := Vector2.ZERO

var coyote_timer := 0.0
var buffer_timer := 0.0
var dash_cd_timer := 0.0
var dash_timer := 0.0
var attack_timer := 0.0
var attack_cd_timer := 0.0
var bounce_timer := 0.0

var hitbox: Area2D
var hitbox_shape: CollisionShape2D
var hb_rect: RectangleShape2D
var hitbox_vis: Polygon2D

func _ready() -> void:
	# body collision shape
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = body_size
	cs.shape = r
	add_child(cs)
	# body visual
	add_child(_rect_poly(body_size, body_color))
	# collision layers: player on layer 2, collides with solids on layer 1
	set_collision_layer_value(1, false)
	set_collision_layer_value(2, true)
	set_collision_mask_value(1, true)
	# attack hitbox (detects bounceable gadgets on layer 3)
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
	# camera follows the player
	var cam := Camera2D.new()
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
	# horizontal control (skipped briefly after a bounce so momentum carries)
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
	# grounded refills
	if is_on_floor():
		coyote_timer = coyote_time
		dashes_left = max_dashes
	# jump with buffer + coyote time
	if Input.is_action_just_pressed("jump"):
		buffer_timer = jump_buffer
	if buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = jump_velocity
		buffer_timer = 0.0
		coyote_timer = 0.0
	# variable jump height
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_mult
	# dash
	if Input.is_action_just_pressed("dash") and dashes_left > 0 and dash_cd_timer <= 0.0:
		_start_dash()
	move_and_slide()

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
	# aim: hold Down/Up for a down/up slash, otherwise slash where you face
	if Input.is_action_pressed("down"):
		attack_dir = Vector2.DOWN
	elif Input.is_action_pressed("up"):
		attack_dir = Vector2.UP
	else:
		attack_dir = Vector2(facing, 0.0)
	var reach := 36.0
	if attack_dir == Vector2.DOWN:
		hb_rect.size = Vector2(40, 36)
		hitbox_shape.position = Vector2(0, reach)
	elif attack_dir == Vector2.UP:
		hb_rect.size = Vector2(40, 36)
		hitbox_shape.position = Vector2(0, -reach)
	else:
		hb_rect.size = Vector2(34, 40)
		hitbox_shape.position = Vector2(reach * attack_dir.x, 0)
	# match the visible swing rectangle to the hitbox
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
	bounced = true
	dashing = false                 # a dash can cancel straight into a pogo
	dashes_left = max_dashes         # refill dash on a pogo (rewards chaining)
	bounce_timer = bounce_lock
	if attack_dir == Vector2.DOWN:
		velocity.y = pogo_up
	elif attack_dir == Vector2.UP:
		velocity.y = pogo_down
	elif attack_dir.x > 0.0:         # hit something on the right -> pushed left
		velocity.x = -pogo_side
	else:                            # hit something on the left -> pushed right
		velocity.x = pogo_side
	# squash feedback on whatever we hit
	var hit := bodies[0]
	if hit is Node2D:
		var n := hit as Node2D
		n.scale = Vector2(1.25, 0.78)
		var tw := create_tween()
		tw.tween_property(n, "scale", Vector2.ONE, 0.16)

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
