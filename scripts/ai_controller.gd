## AI Controller — computer opponent paddle (AnimatableBody3D).
## Uses prediction and reaction-time simulation for natural behaviour.
extends AnimatableBody3D

# ── Properties set from main.gd ───────────────────────────────
var puck_node  : RigidBody3D = null
var difficulty : float = 0.7          # 0.0 (easy) → 1.0 (impossible)
var bounds_min : Vector3 = Vector3(-1, 0, -2)
var bounds_max : Vector3 = Vector3( 1, 0, -0.15)

# ── Tuning ─────────────────────────────────────────────────────
const BASE_SPEED     : float = 2.8
const MAX_SPEED      : float = 5.5
const REACTION_TIME  : float = 0.18   # seconds of delay (scaled by difficulty)
const DEFEND_Z_RATIO : float = 0.75   # how far back paddle sits when idle
const PADDLE_Y       : float = 0.03

# ── Internal state ─────────────────────────────────────────────
var _target_pos      : Vector3
var _reaction_timer  : float = 0.0
var _last_puck_pos   : Vector3
var _predicted_x     : float = 0.0
var _home_pos        : Vector3
var _initialized     : bool = false

func _ready() -> void:
	_initialized = false


func _compute_home() -> void:
	_home_pos   = Vector3(0, PADDLE_Y, bounds_min.z + (bounds_max.z - bounds_min.z) * 0.25)
	_target_pos = _home_pos
	_initialized = true


func _physics_process(delta: float) -> void:
	if not _initialized:
		_compute_home()
	if GameManager.game_state != GameManager.GameState.PLAYING:
		return
	if puck_node == null:
		return

	var puck_pos := puck_node.position
	var puck_vel := puck_node.linear_velocity

	# Update reaction timer
	_reaction_timer -= delta

	# ── Decision logic ─────────────────────────────────────────
	var puck_coming_toward_us := puck_vel.z < -0.3  # puck moving toward -Z (our side)
	var puck_in_our_half      := puck_pos.z < 0.2

	if puck_coming_toward_us and puck_in_our_half:
		# ATTACK / INTERCEPT mode
		if _reaction_timer <= 0:
			_reaction_timer = REACTION_TIME * (1.0 - difficulty * 0.7)
			_predicted_x    = _predict_puck_x(puck_pos, puck_vel)

		# Move to intercept
		_target_pos.x = _predicted_x
		# Advance toward puck Z but stay within bounds
		var advance_z := puck_pos.z + 0.15
		_target_pos.z = clampf(advance_z, bounds_min.z, bounds_max.z)

	elif puck_in_our_half and not puck_coming_toward_us:
		# Puck in our half but moving away — follow loosely
		_target_pos.x = lerpf(_target_pos.x, puck_pos.x, 0.3 * difficulty)
		_target_pos.z = lerpf(_target_pos.z, _home_pos.z, 2.0 * delta)

	else:
		# Puck in opponent's half — drift back to home
		_target_pos.x = lerpf(_target_pos.x, 0.0, 2.5 * delta)
		_target_pos.z = lerpf(_target_pos.z, _home_pos.z, 3.0 * delta)

	# ── Add imperfection ───────────────────────────────────────
	var error := (1.0 - difficulty) * 0.15
	_target_pos.x += randf_range(-error, error)

	# ── Clamp & move ──────────────────────────────────────────
	_target_pos.x = clampf(_target_pos.x, bounds_min.x, bounds_max.x)
	_target_pos.z = clampf(_target_pos.z, bounds_min.z, bounds_max.z)
	_target_pos.y = PADDLE_Y

	var speed := lerpf(BASE_SPEED, MAX_SPEED, difficulty)
	var max_move := speed * delta
	var diff     := _target_pos - position
	diff.y = 0
	if diff.length() > max_move:
		diff = diff.normalized() * max_move

	var new_pos := position + diff
	new_pos.y   = PADDLE_Y
	position    = new_pos


# ── Predict where puck will arrive at our defensive Z line ─────
func _predict_puck_x(puck_pos: Vector3, puck_vel: Vector3) -> float:
	if abs(puck_vel.z) < 0.1:
		return puck_pos.x

	# Time for puck to reach our Z position
	var target_z := (bounds_min.z + bounds_max.z) * 0.5
	var t := (target_z - puck_pos.z) / puck_vel.z
	if t < 0:
		t = 0

	# Simple linear prediction (ignoring wall bounces for now)
	var pred_x := puck_pos.x + puck_vel.x * t

	# Simulate wall bounces for better prediction
	var wall_min := bounds_min.x - 0.1
	var wall_max := bounds_max.x + 0.1
	var w := wall_max - wall_min
	if w > 0:
		pred_x -= wall_min
		var bounces := int(abs(pred_x) / w)
		pred_x = fmod(abs(pred_x), w)
		if bounces % 2 == 1:
			pred_x = w - pred_x
		pred_x += wall_min

	return clampf(pred_x, bounds_min.x, bounds_max.x)
