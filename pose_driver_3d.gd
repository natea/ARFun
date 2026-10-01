extends Node3D
## Drives a humanoid skeleton from MediaPipe world landmarks sent by tracker/tracker.py.
## Works with the built-in Mannequin or any Mixamo character (set `character_scene`).
## Each limb bone is swung so it points the same way as your matching limb;
## hips, spine and head get a full orientation from the hip, shoulder and ear lines.

const PORT := 4242
const STALE_AFTER := 1.5  # webcams in dim light can drop to a few frames per second
const MIN_VISIBILITY := 0.5
const HEAD_PITCH_OFFSET := deg_to_rad(-15.0)  # the nose sits a bit below the ears

## A rigged character (e.g. a Mixamo .fbx) to use instead of the built-in Mannequin.
@export var character_scene: PackedScene
## Uniform scale for `character_scene` (Mixamo kids like Amy are ~1.4 m tall).
@export var character_scale := 1.0
## Higher = snappier, lower = smoother.
@export var smoothing := 40.0
## Slide the character sideways as you move across the camera's view.
@export var follow_sideways := true
## Meters the character travels as your hips cross the full width of the camera image.
@export var sideways_range := 6.0
## Keep the character on the floor.
@export var max_sideways := 3.0
## How much the camera follows the character sideways (0 = fixed, 1 = locked on).
@export var camera_follow := 0.6
## Sideways camera offset the follow is added to (games can set this, e.g. an over-the-shoulder view).
var camera_offset_x := 0.0

# MediaPipe pose landmark indices
const NOSE := 0
const L_EAR := 7
const R_EAR := 8
const L_SHOULDER := 11
const R_SHOULDER := 12
const L_ELBOW := 13
const R_ELBOW := 14
const L_WRIST := 15
const R_WRIST := 16
const L_PINKY := 17
const R_PINKY := 18
const L_INDEX := 19
const R_INDEX := 20
const L_HIP := 23
const R_HIP := 24
const L_KNEE := 25
const R_KNEE := 26
const L_ANKLE := 27
const R_ANKLE := 28
const L_FOOT := 31
const R_FOOT := 32

# Rig profiles. Bone names are matched without any "mixamorig:" style prefix.
# torso: bone -> blend between the hip frame (0) and the shoulder frame (1)
# limbs: bone -> [bone whose joint the limb points at ("" = use the Mannequin tip), limb name]
const MANNEQUIN_RIG := {
	"torso": {"Hips": 0.0, "Spine": 0.5, "Chest": 1.0},
	"neck": "Neck", "head": "Head",
	"limbs": {
		"LeftUpperArm": ["LeftLowerArm", "l_upper_arm"], "LeftLowerArm": ["LeftHand", "l_lower_arm"], "LeftHand": ["", "l_hand"],
		"RightUpperArm": ["RightLowerArm", "r_upper_arm"], "RightLowerArm": ["RightHand", "r_lower_arm"], "RightHand": ["", "r_hand"],
		"LeftUpperLeg": ["LeftLowerLeg", "l_upper_leg"], "LeftLowerLeg": ["LeftFoot", "l_lower_leg"], "LeftFoot": ["", "l_foot"],
		"RightUpperLeg": ["RightLowerLeg", "r_upper_leg"], "RightLowerLeg": ["RightFoot", "r_lower_leg"], "RightFoot": ["", "r_foot"],
	},
}
const MIXAMO_RIG := {
	"torso": {"Hips": 0.0, "Spine": 0.33, "Spine1": 0.66, "Spine2": 1.0},
	"neck": "Neck", "head": "Head",
	"limbs": {
		"LeftArm": ["LeftForeArm", "l_upper_arm"], "LeftForeArm": ["LeftHand", "l_lower_arm"], "LeftHand": ["LeftHandMiddle1", "l_hand"],
		"RightArm": ["RightForeArm", "r_upper_arm"], "RightForeArm": ["RightHand", "r_lower_arm"], "RightHand": ["RightHandMiddle1", "r_hand"],
		"LeftUpLeg": ["LeftLeg", "l_upper_leg"], "LeftLeg": ["LeftFoot", "l_lower_leg"], "LeftFoot": ["LeftToeBase", "l_foot"],
		"RightUpLeg": ["RightLeg", "r_upper_leg"], "RightLeg": ["RightFoot", "r_lower_leg"], "RightFoot": ["RightToeBase", "r_foot"],
	},
}
# limb name -> [from landmark, to landmarks (averaged)]
const LIMB_LANDMARKS := {
	"l_upper_arm": [L_SHOULDER, [L_ELBOW]], "l_lower_arm": [L_ELBOW, [L_WRIST]], "l_hand": [L_WRIST, [L_INDEX, L_PINKY]],
	"r_upper_arm": [R_SHOULDER, [R_ELBOW]], "r_lower_arm": [R_ELBOW, [R_WRIST]], "r_hand": [R_WRIST, [R_INDEX, R_PINKY]],
	"l_upper_leg": [L_HIP, [L_KNEE]], "l_lower_leg": [L_KNEE, [L_ANKLE]], "l_foot": [L_ANKLE, [L_FOOT]],
	"r_upper_leg": [R_HIP, [R_KNEE]], "r_lower_leg": [R_KNEE, [R_ANKLE]], "r_foot": [R_ANKLE, [R_FOOT]],
}

