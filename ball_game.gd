extends Node3D
## Balls fly at the character; hit them with an arm or leg to score.
## Raise both hands above your head (or press Space/Enter) to start a round.
## Expects to be a child of the node running pose_driver_3d.gd.

const ROUND_LENGTH := 60.0
const BALL_RADIUS := 0.12
const LIMB_RADIUS := 0.1
const SPAWN_DISTANCE := 7.0  # how far in front of the character balls start
const MISS_PAST := 0.6  # a ball this far past its target is a miss
const START_SPEED := 3.0
const END_SPEED := 5.0
const START_INTERVAL := 1.8
const END_INTERVAL := 1.1
const RESTART_DELAY := 2.5
const COLORS := [Color("#ff5a5f"), Color("#ffb400"), Color("#3ddc97"), Color("#4fc3f7"), Color("#c77dff")]

enum State { WAITING, PLAYING, OVER }

@onready var _driver: Node = get_parent()

var _state := State.WAITING
var _time_left := 0.0
var _spawn_timer := 0.0
var _restart_timer := 0.0
var _score := 0
var _streak := 0
var _best_streak := 0
var _hits := 0
var _misses := 0
var _balls: Array[Dictionary] = []  # {node, velocity, hit, life}
var _ball_mesh := SphereMesh.new()
var _score_label := Label.new()
var _center_label := Label.new()
var _hit_sound := AudioStreamPlayer.new()
var _chime_sound := AudioStreamPlayer.new()
var _miss_sound := AudioStreamPlayer.new()
var _hud := CanvasLayer.new()
var active := true


func _ready() -> void:
	# Sounds from Kenney's Impact Sounds and Interface Sounds packs (CC0, see sfx/Kenney_*_License.txt).
	_hit_sound.stream = load("res://sfx/hit_thump.ogg")
	_chime_sound.stream = load("res://sfx/hit_chime.ogg")
	_chime_sound.volume_db = -3.0
	_miss_sound.stream = load("res://sfx/miss_error.ogg")
	add_child(_chime_sound)
	add_child(_hit_sound)
	add_child(_miss_sound)
	_ball_mesh.radius = BALL_RADIUS
	_ball_mesh.height = BALL_RADIUS * 2.0
	var hud := _hud
	add_child(hud)
	for label in [_score_label, _center_label]:
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 8)
		hud.add_child(label)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_score_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 40)
	_center_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 110)
	_center_label.grow_horizontal = Control.GROW_DIRECTION_BOTH


## Turned on and off by the game menu.
func set_active(on: bool) -> void:
	active = on
	_hud.visible = on
	set_process(on)
	_state = State.WAITING
	for ball in _balls.duplicate():
		_remove(ball)


func _unhandled_input(event: InputEvent) -> void:
	if active and event.is_action_pressed("ui_accept") and _state != State.PLAYING:
		start_round()


func start_round() -> void:
	_state = State.PLAYING
	_time_left = ROUND_LENGTH
	_spawn_timer = 1.0
	_score = 0
	_streak = 0
	_best_streak = 0
	_hits = 0
	_misses = 0


func _process(delta: float) -> void:
	match _state:
		State.WAITING:
			if _driver.is_arms_up():
				start_round()
		State.PLAYING:
			_time_left -= delta
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				_spawn_ball()
				_spawn_timer = lerpf(START_INTERVAL, END_INTERVAL, _progress())
			if _time_left <= 0.0:
				_state = State.OVER
				_restart_timer = RESTART_DELAY
		State.OVER:
			_restart_timer -= delta
			if _restart_timer <= 0.0 and _driver.is_arms_up():
				start_round()
	_update_balls(delta)
	_update_hud()


func _progress() -> float:
	return clampf(1.0 - _time_left / ROUND_LENGTH, 0.0, 1.0)


