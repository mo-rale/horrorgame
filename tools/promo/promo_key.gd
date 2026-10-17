@tool
class_name PromoKey
extends Camera3D
## A camera keyframe of the PromoShot it sits under. At `time` the trailer
## camera is exactly here, with this rotation and field of view; in between
## keys it glides from one to the next.
##
## Select it and tick "Preview" at the top of the 3D view to look through it.
## To set it, fly the editor camera to the view you want, select the key and
## use Perspective menu > Align Transform with View (Ctrl+Alt+M).

enum Easing { SMOOTH, LINEAR, EASE_IN, EASE_OUT }

## Seconds from the start of the shot.
@export var time := 0.0
## How the camera eases into this keyframe from the previous one.
@export var easing: Easing = Easing.SMOOTH
## How far ahead the subject is. When this key and its neighbour both have one,
## the camera keeps aiming at a point that glides from one key's subject to the
## other's, so a move around a subject stays locked on it. 0 = the rotation just
## turns smoothly from one key to the next (and keeps any roll).
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:m") var look_distance := 0.0
## When this keyframe happens on the whole trailer timeline.
@export_custom(PROPERTY_HINT_NONE, "suffix:s", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var trailer_time := 0.0:
	get:
		var shot := get_parent() as PromoShot
		return (shot.starts_at if shot else 0.0) + time


## The point the camera looks at, `look_distance` ahead.
func get_look_point() -> Vector3:
	return global_position - global_basis.z.normalized() * look_distance