@onready var _status: Label = $HUD/Status
@onready var _camera: Camera3D = get_node_or_null("Camera3D")

var _character: Node3D
var _skeleton: Skeleton3D
var _rig: Dictionary
var _bones := {}  # rig bone name -> skeleton bone index
var _to_skeleton := Quaternion.IDENTITY  # character space -> skeleton space
var _rest_global_rot := {}  # bone index -> Quaternion (skeleton space)
var _rest_dir := {}  # bone index -> unit Vector3 (skeleton space)
var _hit_segments := []  # [bone index, child bone index] along each limb
var _hit_points := []  # bone indices of hands and feet

var _udp := PacketPeerUDP.new()
var _world: Array = []
var _image: Array = []
var _last_packet_time := -INF


func _ready() -> void:
	_status.add_theme_font_size_override("font_size", 22)
	_setup_character()
	var err := _udp.bind(PORT, "127.0.0.1")
	if err != OK:
		push_error("Could not listen on UDP port %d (error %d)" % [PORT, err])


func _exit_tree() -> void:
	_udp.close()


func _setup_character() -> void:
	var mannequin: Node3D = $Mannequin
	_character = mannequin
	if character_scene:
		_character = character_scene.instantiate()
		_character.scale = Vector3.ONE * character_scale
		add_child(_character)
		mannequin.hide()
		mannequin.process_mode = Node.PROCESS_MODE_DISABLED
	_skeleton = _find_skeleton(_character)
	if _skeleton == null:
		push_error("No Skeleton3D found in the character")
		return

	var by_name := {}
	var prefix := RegEx.create_from_string("^mixamorig\\d*[:_]")
	for idx in _skeleton.get_bone_count():
		by_name[prefix.sub(_skeleton.get_bone_name(idx), "")] = idx
	_rig = MIXAMO_RIG if by_name.has("LeftForeArm") else MANNEQUIN_RIG
	for bone_name in _rig["torso"].keys() + [_rig["neck"], _rig["head"]] + _rig["limbs"].keys():
		if by_name.has(bone_name):
			_bones[bone_name] = by_name[bone_name]

	# Everything is posed in skeleton space; the character may be rotated/scaled by its import.
	var relative := global_transform.affine_inverse() * _skeleton.global_transform
	_to_skeleton = relative.basis.get_rotation_quaternion().inverse()

	for bone_name in _bones:
		var idx: int = _bones[bone_name]
		var rest := _skeleton.get_bone_global_rest(idx)
		_rest_global_rot[idx] = rest.basis.get_rotation_quaternion()
	for bone_name in _rig["limbs"]:
		if not _bones.has(bone_name):
			continue
		var idx: int = _bones[bone_name]
		var child_name: String = _rig["limbs"][bone_name][0]
		var rest := _skeleton.get_bone_global_rest(idx)
		var direction: Vector3
		if child_name != "" and by_name.has(child_name):
			direction = _skeleton.get_bone_global_rest(by_name[child_name]).origin - rest.origin
		elif _skeleton is Mannequin:
			direction = rest.basis * _skeleton.get_bone_tip(bone_name)
		else:
			continue
		_rest_dir[idx] = direction.normalized()
		if child_name != "" and by_name.has(child_name):
			_hit_segments.append([idx, by_name[child_name]])
		var limb: String = _rig["limbs"][bone_name][1]
		if limb.ends_with("hand") or limb.ends_with("foot"):
			_hit_points.append(idx)
	print("Driving %s: %d/%d rig bones found" % [_character.name, _bones.size(),
		_rig["torso"].size() + 2 + _rig["limbs"].size()])


