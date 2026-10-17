@tool
class_name PromoCue
extends AudioStreamPlayer
## A sound placed on the trailer timeline. Stream and Volume Db are the usual
## AudioStreamPlayer settings; tick Playing to listen to it in the editor.

## When it starts, in seconds from the start of the trailer.
@export var at := 0.0
## Which shot that is, and how far into it.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var starts_during := "":
	get:
		var director := owner as PromoDirector
		return director.describe_time(at) if director else ""
## Where to start inside the sound file.
@export var from := 0.0
## How long it plays (seconds).
@export var length := 1.0
@export var fade_in := 0.0
@export var fade_out := 0.0
