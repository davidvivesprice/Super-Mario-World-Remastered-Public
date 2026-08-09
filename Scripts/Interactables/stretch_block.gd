extends AnimatableBody2D

@export_enum("Horizontal", "Vertical", "Both") var direction := "Horizontal"
@onready var animations: AnimationPlayer = $Animations

func _ready() -> void:
	add_to_group("slowmo_world")   # slow-mo powerup target
	animations.play(direction)
	animations.seek(2.5 if direction == "Horizontal" else 0)