## World-space [start, end] segments along the arms and legs (hands and feet as points), for hit tests.
func get_limb_segments() -> Array:
	var segments := []
	if _skeleton == null:
		return segments
	for pair in _hit_segments:
		segments.append([_bone_world(pair[0]), _bone_world(pair[1])])
	for idx in _hit_points:
		var point := _bone_world(idx)
		segments.append([point, point])
	return segments


func get_character_position() -> Vector3:
	return _character.global_position


func is_tracking() -> bool:
	return _is_tracking()


func is_arms_up() -> bool:
	return _is_tracking() and _all_visible([NOSE, L_WRIST, R_WRIST]) \
		and _p(L_WRIST).y > _p(NOSE).y and _p(R_WRIST).y > _p(NOSE).y


## True when the player's own `side` ("left" or "right") hand is raised above their head.
func is_hand_raised(side: String) -> bool:
	var wrist := L_WRIST if side == "left" else R_WRIST
	return _is_tracking() and _all_visible([NOSE, wrist]) and _p(wrist).y > _p(NOSE).y


## World position of the joint of the rig bone for a limb (e.g. "r_hand", "r_lower_arm"), or null.
func get_limb_joint(limb: String):
	if _skeleton == null:
		return null
	for bone_name in _rig["limbs"]:
		if _rig["limbs"][bone_name][1] == limb and _bones.has(bone_name):
			return _bone_world(_bones[bone_name])
	return null


func _bone_world(idx: int) -> Vector3:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(idx).origin


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _process(delta: float) -> void:
	_receive_packets()
	if _skeleton == null:
		return
	var tracking := _is_tracking()
	_apply(_compute_targets() if tracking else {}, delta)
	if tracking and follow_sideways and _all_visible([L_SHOULDER, R_SHOULDER]):
		# Follow the hips; fall back to the shoulders when the hips are out of view (e.g. at a desk).
		var pair := [L_HIP, R_HIP] if _all_visible([L_HIP, R_HIP]) else [L_SHOULDER, R_SHOULDER]
		var body_x: float = (_image[pair[0]][0] + _image[pair[1]][0]) / 2.0
		var target_x := clampf((body_x - 0.5) * sideways_range, -max_sideways, max_sideways)
		_character.position.x = lerpf(_character.position.x, target_x, 1.0 - exp(-smoothing * delta))
	if _camera:
		_camera.position.x = lerpf(_camera.position.x, camera_offset_x + _character.position.x * camera_follow, 1.0 - exp(-4.0 * delta))
	if tracking:
		_status.text = "Tracking"
	elif _is_connected():
		_status.text = "Tracker connected - no person in view.\nStep back so your head, shoulders and hips are in frame."
	else:
		_status.text = "Waiting for tracker on UDP %d...\nRun: uv run tracker/tracker.py" % PORT
	_status.modulate = Color("#5be08a") if tracking else Color("#e0b35b")


func _receive_packets() -> void:
	while _udp.get_available_packet_count() > 0:
		var data = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
		if data is Dictionary and data.has("wlm") and data.has("lm"):
			_world = data["wlm"]
			_image = data["lm"]
			_last_packet_time = Time.get_ticks_msec() / 1000.0


func _is_connected() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _last_packet_time < STALE_AFTER


func _is_tracking() -> bool:
	return _world.size() >= 33 and _is_connected()


func _visible(index: int) -> bool:
	return _world[index][3] >= MIN_VISIBILITY


func _all_visible(indices: Array) -> bool:
	return indices.all(_visible)


