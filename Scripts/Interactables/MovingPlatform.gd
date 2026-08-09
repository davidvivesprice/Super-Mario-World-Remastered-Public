extends Node2D

@export_enum("Left", "Up") var direction := "Left"

@onready var animations: AnimationPlayer = $Animations

func _ready() -> void:
	add_to_group("slowmo_world")   # slow-mo powerup target
	animations.play(direction)
