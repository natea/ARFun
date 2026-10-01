extends Node3D
## Table tennis against a CPU. You hold a paddle in your right hand; touch the ball with it to
## return it. Returns are aim-assisted over the net (webcam tracking is only ~15 fps), and the
## direction and speed of your swing steer and speed up the shot. First to 11 wins.
## Expects to be a child of the node running pose_driver_3d.gd, with the table as child "Table".

const TOP_Y := 0.76
const HALF_WIDTH := 0.7625
const HALF_LENGTH := 1.37
const NET_HEIGHT := 0.1525
const NET_HALF_WIDTH := 0.915
const BALL_RADIUS := 0.02
const GRAVITY := 7.0  # slower than real life so rallies are playable with body tracking
const RESTITUTION := 0.9
const PADDLE_REACH := 0.26  # how close the ball must come to the paddle blade to count as a hit
## Tracking lags your real arm by roughly a tenth of a second, so hits are also tested against
## where the paddle is heading (its velocity this far ahead), not just where it is drawn.
const LATENCY_LOOKAHEAD := 0.12
## Balls coming at you move at this fraction of full speed, for more reaction time.
const APPROACH_SLOWMO := 0.75
const CPU_Z_BEHIND := 0.35  # how far behind its end line the CPU plays
const WIN_SCORE := 11
const SUBSTEPS := 4

enum State { WAITING, SERVING, RALLY, POINT_OVER, GAME_OVER }

@onready var _driver: Node = get_parent()
@onready var _table: Node3D = $Table

var active := false
var _state := State.WAITING
var _timer := 0.0
var _player_score := 0
var _cpu_score := 0
var _message := ""

var _ball := MeshInstance3D.new()
var _ball_shadow := MeshInstance3D.new()
var _ball_velocity := Vector3.ZERO
var _last_hitter := ""  # "player" or "cpu"
var _bounced_on := ""  # side of the table the ball has bounced on since the last hit
var _cpu_will_miss := false

var _player_paddle: Node3D
var _cpu_paddle: Node3D
var _paddle_prev := Vector3.ZERO
var _paddle_velocity := Vector3.ZERO
var _cpu_swing := 0.0

var _saved_camera: Transform3D
var _hud := CanvasLayer.new()
var _score_label := Label.new()
var _center_label := Label.new()
var _paddle_sound := AudioStreamPlayer.new()
var _table_sound := AudioStreamPlayer.new()
var _win_sound := AudioStreamPlayer.new()
var _lose_sound := AudioStreamPlayer.new()


func _ready() -> void:
	var paddle_scene: PackedScene = load("res://ping_pong/paddle.tscn")
	_player_paddle = paddle_scene.instantiate()
	_cpu_paddle = paddle_scene.instantiate()
	add_child(_player_paddle)
	add_child(_cpu_paddle)

	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	_ball.mesh = sphere
	var ball_material := StandardMaterial3D.new()
	ball_material.albedo_color = Color("#ff8c1a")
	ball_material.emission_enabled = true
	ball_material.emission = Color("#ff8c1a")
	ball_material.emission_energy_multiplier = 0.35
	_ball.material_override = ball_material
	add_child(_ball)

	# A soft dark disc on the table under the ball makes its height and depth easy to read.
	var disc := CylinderMesh.new()
	disc.top_radius = BALL_RADIUS * 1.4
	disc.bottom_radius = BALL_RADIUS * 1.4
	disc.height = 0.001
	_ball_shadow.mesh = disc
	var shadow_material := StandardMaterial3D.new()
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.albedo_color = Color(0, 0, 0, 0.45)
	_ball_shadow.material_override = shadow_material
	add_child(_ball_shadow)

	# Sounds from Kenney's Impact Sounds pack plus the ball game's chime/error (CC0).
	_paddle_sound.stream = load("res://sfx/pp_paddle.ogg")
	_table_sound.stream = load("res://sfx/pp_table.ogg")
	_table_sound.volume_db = -4.0
	_win_sound.stream = load("res://sfx/hit_chime.ogg")
	_lose_sound.stream = load("res://sfx/miss_error.ogg")
	for player in [_paddle_sound, _table_sound, _win_sound, _lose_sound]:
		add_child(player)

	add_child(_hud)
	for label in [_score_label, _center_label]:
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 8)
		_hud.add_child(label)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_score_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 40)
	_center_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 110)
	_center_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	set_active(false)


