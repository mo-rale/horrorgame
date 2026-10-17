@tool
class_name PromoShot
extends Node3D
## One shot of the promo trailer. Shots play in the order they sit under
## "Shots" in tools/promo/promo_trailer.tscn; the node name is the shot's label.
##
## Select a shot to preview it: its game scene loads into the 3D view and its
## titles show in the 2D view. The PromoKey cameras under it are the camera
## keyframes; the PromoForemanKey markers place the foreman over time.

enum Kind {
	CARD,   ## Black screen with text.
	GATE,   ## The stormy factory gate (scenes/main_menu_scenery.tscn).
	LEVEL,  ## Inside the plant (scenes/main.tscn), seen through the player's camera.
}
enum TextStyle {
	NONE,
	CENTER,       ## Centred card text (BBCode allowed, e.g. [color=#c8161a]red[/color]).
	LOWER_THIRD,  ## Headline + subline bottom-left with a red bar.
	LOW_CENTER,   ## Big red line near the bottom.
	TITLE,        ## The game title block (edit its labels in the scene).
	END,          ## The closing card (edit its labels in the scene).
}

@export var kind: Kind = Kind.CARD
@export var duration := 3.0
## When this shot starts on the whole trailer timeline.
@export_custom(PROPERTY_HINT_NONE, "suffix:s", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var starts_at := 0.0:
	get:
		var t := 0.0
		if get_parent():
			for sibling in get_parent().get_children():
				if sibling == self:
					break
				if sibling is PromoShot:
					t += sibling.duration
		return t
## Fade from / to black at the start and end of the shot (seconds, 0 = cut).
@export var fade_in := 0.0
@export var fade_out := 0.0

@export_group("Text")
@export var text_style: TextStyle = TextStyle.NONE
@export_multiline var text := ""
@export_multiline var subtext := ""
## When the text starts fading in, in seconds from the start of the shot.
@export var text_in := 0.15
## When the text starts fading out. Negative = 0.7 s before the shot ends.
@export var text_out := -1.0

@export_group("Camera")
## Amount of hand-held wobble (0 = locked off).
@export_range(0.0, 4.0, 0.1) var handheld := 0.0

@export_group("Level")
@export var flashlight := true
@export var flashlight_energy := 1.82
## Show the flashlight model in the player's hand.
@export var show_hand := false
## Time windows (x = start, y = end, seconds) where the flashlight cuts out.
@export var flicker := PackedVector2Array()
## Brightens the dark level a little for the trailer (1 = as in game).
@export var brightness := 1.25

@export_group("Foreman")
@export var show_foreman := false
## Turn the foreman to face the camera; otherwise he faces his direction of travel.
@export var foreman_faces_camera := true


## The camera keyframes, in time order.
func get_keys() -> Array[PromoKey]:
	var keys: Array[PromoKey] = []
	for child in get_children():
		if child is PromoKey:
			keys.append(child)
	keys.sort_custom(func(a: PromoKey, b: PromoKey) -> bool: return a.time < b.time)
	return keys


## The foreman's path markers, in time order.
func get_foreman_keys() -> Array[PromoForemanKey]:
	var marks: Array[PromoForemanKey] = []
	for child in get_children():
		if child is PromoForemanKey:
			marks.append(child)
	marks.sort_custom(func(a: PromoForemanKey, b: PromoForemanKey) -> bool: return a.time < b.time)
	return marks
