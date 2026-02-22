## Puck — minimal physics script (main.gd handles bounds clamping).
extends RigidBody3D

func _physics_process(_delta: float) -> void:
	# Keep Y locked (belt-and-suspenders)
	position.y = 0.015
	linear_velocity.y = 0.0