func set_active(on: bool) -> void:
	active = on
	visible = on
	_hud.visible = on
	set_process(on)
	var camera: Camera3D = _driver.get_node_or_null("Camera3D")
	if on:
		_state = State.WAITING
		_ball.visible = false
		_ball_shadow.visible = false
		if camera:
			# Look down the table from high up behind the player, off to their left so the
			# body doesn't hide the table and the right (paddle) hand stays in view.
			_saved_camera = camera.transform
			var eye := Vector3(0.9, 2.45, -2.3)
			var look_at_point := _table_center() + Vector3(0.0, TOP_Y, 0.2)
			camera.transform = Transform3D(Basis.looking_at(look_at_point - eye, Vector3.UP), eye)
			_driver.camera_offset_x = eye.x
	elif camera and _saved_camera != Transform3D():
		camera.transform = _saved_camera
		_driver.camera_offset_x = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if active and event.is_action_pressed("ui_accept") and _state in [State.WAITING, State.GAME_OVER]:
		_start_game()


# --- Table geometry (the table's origin is the floor under its center; +Z runs away from you) ---

func _table_center() -> Vector3:
	return _table.global_position


func _to_table(world: Vector3) -> Vector3:
	return world - _table_center()


func _side_of(local: Vector3) -> String:
	return "player" if local.z < 0.0 else "cpu"


func _on_table(local: Vector3) -> bool:
	return absf(local.x) <= HALF_WIDTH and absf(local.z) <= HALF_LENGTH


# --- Game flow ---

func _start_game() -> void:
	_player_score = 0
	_cpu_score = 0
	_message = ""
	_begin_serve()


func _begin_serve() -> void:
	_state = State.SERVING
	_timer = 1.2
	_ball.visible = false
	_ball_shadow.visible = false


func _serve() -> void:
	# The CPU serves from behind its end line straight onto your side of the table.
	var start := _table_center() + Vector3(randf_range(-0.4, 0.4), TOP_Y + 0.25, HALF_LENGTH + 0.15)
	_ball.global_position = start
	_ball.visible = true
	_shoot("cpu", _pick_target("player"), randf_range(0.95, 1.1))
	_state = State.RALLY


func _point(winner: String, why: String) -> void:
	if _state != State.RALLY:
		return
	if winner == "player":
		_player_score += 1
		_win_sound.play()
	else:
		_cpu_score += 1
		_lose_sound.play()
	_message = why
	if _player_score >= WIN_SCORE or _cpu_score >= WIN_SCORE:
		_state = State.GAME_OVER
		_timer = 2.5
		_message = "You win %d-%d!" % [_player_score, _cpu_score] if _player_score > _cpu_score \
			else "CPU wins %d-%d" % [_cpu_score, _player_score]
	else:
		_state = State.POINT_OVER
		_timer = 1.3


func _process(delta: float) -> void:
	_update_player_paddle(delta)
	_update_cpu_paddle(delta)
	match _state:
		State.WAITING:
			if _driver.is_arms_up():
				_start_game()
		State.SERVING:
			_timer -= delta
			if _timer <= 0.0:
				_serve()
		State.RALLY:
			var step := delta / SUBSTEPS
			for i in SUBSTEPS:
				_step_ball(step)
				if _state != State.RALLY:
					break
		State.POINT_OVER:
			_timer -= delta
			_step_ball_freely(delta)
			if _timer <= 0.0:
				_message = ""
				_begin_serve()
		State.GAME_OVER:
			_timer -= delta
			_step_ball_freely(delta)
			if _timer <= 0.0 and _driver.is_arms_up():
				_start_game()
	_update_shadow()
	_update_hud()


# --- Ball physics and rules ---

