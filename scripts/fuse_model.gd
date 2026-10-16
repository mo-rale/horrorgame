extends RefCounted
# Shared model for a cartridge fuse: glass tube, brass end caps, a glowing
# element and a colour-coded band. The model stands along local Y and is about
# 0.56 m long at length_scale 1.

static func build(color: Color, length_scale := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"

	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.75, 0.88, 1.0, 0.28)
	glass.roughness = 0.08
	glass.emission_enabled = true
	glass.emission = color
	glass.emission_energy_multiplier = 0.25

	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.86, 0.66, 0.3)
	brass.metallic = 0.25
	brass.roughness = 0.45
	brass.emission_enabled = true
	brass.emission = Color(0.5, 0.35, 0.1)
	brass.emission_energy_multiplier = 0.2

	var glow := StandardMaterial3D.new()
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 2.2

	var band := StandardMaterial3D.new()
	band.albedo_color = color
	band.emission_enabled = true
	band.emission = color
	band.emission_energy_multiplier = 0.7
	band.roughness = 0.5

	var body_length := 0.36 * length_scale
	var cap_length := 0.1 * length_scale
	var cap_offset := (body_length + cap_length) * 0.5

	_add_cylinder(root, "Glass", 0.07, body_length, Vector3.ZERO, glass)
	_add_cylinder(root, "CapTop", 0.078, cap_length, Vector3(0, cap_offset, 0), brass)
	_add_cylinder(root, "CapBottom", 0.078, cap_length, Vector3(0, -cap_offset, 0), brass)
	_add_cylinder(root, "Filament", 0.009, body_length * 0.95, Vector3.ZERO, glow)
	_add_cylinder(root, "BandTop", 0.074, 0.05 * length_scale, Vector3(0, body_length * 0.3, 0), band)
	_add_cylinder(root, "BandBottom", 0.074, 0.05 * length_scale, Vector3(0, -body_length * 0.3, 0), band)
	return root


## Recolours a built or baked fuse model. Every call gets its own materials, so
## fuses sharing one scene can still be red, blue and yellow.
static func tint(model: Node3D, color: Color) -> void:
	for node_name in ["Glass", "Filament", "BandTop", "BandBottom"]:
		var part := model.get_node_or_null(node_name) as MeshInstance3D
		if part == null:
			continue
		var material := part.material_override.duplicate() as StandardMaterial3D
		material.emission = color
		if node_name != "Glass":
			material.albedo_color = color
		part.material_override = material


static func length(length_scale := 1.0) -> float:
	return (0.36 + 0.1 * 2.0) * length_scale


static func _add_cylinder(parent: Node3D, part_name: String, radius: float, height: float, position: Vector3, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
