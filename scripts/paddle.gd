## Paddle — human-controlled mallet (AnimatableBody3D).
## Player 1 uses mouse; Player 2 uses arrow keys.
extends AnimatableBody3D

# ── Properties set from main.gd before adding to tree ──────────
var player_id : int        = 1
var cam       : Camera3D   = null
var bounds_min: Vector3    = Vector3(-1, 0, -2)
var bounds_max: Vector3    = Vector3( 1, 0,  2)

# ── Tuning ─────────────────────────────────────────────────────
const LERP_SPEED    : float = 18.0   # mouse-follow responsiveness
const KEY_SPEED     : float = 3.2    # keyboard movement speed
const PADDLE_Y      : float = 0.03   # half paddle height

var _target_pos : Vector3

func _ready() -> void:
	_target_pos = position


func _physics_process(delta: float) -> void:
	if GameManager.game_state != GameManager.GameState.PLAYING:
		return

	if player_id == 1:
		_handle_mouse_input()
	else:
		_handle_keyboard_input(delta)

	# Clamp target to allowed bounds
	_target_pos.x = clampf(_target_pos.x, bounds_min.x, bounds_max.x)
	_target_pos.z = clampf(_target_pos.z, bounds_min.z, bounds_max.z)
	_target_pos.y = PADDLE_Y

	# Move toward target — use velocity so physics engine detects collisions
	var desired := _target_pos - position
	desired.y = 0
	var max_dist := LERP_SPEED * delta
	if desired.length() > max_dist:
		desired = desired.normalized() * max_dist
	position += desired
	position.y = PADDLE_Y


# ── Mouse input (Player 1) ────────────────────────────────────
func _handle_mouse_input() -> void:
	if cam == null:
		return
	var vp := get_viewport()
	if vp == null:
		return

	var mouse_pos := vp.get_mouse_position()
	var ray_origin := cam.project_ray_origin(mouse_pos)
	var ray_dir    := cam.project_ray_normal(mouse_pos)

	# Intersect with the Y = PADDLE_Y plane
	if abs(ray_dir.y) < 0.001:
		return
	var t := (PADDLE_Y - ray_origin.y) / ray_dir.y
	if t < 0:
		return
	var hit := ray_origin + ray_dir * t
	_target_pos = hit


# ── Arrow-key input (Player 2, local 2-player) ────────────────
func _handle_keyboard_input(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_UP):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		dir.z += 1.0
	if Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0

	if dir.length_squared() > 0:
		dir = dir.normalized()
	_target_pos += dir * KEY_SPEED * delta