func _step_ball(dt: float) -> void:
	var before := _to_table(_ball.global_position)
	if _last_hitter == "cpu" and before.z < 0.0:
		dt *= APPROACH_SLOWMO
	_ball_velocity.y -= GRAVITY * dt
	_ball.global_position += _ball_velocity * dt
	var local := _to_table(_ball.global_position)

	# Net: a ball crossing the middle below the tape stops dead.
	if signf(before.z) != signf(local.z) and absf(local.x) < NET_HALF_WIDTH and local.y < TOP_Y + NET_HEIGHT + BALL_RADIUS:
		_ball_velocity = Vector3(_ball_velocity.x * 0.2, 0.0, -_ball_velocity.z * 0.15)
		_ball.global_position.z = _table_center().z + signf(before.z) * BALL_RADIUS
		_point("cpu" if _last_hitter == "player" else "player", "Net!")
		return

	# Table bounce.
	if _ball_velocity.y < 0.0 and local.y - BALL_RADIUS <= TOP_Y and before.y - BALL_RADIUS >= TOP_Y - 0.02 and _on_table(local):
		_ball.global_position.y = _table_center().y + TOP_Y + BALL_RADIUS
		_ball_velocity.y = -_ball_velocity.y * RESTITUTION
		_ball_velocity.x *= 0.97
		_ball_velocity.z *= 0.97
		_table_sound.pitch_scale = randf_range(0.95, 1.1)
		_table_sound.play()
		var side := _side_of(local)
		if side == _last_hitter:
			_point("cpu" if side == "player" else "player", "Bounced on your own side" if side == "player" else "CPU fault")
		elif _bounced_on == side:
			_point(_last_hitter, "Double bounce - point CPU" if side == "player" else "Double bounce - point you")
		else:
			_bounced_on = side
		return

	# The CPU returns the ball once it has bounced on its side and comes back down to it.
	if _last_hitter == "player" and _bounced_on == "cpu" and local.z > HALF_LENGTH - 0.25 and _ball_velocity.y < 0.6:
		if _cpu_will_miss:
			if local.z > HALF_LENGTH + CPU_Z_BEHIND + 0.4:
				_point("player", "CPU missed!")
		else:
			_cpu_swing = 1.0
			_paddle_sound.pitch_scale = randf_range(0.9, 1.05)
			_paddle_sound.play()
			var rally_speed := clampf(1.1 - (_player_score + _cpu_score) * 0.01, 0.85, 1.1)
			_shoot("cpu", _pick_target("player"), rally_speed * randf_range(0.95, 1.05))
		return

	# Your paddle.
	if _ball_velocity.z < 0.0 and _player_paddle.visible:
		var blade := _player_paddle.global_position
		var heading := (_paddle_velocity * LATENCY_LOOKAHEAD).limit_length(0.4)
		var nearest := Geometry3D.get_closest_point_to_segment(_ball.global_position, blade, blade + heading)
		if nearest.distance_to(_ball.global_position) < PADDLE_REACH:
			_player_hit()
			return

	# Out of play.
	if local.y < BALL_RADIUS or absf(local.x) > 3.0 or absf(local.z) > HALF_LENGTH + 2.0:
		if _bounced_on == "":
			# Hit straight out (never bounced on the other side): the hitter loses the point.
			_point("cpu" if _last_hitter == "player" else "player", "Out!" if _last_hitter == "player" else "CPU hit it out")
		else:
			_point(_last_hitter, "Missed it!" if _last_hitter == "cpu" else "CPU missed!")


func _step_ball_freely(dt: float) -> void:
	if not _ball.visible:
		return
	_ball_velocity.y -= GRAVITY * dt
	_ball.global_position += _ball_velocity * dt
	var local := _to_table(_ball.global_position)
	if local.y < BALL_RADIUS:
		_ball.global_position.y = _table_center().y + BALL_RADIUS
		_ball_velocity = Vector3(_ball_velocity.x * 0.6, -_ball_velocity.y * 0.5, _ball_velocity.z * 0.6)
	elif _ball_velocity.y < 0.0 and local.y - BALL_RADIUS <= TOP_Y and _on_table(local) and local.y > TOP_Y - 0.05:
		_ball.global_position.y = _table_center().y + TOP_Y + BALL_RADIUS
		_ball_velocity.y = -_ball_velocity.y * RESTITUTION


func _player_hit() -> void:
	_paddle_sound.pitch_scale = randf_range(1.0, 1.15)
	_paddle_sound.play()
	# Swinging sideways steers the ball; swinging fast makes it faster (shorter flight time).
	var swing := _paddle_velocity
	var target := _pick_target("cpu")
	target.x = clampf(target.x + swing.x * 0.25, _table_center().x - HALF_WIDTH + 0.12, _table_center().x + HALF_WIDTH - 0.12)
	var flight := clampf(1.0 - swing.length() * 0.1, 0.65, 1.0)
	_shoot("player", target, flight)
	# The CPU misses more often against fast shots.
	_cpu_will_miss = randf() < clampf(0.1 + (1.0 - flight) * 1.0, 0.1, 0.45)


