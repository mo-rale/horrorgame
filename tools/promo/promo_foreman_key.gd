@tool
class_name PromoForemanKey
extends Marker3D
## Where the foreman is at `time` in the PromoShot this sits under. He walks in
## a straight line from marker to marker. The marker is his body's centre: his
## feet are 0.95 m below it.

## Seconds from the start of the shot.
@export var time := 0.0
