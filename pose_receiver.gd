extends Node2D
## Receives MediaPipe pose landmarks from tracker/tracker.py over UDP,
## draws a stick figure of the player, and turns gestures into movement:
##   lean left/right -> walk,  both hands above head -> jump.

const PORT := 4242
const STALE_AFTER := 0.5  # seconds without packets before we say "no tracking"
const MIN_VISIBILITY := 0.5

const LEAN_THRESHOLD := 0.03
const MOVE_SPEED := 360.0
const JUMP_VELOCITY := -700.0
const GRAVITY := 1800.0

# MediaPipe pose landmark indices
const NOSE := 0
const L_SHOULDER := 11
const R_SHOULDER := 12
const L_WRIST := 15
const R_WRIST := 16
const L_HIP := 23
const R_HIP := 24
const BONES := [
	[11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
	[11, 23], [12, 24], [23, 24],
	[23, 25], [25, 27], [24, 26], [26, 28],
]

# Layout: stick figure panel on the left, play area on the right
const PANEL := Rect2(40, 80, 560, 560)
const PLAY_LEFT := 680.0
const PLAY_RIGHT := 1240.0
const GROUND_Y := 600.0
const PLAYER_SIZE := Vector2(40, 60)

var _udp := PacketPeerUDP.new()
var _landmarks: Array = []
var _image_aspect := 4.0 / 3.0
var _last_packet_time := -INF

var _lean := 0.0
var _arms_up := false
var _was_arms_up := false

var _player_pos := Vector2((PLAY_LEFT + PLAY_RIGHT) / 2.0, GROUND_Y)
var _player_vel := Vector2.ZERO


func _ready() -> void:
	var err := _udp.bind(PORT, "127.0.0.1")
	if err != OK:
		push_error("Could not listen on UDP port %d (error %d)" % [PORT, err])


func _exit_tree() -> void:
	_udp.close()


func _process(delta: float) -> void:
	_receive_packets()
	_read_gestures()
	_update_player(delta)
	queue_redraw()


func _receive_packets() -> void:
	while _udp.get_available_packet_count() > 0:
		var data = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
		if data is Dictionary and data.has("lm"):
			_landmarks = data["lm"]
			if data.get("h", 0) > 0:
				_image_aspect = float(data["w"]) / float(data["h"])
			_last_packet_time = Time.get_ticks_msec() / 1000.0


func _is_tracking() -> bool:
	return _landmarks.size() >= 29 and Time.get_ticks_msec() / 1000.0 - _last_packet_time < STALE_AFTER


func _visible(index: int) -> bool:
	return _landmarks[index][3] >= MIN_VISIBILITY


## Normalized image coordinates (0..1, y down) of a landmark, mirrored so the stick figure
## moves like your reflection (the tracker sends the unmirrored camera view).
func _point(index: int) -> Vector2:
	return Vector2(1.0 - _landmarks[index][0], _landmarks[index][1])


func _read_gestures() -> void:
	_lean = 0.0
	_arms_up = false
	if not _is_tracking():
		return
	if _visible(L_SHOULDER) and _visible(R_SHOULDER) and _visible(L_HIP) and _visible(R_HIP):
		var shoulders := (_point(L_SHOULDER) + _point(R_SHOULDER)) / 2.0
		var hips := (_point(L_HIP) + _point(R_HIP)) / 2.0
		_lean = shoulders.x - hips.x
	if _visible(NOSE) and _visible(L_WRIST) and _visible(R_WRIST):
		var nose_y := _point(NOSE).y
		_arms_up = _point(L_WRIST).y < nose_y and _point(R_WRIST).y < nose_y


func _update_player(delta: float) -> void:
	var on_ground := _player_pos.y >= GROUND_Y
	_player_vel.x = 0.0
	if absf(_lean) > LEAN_THRESHOLD:
		_player_vel.x = signf(_lean) * MOVE_SPEED

	if _arms_up and not _was_arms_up and on_ground:
		_player_vel.y = JUMP_VELOCITY
	_was_arms_up = _arms_up

	_player_vel.y += GRAVITY * delta
	_player_pos += _player_vel * delta
	if _player_pos.y >= GROUND_Y:
		_player_pos.y = GROUND_Y
		_player_vel.y = 0.0
	var half_w := PLAYER_SIZE.x / 2.0
	_player_pos.x = clampf(_player_pos.x, PLAY_LEFT + half_w, PLAY_RIGHT - half_w)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("#14161c"))

	# Stick figure panel
	draw_rect(PANEL, Color("#1e222b"))
	draw_rect(PANEL, Color("#3a4150"), false, 2.0)
	if _is_tracking():
		_draw_stick_figure()
		draw_string(font, Vector2(40, 60), "Tracking", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#5be08a"))
	else:
		var waiting := "Tracker connected - no person in view" if Time.get_ticks_msec() / 1000.0 - _last_packet_time < STALE_AFTER else "Waiting for tracker on UDP %d..." % PORT
		draw_string(font, Vector2(40, 60), waiting, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#e0b35b"))
		draw_string(font, PANEL.get_center() + Vector2(-200, 0), "Run: uv run tracker/tracker.py", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#8a93a6"))

	# Play area
	draw_line(Vector2(PLAY_LEFT, GROUND_Y), Vector2(PLAY_RIGHT, GROUND_Y), Color("#8a93a6"), 3.0)
	var player_rect := Rect2(_player_pos - Vector2(PLAYER_SIZE.x / 2.0, PLAYER_SIZE.y), PLAYER_SIZE)
	draw_rect(player_rect, Color("#ff7a45") if _arms_up else Color("#45b3ff"))

	# Gesture readout
	var lean_text := "standing"
	if _lean > LEAN_THRESHOLD:
		lean_text = "leaning RIGHT"
	elif _lean < -LEAN_THRESHOLD:
		lean_text = "leaning LEFT"
	draw_string(font, Vector2(PLAY_LEFT, 120), "Lean: %s (%.3f)" % [lean_text, _lean], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(PLAY_LEFT, 155), "Arms up: %s" % ("YES - jump!" if _arms_up else "no"), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(PLAY_LEFT, 680), "Lean to walk. Raise both hands above your head to jump.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#8a93a6"))


func _to_panel(p: Vector2) -> Vector2:
	# Fit the camera image into the square panel while keeping its aspect ratio.
	var size := PANEL.size
	if _image_aspect >= 1.0:
		size.y = PANEL.size.x / _image_aspect
	else:
		size.x = PANEL.size.y * _image_aspect
	var origin := PANEL.position + (PANEL.size - size) / 2.0
	return origin + p * size


func _draw_stick_figure() -> void:
	var bone_color := Color("#5be08a")
	for bone in BONES:
		if _visible(bone[0]) and _visible(bone[1]):
			draw_line(_to_panel(_point(bone[0])), _to_panel(_point(bone[1])), bone_color, 6.0, true)
	if _visible(NOSE):
		var head := _to_panel(_point(NOSE))
		var shoulder_width := 60.0
		if _visible(L_SHOULDER) and _visible(R_SHOULDER):
			shoulder_width = _to_panel(_point(L_SHOULDER)).distance_to(_to_panel(_point(R_SHOULDER)))
		draw_circle(head, shoulder_width * 0.3, bone_color, false, 4.0, true)
	for index in [L_WRIST, R_WRIST]:
		if _visible(index):
			draw_circle(_to_panel(_point(index)), 9.0, Color("#ff7a45") if _arms_up else Color.WHITE)