## A random landing spot on `side` of the table, in world space.
func _pick_target(side: String) -> Vector3:
	var z_sign := -1.0 if side == "player" else 1.0
	var local := Vector3(randf_range(-0.5, 0.5), TOP_Y + BALL_RADIUS, z_sign * randf_range(0.55, 1.1))
	if side == "player":
		# Aim roughly where you are standing so it stays reachable.
		var paddle_x := _to_table(_player_paddle.global_position).x
		local.x = clampf(lerpf(local.x, paddle_x, 0.6), -0.6, 0.6)
	return _table_center() + local


## Launch the ball on a ballistic arc that lands on `target` after `flight` seconds,
## lengthening the flight if needed so it clears the net.
func _shoot(hitter: String, target: Vector3, flight: float) -> void:
	_last_hitter = hitter
	_bounced_on = ""
	var start := _ball.global_position
	var velocity := _ballistic(start, target, flight)
	for i in 8:
		if _clears_net(start, velocity):
			break
		flight += 0.1
		velocity = _ballistic(start, target, flight)
	_ball_velocity = velocity


func _ballistic(start: Vector3, target: Vector3, flight: float) -> Vector3:
	var v := (target - start) / flight
	v.y += 0.5 * GRAVITY * flight
	return v


func _clears_net(start: Vector3, velocity: Vector3) -> bool:
	var net_z := _table_center().z
	if is_zero_approx(velocity.z):
		return false
	var t := (net_z - start.z) / velocity.z
	if t <= 0.0:
		return true
	var height := start.y + velocity.y * t - 0.5 * GRAVITY * t * t - _table_center().y
	return height > TOP_Y + NET_HEIGHT + 0.06


# --- Paddles, shadow, HUD ---

func _update_player_paddle(delta: float) -> void:
	var elbow = _driver.get_limb_joint("r_lower_arm")
	var hand = _driver.get_limb_joint("r_hand")
	if elbow == null or hand == null:
		_player_paddle.visible = false
		return
	_player_paddle.visible = true
	# The paddle's handle sits in the hand and its blade extends along the forearm, face forward.
	var along: Vector3 = (hand - elbow).normalized()
	var face := Vector3.FORWARD.slide(along).normalized() * -1.0  # facing +Z, towards the table
	if face.is_zero_approx():
		face = Vector3.UP
	var side := face.cross(along).normalized()
	var blade_center: Vector3 = hand + along * 0.16
	_player_paddle.global_transform = Transform3D(Basis(side, face, along), blade_center)
	_paddle_velocity = (blade_center - _paddle_prev) / maxf(delta, 0.001)
	_paddle_prev = blade_center


func _update_cpu_paddle(delta: float) -> void:
	var goal := _table_center() + Vector3(0.0, TOP_Y + 0.25, HALF_LENGTH + CPU_Z_BEHIND)
	if _ball.visible and _ball_velocity.z > 0.0:
		goal.x = _ball.global_position.x
		goal.y = clampf(_ball.global_position.y, _table_center().y + TOP_Y + 0.05, _table_center().y + TOP_Y + 0.6)
	var position_now := _cpu_paddle.global_position.lerp(goal, 1.0 - exp(-6.0 * delta))
	_cpu_swing = maxf(_cpu_swing - delta * 4.0, 0.0)
	# Blade faces you (-Z), handle down (the paddle's +Z, handle-to-tip, points up); a quick tilt when it swings.
	var paddle_basis := Basis(Vector3.RIGHT, -PI / 2.0 + _cpu_swing * 0.8)
	_cpu_paddle.global_transform = Transform3D(paddle_basis, position_now)


func _update_shadow() -> void:
	var local := _to_table(_ball.global_position)
	_ball_shadow.visible = _ball.visible and _on_table(local) and local.y > TOP_Y
	if _ball_shadow.visible:
		_ball_shadow.global_position = _table_center() + Vector3(local.x, TOP_Y + 0.002, local.z)


func _update_hud() -> void:
	_score_label.text = "You %d  -  %d CPU" % [_player_score, _cpu_score]
	match _state:
		State.WAITING:
			_center_label.text = "Ping Pong: the paddle is in your right hand\nRaise both hands to start (or press Space)"
		State.GAME_OVER:
			var again := "\nRaise both hands to play again" if _timer <= 0.0 else ""
			_center_label.text = _message + again
		_:
			_center_label.text = _message
