@tool
class_name Mannequin
extends Skeleton3D
## A simple rigged humanoid: the bones are built in code, and a capsule
## "body part" hangs off each bone through a BoneAttachment3D.
## Rest pose is a T-pose facing +Z (towards the camera); the character's left is +X.

const SKIN := Color("#e0ac85")
const SHIRT := Color("#3d7bd9")
const PANTS := Color("#2b3140")
const SHOES := Color("#1a1a1a")

# [name, parent, offset from parent joint, tip (bone direction & length), radius, color]
const BONES := [
	["Hips", "", Vector3(0, 0.97, 0), Vector3(0, 0.1, 0), 0.13, PANTS],
	["Spine", "Hips", Vector3(0, 0.1, 0), Vector3(0, 0.2, 0), 0.09, SHIRT],
	["Chest", "Spine", Vector3(0, 0.2, 0), Vector3(0, 0.2, 0), 0.15, SHIRT],
	["Neck", "Chest", Vector3(0, 0.2, 0), Vector3(0, 0.1, 0), 0.05, SKIN],
	["Head", "Neck", Vector3(0, 0.1, 0), Vector3(0, 0.22, 0), 0.11, SKIN],
	["LeftUpperArm", "Chest", Vector3(0.19, 0.16, 0), Vector3(0.28, 0, 0), 0.05, SHIRT],
	["LeftLowerArm", "LeftUpperArm", Vector3(0.28, 0, 0), Vector3(0.25, 0, 0), 0.04, SKIN],
	["LeftHand", "LeftLowerArm", Vector3(0.25, 0, 0), Vector3(0.12, 0, 0), 0.045, SKIN],
	["RightUpperArm", "Chest", Vector3(-0.19, 0.16, 0), Vector3(-0.28, 0, 0), 0.05, SHIRT],
	["RightLowerArm", "RightUpperArm", Vector3(-0.28, 0, 0), Vector3(-0.25, 0, 0), 0.04, SKIN],
	["RightHand", "RightLowerArm", Vector3(-0.25, 0, 0), Vector3(-0.12, 0, 0), 0.045, SKIN],
	["LeftUpperLeg", "Hips", Vector3(0.1, -0.05, 0), Vector3(0, -0.43, 0), 0.07, PANTS],
	["LeftLowerLeg", "LeftUpperLeg", Vector3(0, -0.43, 0), Vector3(0, -0.42, 0), 0.055, PANTS],
	["LeftFoot", "LeftLowerLeg", Vector3(0, -0.42, 0), Vector3(0, -0.03, 0.16), 0.045, SHOES],
	["RightUpperLeg", "Hips", Vector3(-0.1, -0.05, 0), Vector3(0, -0.43, 0), 0.07, PANTS],
	["RightLowerLeg", "RightUpperLeg", Vector3(0, -0.43, 0), Vector3(0, -0.42, 0), 0.055, PANTS],
	["RightFoot", "RightLowerLeg", Vector3(0, -0.42, 0), Vector3(0, -0.03, 0.16), 0.045, SHOES],
]

var _tips := {}


func _ready() -> void:
	_build()


## Direction and length of a bone in its own rest space (from its joint to its tip).
func get_bone_tip(bone_name: String) -> Vector3:
	return _tips.get(bone_name, Vector3.UP * 0.1)


func _build() -> void:
	for child in get_children():
		if child is BoneAttachment3D:
			remove_child(child)
			child.free()
	clear_bones()
	for spec in BONES:
		var idx := add_bone(spec[0])
		if spec[1] != "":
			set_bone_parent(idx, find_bone(spec[1]))
		set_bone_rest(idx, Transform3D(Basis.IDENTITY, spec[2]))
		_tips[spec[0]] = spec[3]
	reset_bone_poses()
	for spec in BONES:
		_add_part(spec[0], spec[3], spec[4], spec[5])


func _add_part(bone_name: String, tip: Vector3, radius: float, color: Color) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.name = bone_name + "Part"
	attachment.bone_name = bone_name
	add_child(attachment)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7

	var part := MeshInstance3D.new()
	part.material_override = material
	match bone_name:
		"Head":
			var sphere := SphereMesh.new()
			sphere.radius = radius
			sphere.height = radius * 2.3
			part.mesh = sphere
			_add_face(part, radius)
		"Chest":
			var box := BoxMesh.new()
			box.size = Vector3(0.36, 0.26, 0.2)
			part.mesh = box
		"Hips":
			var box := BoxMesh.new()
			box.size = Vector3(0.3, 0.16, 0.18)
			part.mesh = box
		_:
			var capsule := CapsuleMesh.new()
			capsule.radius = radius
			capsule.height = tip.length() + radius * 2.0
			part.mesh = capsule
			part.basis = Basis(_arc(Vector3.UP, tip.normalized()))
	part.position = tip * 0.5
	attachment.add_child(part)


func _add_face(head: MeshInstance3D, radius: float) -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#222222")
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.018
		sphere.height = 0.036
		eye.mesh = sphere
		eye.material_override = dark
		eye.position = Vector3(side * 0.04, 0.02, radius * 0.9)
		head.add_child(eye)
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.025, 0.04, 0.04)
	nose.mesh = nose_mesh
	nose.material_override = head.material_override
	nose.position = Vector3(0, -0.02, radius)
	head.add_child(nose)


## Shortest rotation taking unit vector `from` onto unit vector `to` (safe for opposite vectors).
static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	if from.dot(to) < -0.9999:
		var axis := from.cross(Vector3.RIGHT)
		if axis.length_squared() < 0.000001:
			axis = from.cross(Vector3.FORWARD)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(from, to)