func _spawn_ball() -> void:
	var center: Vector3 = _driver.get_character_position()
	# Aim somewhere within reach: from the shins up to above the head, arm's length to each side.
	var target := center + Vector3(randf_range(-0.8, 0.8), randf_range(0.3, 1.95), 0.15)
	# The camera looks over the character's shoulder (towards +Z); balls come from the far side at them.
	var start := Vector3(center.x + randf_range(-2.5, 2.5), randf_range(0.6, 2.4), center.z + SPAWN_DISTANCE)
	var speed := lerpf(START_SPEED, END_SPEED, _progress()) * randf_range(0.9, 1.1)

	var material := StandardMaterial3D.new()
	material.albedo_color = COLORS.pick_random()
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.4
	var ball := MeshInstance3D.new()
	ball.mesh = _ball_mesh
	ball.material_override = material
	add_child(ball)
	ball.global_position = start
	_balls.append({"node": ball, "velocity": (target - start).normalized() * speed, "target": target, "hit": false, "life": 1.0})


func _update_balls(delta: float) -> void:
	var segments: Array = _driver.get_limb_segments() if _state == State.PLAYING else []
	for ball in _balls.duplicate():
		var node: MeshInstance3D = ball["node"]
		if ball["hit"]:
			ball["velocity"].y -= 9.8 * delta
			ball["life"] -= delta
			node.global_position += ball["velocity"] * delta
			node.scale = Vector3.ONE * maxf(ball["life"], 0.01)
			if ball["life"] <= 0.0:
				_remove(ball)
			continue

		node.global_position += ball["velocity"] * delta
		var closest = _closest_limb_point(node.global_position, segments)
		if closest != null:
			_on_hit(ball, closest)
		elif (node.global_position - ball["target"]).dot(ball["velocity"].normalized()) > MISS_PAST:
			_streak = 0
			_misses += 1
			_miss_sound.play()
			_remove(ball)


## The nearest point on any limb within touching distance of `ball_position`, or null.
func _closest_limb_point(ball_position: Vector3, segments: Array):
	var best = null
	var best_distance := BALL_RADIUS + LIMB_RADIUS
	for segment in segments:
		var point := Geometry3D.get_closest_point_to_segment(ball_position, segment[0], segment[1])
		var distance := point.distance_to(ball_position)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


func _on_hit(ball: Dictionary, limb_point: Vector3) -> void:
	var node: MeshInstance3D = ball["node"]
	var away := (node.global_position - limb_point).normalized()
	if away.is_zero_approx():
		away = Vector3.UP
	# Knock the ball back into the scene, away from the limb.
	ball["velocity"] = away * 4.0 + Vector3(0.0, 3.0, 6.0)
	ball["hit"] = true
	var material: StandardMaterial3D = node.material_override
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 3.0

	_streak += 1
	_hits += 1
	_best_streak = maxi(_best_streak, _streak)
	var points := 10 * (1 + floori(_streak / 5.0))
	# A thump for the contact plus a chime that climbs in pitch as the streak grows.
	_hit_sound.pitch_scale = randf_range(0.92, 1.08)
	_hit_sound.play()
	_chime_sound.pitch_scale = 1.0 + minf(_streak - 1, 12) * 0.06
	_chime_sound.play()
	_score += points
	_popup("+%d" % points, node.global_position, material.albedo_color)


func _popup(text: String, at: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.outline_size = 16
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	label.global_position = at
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 0.6, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


func _remove(ball: Dictionary) -> void:
	ball["node"].queue_free()
	_balls.erase(ball)


func _update_hud() -> void:
	match _state:
		State.WAITING:
			_score_label.text = ""
			_center_label.text = "Raise both hands to start\n(or press Space)"
		State.PLAYING:
			_score_label.text = "Score %d\nStreak %d\nTime %d" % [_score, _streak, ceili(_time_left)]
			_center_label.text = ""
		State.OVER:
			_score_label.text = ""
			var again := "Raise both hands to play again" if _restart_timer <= 0.0 else ""
			_center_label.text = "Time!\nScore %d  -  %d hits, %d missed\nBest streak %d\n%s" % [
				_score, _hits, _misses, _best_streak, again]