## Landmark in character space: MediaPipe world is y-down with -z towards the camera.
func _p(index: int) -> Vector3:
	return Vector3(_world[index][0], -_world[index][1], -_world[index][2])


func _mid(a: int, b: int) -> Vector3:
	return (_p(a) + _p(b)) / 2.0


## Desired global (skeleton-space) rotation for each tracked bone index.
func _compute_targets() -> Dictionary:
	var targets := {}
	if not _all_visible([L_SHOULDER, R_SHOULDER]):
		return targets

	var shoulders_across := _p(L_SHOULDER) - _p(R_SHOULDER)
	var hips: Quaternion
	var chest: Quaternion
	if _all_visible([L_HIP, R_HIP]):
		var up := _mid(L_SHOULDER, R_SHOULDER) - _mid(L_HIP, R_HIP)
		hips = _frame(_p(L_HIP) - _p(R_HIP), up)
		chest = _frame(shoulders_across, up)
	else:
		# Hips out of view: keep the body upright and turn it with the shoulders.
		chest = _frame(shoulders_across, Vector3.UP)
		hips = _frame(Vector3(shoulders_across.x, 0.0, shoulders_across.z), Vector3.UP)
	for bone_name in _rig["torso"]:
		_set_frame(targets, bone_name, hips.slerp(chest, _rig["torso"][bone_name]))

	if _all_visible([L_EAR, R_EAR, NOSE]):
		var across := _p(L_EAR) - _p(R_EAR)
		var forward := _p(NOSE) - _mid(L_EAR, R_EAR)
		var head := _frame(across, forward.cross(across)) * Quaternion(Vector3.RIGHT, HEAD_PITCH_OFFSET)
		_set_frame(targets, _rig["neck"], chest.slerp(head, 0.5))
		_set_frame(targets, _rig["head"], head)

	for bone_name in _rig["limbs"]:
		var landmarks: Array = LIMB_LANDMARKS[_rig["limbs"][bone_name][1]]
		_aim(targets, bone_name, landmarks[0], landmarks[1])
	return targets


## Orientation whose +X runs along `across` (right-to-left side) and whose +Y leans towards `up`.
func _frame(across: Vector3, up: Vector3) -> Quaternion:
	var x := across.normalized()
	var z := x.cross(up).normalized()
	var y := z.cross(x)
	return Basis(x, y, z).get_rotation_quaternion()


func _set_frame(targets: Dictionary, bone_name: String, frame: Quaternion) -> void:
	if not _bones.has(bone_name):
		return
	var idx: int = _bones[bone_name]
	targets[idx] = _to_skeleton * frame * _to_skeleton.inverse() * _rest_global_rot[idx]


## Swing a bone so its rest direction points from landmark `from` towards the average of `to`.
## Skipped when a landmark is out of view; the bone then keeps its rest pose relative to its parent.
func _aim(targets: Dictionary, bone_name: String, from: int, to: Array) -> void:
	if not _bones.has(bone_name) or not _rest_dir.has(_bones[bone_name]):
		return
	if not _visible(from) or not _all_visible(to):
		return
	var target := Vector3.ZERO
	for index in to:
		target += _p(index)
	var direction := target / to.size() - _p(from)
	if direction.length_squared() < 0.000001:
		return
	var idx: int = _bones[bone_name]
	direction = _to_skeleton * direction.normalized()
	targets[idx] = Mannequin._arc(_rest_dir[idx], direction) * _rest_global_rot[idx]


## Turn desired global rotations into smoothed local bone poses (parents come before children).
func _apply(targets: Dictionary, delta: float) -> void:
	var weight := 1.0 - exp(-smoothing * delta)
	var global_rot := {}
	for idx in _skeleton.get_bone_count():
		var parent := _skeleton.get_bone_parent(idx)
		var parent_rot: Quaternion = global_rot[parent] if parent >= 0 else Quaternion.IDENTITY
		var local: Quaternion
		if targets.has(idx):
			local = parent_rot.inverse() * targets[idx]
		else:
			local = _skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
		var smoothed := _skeleton.get_bone_pose_rotation(idx).slerp(local.normalized(), weight)
		_skeleton.set_bone_pose_rotation(idx, smoothed)
		global_rot[idx] = parent_rot * smoothed
