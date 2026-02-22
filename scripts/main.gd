## Main Scene — builds the entire 3D air hockey world and manages game flow.
extends Node3D

# ╔══════════════════════════════════════════════════════════════╗
# ║  CONSTANTS                                                    ║
# ╚══════════════════════════════════════════════════════════════╝

const TABLE_WIDTH      : float = 2.4
const TABLE_LENGTH     : float = 3.8
const SURFACE_THICK    : float = 0.06
const RAIL_HEIGHT      : float = 0.10
const RAIL_THICK       : float = 0.08
const GOAL_WIDTH       : float = 0.72

const PUCK_RADIUS      : float = 0.085
const PUCK_HEIGHT      : float = 0.03
const PADDLE_RADIUS    : float = 0.135
const PADDLE_HEIGHT    : float = 0.06

const PUCK_MAX_SPEED   : float = 14.0
const PUCK_START_SPEED : float = 5.0
const RESET_DELAY      : float = 1.0
const PADDLE_MOVE_SPEED: float = 14.0
const AI_REACTION_TIME : float = 0.10

# ── Derived ──
var _half_w  : float
var _half_l  : float
var _inner_w : float
var _inner_l : float

# ╔══════════════════════════════════════════════════════════════╗
# ║  NODE REFERENCES                                               ║
# ╚══════════════════════════════════════════════════════════════╝

var camera          : Camera3D
var puck            : RigidBody3D

# Paddles: Node3D for visuals, StaticBody3D for physics collider
var paddle1         : Node3D
var paddle2         : Node3D
var paddle1_col     : StaticBody3D
var paddle2_col     : StaticBody3D

# UI
var hud_layer       : CanvasLayer
var score_label     : Label
var menu_panel      : PanelContainer
var game_over_panel : PanelContainer
var countdown_label : Label
var winner_label    : Label

# Materials
var mat_surface   : StandardMaterial3D
var mat_base      : StandardMaterial3D
var mat_rail      : StandardMaterial3D
var mat_puck      : StandardMaterial3D
var mat_paddle_r  : StandardMaterial3D
var mat_paddle_b  : StandardMaterial3D
var mat_marking   : StandardMaterial3D
var mat_goal_slot : StandardMaterial3D
var mat_goal_glow : StandardMaterial3D

# Sound
var sfx_hit       : AudioStreamPlayer
var sfx_wall      : AudioStreamPlayer
var sfx_goal      : AudioStreamPlayer
var sfx_countdown : AudioStreamPlayer
var sfx_game_over : AudioStreamPlayer
var sfx_click     : AudioStreamPlayer
var sfx_cheer     : AudioStreamPlayer
var sfx_boo       : AudioStreamPlayer
var sfx_perfect   : AudioStreamPlayer

# Particles
var puck_trail    : GPUParticles3D
var goal_particles_p1 : GPUParticles3D
var goal_particles_p2 : GPUParticles3D

# ── State ──
var _reset_timer       : float = 0.0
var _last_scorer       : int   = -1

var _p1_target         : Vector3
var _p1_bounds_min     : Vector3
var _p1_bounds_max     : Vector3
var _p2_target         : Vector3
var _p2_bounds_min     : Vector3
var _p2_bounds_max     : Vector3

var _ai_reaction_timer : float = 0.0
var _ai_predicted_x    : float = 0.0
var _ai_home_pos       : Vector3

var _paddle1_prev_pos  : Vector3
var _paddle2_prev_pos  : Vector3

# Platform detection
var _is_web : bool = false


# ╔══════════════════════════════════════════════════════════════╗
# ║  LIFECYCLE                                                     ║
# ╚══════════════════════════════════════════════════════════════╝

func _ready() -> void:
	_is_web = OS.get_name() == "Web"
	_half_w  = TABLE_WIDTH  / 2.0
	_half_l  = TABLE_LENGTH / 2.0
	_inner_w = _half_w - RAIL_THICK
	_inner_l = _half_l - RAIL_THICK

	_create_materials()
	_setup_environment()
	_setup_camera()
	_setup_lighting()
	_build_table()
	_build_markings()
	_build_walls()
	_build_goal_areas()
	_build_puck()
	_build_paddles()
	_build_ui()
	_build_sounds()
	_build_goal_particles()

	GameManager.score_changed.connect(_on_score_changed)
	GameManager.game_state_changed.connect(_on_game_state_changed)
	GameManager.goal_scored.connect(_on_goal_scored)

	_show_menu()


func _process(_delta: float) -> void:
	# Only gather mouse input here (for responsiveness)
	if GameManager.game_state == GameManager.GameState.PLAYING:
		_update_p1_mouse()


func _physics_process(delta: float) -> void:
	# All game logic on fixed timestep to avoid jitter
	if GameManager.game_state == GameManager.GameState.PLAYING:
		# Store previous positions before moving (for velocity calculation)
		_paddle1_prev_pos = paddle1.global_position
		_paddle2_prev_pos = paddle2.global_position

		_move_paddle(paddle1, paddle1_col, _p1_target, _p1_bounds_min, _p1_bounds_max, delta)

		if GameManager.game_mode == GameManager.GameMode.VS_AI:
			_update_ai(delta)
		else:
			_update_p2_keyboard(delta)
		_move_paddle(paddle2, paddle2_col, _p2_target, _p2_bounds_min, _p2_bounds_max, delta)

		# Manual paddle-puck collision (teleported StaticBody3D can't push reliably)
		_handle_paddle_hit(paddle1.global_position, _paddle1_prev_pos, delta)
		_handle_paddle_hit(paddle2.global_position, _paddle2_prev_pos, delta)

		_clamp_puck()

	# ── Goal countdown ──
	if GameManager.game_state == GameManager.GameState.GOAL_SCORED:
		var prev_sec := ceili(_reset_timer)
		_reset_timer -= delta
		if _reset_timer > 0:
			var cur_sec := ceili(_reset_timer)
			countdown_label.text = str(cur_sec)
			if cur_sec != prev_sec:
				_play_sfx(sfx_countdown)
		else:
			countdown_label.visible = false
			_reset_puck_for_play()
			GameManager.resume_play()


# ╔══════════════════════════════════════════════════════════════╗
# ║  PADDLE MOVEMENT                                               ║
# ╚══════════════════════════════════════════════════════════════╝

func _move_paddle(vis: Node3D, col: StaticBody3D, target: Vector3,
		bmin: Vector3, bmax: Vector3, delta: float) -> void:
	var clamped := Vector3(
		clampf(target.x, bmin.x, bmax.x),
		PADDLE_HEIGHT / 2.0,
		clampf(target.z, bmin.z, bmax.z)
	)
	var old_pos := vis.global_position
	var diff := clamped - old_pos
	diff.y = 0.0
	var max_dist := PADDLE_MOVE_SPEED * delta
	if diff.length() > max_dist:
		diff = diff.normalized() * max_dist
	var new_pos := old_pos + diff
	new_pos.y = PADDLE_HEIGHT / 2.0
	vis.global_position = new_pos
	col.global_position = new_pos
	if delta > 0.0:
		col.constant_linear_velocity = diff / delta
	else:
		col.constant_linear_velocity = Vector3.ZERO


func _update_p1_mouse() -> void:
	if camera == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var mouse_pos := vp.get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir    := camera.project_ray_normal(mouse_pos)
	if abs(ray_dir.y) < 0.001:
		return
	var t := (0.0 - ray_origin.y) / ray_dir.y
	if t < 0.0:
		return
	_p1_target = ray_origin + ray_dir * t


func _update_p2_keyboard(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_UP):    dir.z -= 1.0
	if Input.is_key_pressed(KEY_DOWN):  dir.z += 1.0
	if Input.is_key_pressed(KEY_LEFT):  dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT): dir.x += 1.0
	if dir.length_squared() > 0:
		dir = dir.normalized()
	_p2_target += dir * 3.5 * delta


func _update_ai(delta: float) -> void:
	var puck_pos := puck.position
	var puck_vel := puck.linear_velocity
	var difficulty := GameManager.ai_difficulty
	var speed_mult := 0.6 + difficulty * 0.4   # AI movement responsiveness

	_ai_reaction_timer -= delta

	# AI is Player 2 (negative Z side)
	var puck_approaching := puck_vel.z < -0.5
	var puck_in_ai_half := puck_pos.z < 0.0
	var puck_speed := puck_vel.length()

	# Update prediction periodically
	if _ai_reaction_timer <= 0:
		_ai_reaction_timer = AI_REACTION_TIME
		_ai_predicted_x = _ai_predict_with_bounces(puck_pos, puck_vel)

	if puck_approaching or puck_in_ai_half:
		# === ATTACK / INTERCEPT MODE ===
		# Move directly to predicted intercept X
		var lerp_x := 12.0 * speed_mult
		_p2_target.x = lerpf(_p2_target.x, _ai_predicted_x, lerp_x * delta)

		if puck_in_ai_half:
			# Puck in our half — rush to meet it
			var target_z := clampf(puck_pos.z + 0.15, _p2_bounds_min.z, _p2_bounds_max.z)
			_p2_target.z = lerpf(_p2_target.z, target_z, 14.0 * speed_mult * delta)
		else:
			# Puck approaching from far — hold defensive line
			var def_z := _p2_bounds_min.z + (_p2_bounds_max.z - _p2_bounds_min.z) * 0.4
			_p2_target.z = lerpf(_p2_target.z, def_z, 10.0 * speed_mult * delta)
	else:
		# === DEFENSIVE / ANTICIPATION MODE ===
		# Puck in player's half moving away — but don't just stand still!
		# Track the puck's X to stay aligned, hold near center-back
		var anticipate_x := clampf(puck_pos.x * 0.6, _p2_bounds_min.x, _p2_bounds_max.x)
		_p2_target.x = lerpf(_p2_target.x, anticipate_x, 6.0 * speed_mult * delta)
		# Stay at defensive position, ready to react
		var def_z := _p2_bounds_min.z + (_p2_bounds_max.z - _p2_bounds_min.z) * 0.35
		_p2_target.z = lerpf(_p2_target.z, def_z, 8.0 * speed_mult * delta)

	# Tiny jitter for imperfection at lower difficulties
	var jitter := (1.0 - difficulty) * 0.02
	_p2_target.x += randf_range(-jitter, jitter)


# Predict puck X position at AI's defensive line, simulating wall bounces
func _ai_predict_with_bounces(ppos: Vector3, pvel: Vector3) -> float:
	var puck_speed := pvel.length()
	if puck_speed < 0.3:
		return ppos.x  # Puck barely moving, just align

	var target_z := (_p2_bounds_min.z + _p2_bounds_max.z) * 0.5

	# If puck moving away from AI, predict where it'll come back
	if pvel.z >= 0:
		# Puck going toward player side — it'll bounce back
		# Estimate: go to player wall, reflect, then come to AI
		var wall_z := _inner_l - PUCK_RADIUS
		if pvel.z > 0.1:
			var t_to_wall := (wall_z - ppos.z) / pvel.z
			var x_at_wall := ppos.x + pvel.x * t_to_wall
			# Simulate bounces on X walls during travel to player wall
			x_at_wall = _bounce_x(x_at_wall)
			# After bounce, puck comes back with -vel.z
			var t_back := (wall_z - target_z) / absf(pvel.z)
			var x_final := x_at_wall + pvel.x * t_back  # vel.x unchanged by z-bounce
			return clampf(_bounce_x(x_final), _p2_bounds_min.x, _p2_bounds_max.x)
		else:
			return clampf(ppos.x, _p2_bounds_min.x, _p2_bounds_max.x)

	# Puck moving toward AI — predict arrival
	var t_pred := (target_z - ppos.z) / pvel.z
	if t_pred < 0:
		t_pred = 0.0
	var predicted_x := ppos.x + pvel.x * t_pred
	# Account for wall bounces
	predicted_x = _bounce_x(predicted_x)
	return clampf(predicted_x, _p2_bounds_min.x, _p2_bounds_max.x)


# Simulate X-axis wall bounces (ping-pong within table bounds)
func _bounce_x(x: float) -> float:
	var w := _inner_w - PUCK_RADIUS
	if w <= 0.01:
		return 0.0
	# Fold x into [-w, w] range using modular arithmetic
	var shifted := x + w
	var period := w * 2.0
	var wrapped := fmod(shifted, period)
	if wrapped < 0:
		wrapped += period
	# Now wrapped is in [0, period] — fold back
	if wrapped > w:
		return period - wrapped - w
	else:
		return wrapped - w


func _clamp_puck() -> void:
	var margin := PUCK_RADIUS
	var max_x := _inner_w - margin
	var max_z := _inner_l - margin
	var bounced := false

	# Side walls — full-energy reflection
	if puck.position.x < -max_x:
		puck.position.x = -max_x
		if puck.linear_velocity.x < 0:
			puck.linear_velocity.x = -puck.linear_velocity.x
			bounced = true
	elif puck.position.x > max_x:
		puck.position.x = max_x
		if puck.linear_velocity.x > 0:
			puck.linear_velocity.x = -puck.linear_velocity.x
			bounced = true

	# End walls — only outside goal openings, full reflection
	if abs(puck.position.x) > GOAL_WIDTH / 2.0 - margin:
		if puck.position.z < -max_z:
			puck.position.z = -max_z
			if puck.linear_velocity.z < 0:
				puck.linear_velocity.z = -puck.linear_velocity.z
				bounced = true
		elif puck.position.z > max_z:
			puck.position.z = max_z
			if puck.linear_velocity.z > 0:
				puck.linear_velocity.z = -puck.linear_velocity.z
				bounced = true

	if bounced:
		_play_sfx(sfx_wall)

	puck.position.y = PUCK_HEIGHT / 2.0
	puck.linear_velocity.y = 0.0
	var speed := puck.linear_velocity.length()
	if speed > PUCK_MAX_SPEED:
		puck.linear_velocity = puck.linear_velocity.normalized() * PUCK_MAX_SPEED

	# Update puck trail intensity based on speed
	if puck_trail:
		puck_trail.global_position = puck.global_position
		var amt := clampf(speed / PUCK_MAX_SPEED, 0.0, 1.0)
		puck_trail.amount_ratio = amt
		puck_trail.emitting = speed > 1.5


func _handle_paddle_hit(paddle_pos: Vector3, paddle_prev: Vector3, delta: float) -> void:
	var dx := puck.position.x - paddle_pos.x
	var dz := puck.position.z - paddle_pos.z
	var dist := sqrt(dx * dx + dz * dz)
	var min_dist := PADDLE_RADIUS + PUCK_RADIUS + 0.005

	if dist >= min_dist or dist < 0.001:
		return

	# Push direction: paddle → puck
	var push_x := dx / dist
	var push_z := dz / dist

	# Separate puck from paddle
	puck.position.x = paddle_pos.x + push_x * min_dist
	puck.position.z = paddle_pos.z + push_z * min_dist
	puck.position.y = PUCK_HEIGHT / 2.0

	# Paddle velocity from frame delta
	var paddle_vx := 0.0
	var paddle_vz := 0.0
	if delta > 0.001:
		paddle_vx = (paddle_pos.x - paddle_prev.x) / delta
		paddle_vz = (paddle_pos.z - paddle_prev.z) / delta

	# Relative velocity of puck w.r.t. paddle
	var rel_vx := puck.linear_velocity.x - paddle_vx
	var rel_vz := puck.linear_velocity.z - paddle_vz
	var closing := -(rel_vx * push_x + rel_vz * push_z)

	if closing > 0.0:
		# Impulse-based elastic collision (restitution ≈ 0.9)
		var impulse := (1.0 + 0.9) * closing
		puck.linear_velocity.x += impulse * push_x
		puck.linear_velocity.z += impulse * push_z
		_play_sfx_pitched(sfx_hit, randf_range(0.85, 1.15))
	else:
		# Puck stuck inside paddle — give a minimum push
		var spd := puck.linear_velocity.length()
		if spd < 3.0:
			puck.linear_velocity.x = push_x * 3.0
			puck.linear_velocity.z = push_z * 3.0
			_play_sfx_pitched(sfx_hit, 0.7)
	puck.linear_velocity.y = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if GameManager.game_state == GameManager.GameState.PLAYING:
				GameManager.return_to_menu()
				_show_menu()





# ╔══════════════════════════════════════════════════════════════╗
# ║  MATERIALS                                                     ║
# ╚══════════════════════════════════════════════════════════════╝

func _create_materials() -> void:
	# === TRON NEON STYLE WITH PROCEDURAL TEXTURES ===

	# ── Procedural normal map for playing surface (ice-rink micro-texture) ──
	var surface_noise := FastNoiseLite.new()
	surface_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	surface_noise.frequency = 0.08
	surface_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	surface_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var surface_normal_tex := NoiseTexture2D.new()
	surface_normal_tex.width = 256
	surface_normal_tex.height = 256
	surface_normal_tex.noise = surface_noise
	surface_normal_tex.as_normal_map = true
	surface_normal_tex.bump_strength = 3.0
	surface_normal_tex.seamless = true

	# Near-black playing surface with micro-texture relief
	mat_surface = StandardMaterial3D.new()
	mat_surface.albedo_color = Color(0.01, 0.01, 0.03)
	mat_surface.metallic     = 0.6
	mat_surface.roughness    = 0.08
	mat_surface.emission_enabled = true
	mat_surface.emission         = Color(0.0, 0.06, 0.12)
	mat_surface.emission_energy_multiplier = 0.4
	mat_surface.normal_enabled = true
	mat_surface.normal_texture = surface_normal_tex
	mat_surface.normal_scale = 0.4
	mat_surface.uv1_scale = Vector3(4, 4, 1)

	# Pure black base
	mat_base = StandardMaterial3D.new()
	mat_base.albedo_color = Color(0.02, 0.02, 0.02)
	mat_base.roughness    = 0.9

	# ── Procedural brushed-metal normal for rails ──
	var rail_noise := FastNoiseLite.new()
	rail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	rail_noise.frequency = 0.15
	rail_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	rail_noise.fractal_octaves = 3
	var rail_normal_tex := NoiseTexture2D.new()
	rail_normal_tex.width = 128
	rail_normal_tex.height = 128
	rail_normal_tex.noise = rail_noise
	rail_normal_tex.as_normal_map = true
	rail_normal_tex.bump_strength = 4.0
	rail_normal_tex.seamless = true

	# Neon cyan glowing rails with brushed-metal relief
	mat_rail = StandardMaterial3D.new()
	mat_rail.albedo_color = Color(0.05, 0.15, 0.2)
	mat_rail.metallic     = 0.9
	mat_rail.roughness    = 0.1
	mat_rail.emission_enabled = true
	mat_rail.emission         = Color(0.0, 0.8, 1.0)
	mat_rail.emission_energy_multiplier = 1.8
	mat_rail.normal_enabled = true
	mat_rail.normal_texture = rail_normal_tex
	mat_rail.normal_scale = 0.5
	mat_rail.uv1_scale = Vector3(6, 2, 1)

	# ── Procedural rough texture for puck ──
	var puck_noise := FastNoiseLite.new()
	puck_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	puck_noise.frequency = 0.12
	puck_noise.fractal_octaves = 4
	var puck_normal_tex := NoiseTexture2D.new()
	puck_normal_tex.width = 128
	puck_normal_tex.height = 128
	puck_normal_tex.noise = puck_noise
	puck_normal_tex.as_normal_map = true
	puck_normal_tex.bump_strength = 5.0
	puck_normal_tex.seamless = true

	# Hot orange neon puck with textured surface
	mat_puck = StandardMaterial3D.new()
	mat_puck.albedo_color = Color(1.0, 0.3, 0.0)
	mat_puck.metallic     = 0.4
	mat_puck.roughness    = 0.15
	mat_puck.emission_enabled = true
	mat_puck.emission         = Color(1.0, 0.4, 0.05)
	mat_puck.emission_energy_multiplier = 2.5
	mat_puck.normal_enabled = true
	mat_puck.normal_texture = puck_normal_tex
	mat_puck.normal_scale = 0.6

	# ── Procedural grip texture for paddles ──
	var paddle_noise := FastNoiseLite.new()
	paddle_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	paddle_noise.frequency = 0.2
	paddle_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var paddle_normal_tex := NoiseTexture2D.new()
	paddle_normal_tex.width = 128
	paddle_normal_tex.height = 128
	paddle_normal_tex.noise = paddle_noise
	paddle_normal_tex.as_normal_map = true
	paddle_normal_tex.bump_strength = 3.0
	paddle_normal_tex.seamless = true

	# Neon red paddle — player 1 (with grip texture)
	mat_paddle_r = StandardMaterial3D.new()
	mat_paddle_r.albedo_color = Color(0.15, 0.02, 0.02)
	mat_paddle_r.metallic     = 0.6
	mat_paddle_r.roughness    = 0.15
	mat_paddle_r.emission_enabled = true
	mat_paddle_r.emission         = Color(1.0, 0.1, 0.05)
	mat_paddle_r.emission_energy_multiplier = 2.0
	mat_paddle_r.normal_enabled = true
	mat_paddle_r.normal_texture = paddle_normal_tex
	mat_paddle_r.normal_scale = 0.5

	# Neon cyan paddle — player 2 / AI (with grip texture)
	mat_paddle_b = StandardMaterial3D.new()
	mat_paddle_b.albedo_color = Color(0.02, 0.05, 0.15)
	mat_paddle_b.metallic     = 0.6
	mat_paddle_b.roughness    = 0.15
	mat_paddle_b.emission_enabled = true
	mat_paddle_b.emission         = Color(0.0, 0.7, 1.0)
	mat_paddle_b.emission_energy_multiplier = 2.0
	mat_paddle_b.normal_enabled = true
	mat_paddle_b.normal_texture = paddle_normal_tex
	mat_paddle_b.normal_scale = 0.5

	# Neon cyan markings (bright unshaded lines)
	mat_marking = StandardMaterial3D.new()
	mat_marking.albedo_color  = Color(0.0, 0.9, 1.0, 0.9)
	mat_marking.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_marking.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_marking.emission_enabled = true
	mat_marking.emission = Color(0.0, 0.7, 1.0)
	mat_marking.emission_energy_multiplier = 1.5

	# Dark goal slot openings
	mat_goal_slot = StandardMaterial3D.new()
	mat_goal_slot.albedo_color = Color(0.0, 0.0, 0.0)
	mat_goal_slot.roughness    = 1.0

	# Goal glow material — bright orange neon
	mat_goal_glow = StandardMaterial3D.new()
	mat_goal_glow.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	mat_goal_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_goal_glow.emission_enabled = true
	mat_goal_glow.emission = Color(1.0, 0.4, 0.0)
	mat_goal_glow.emission_energy_multiplier = 3.0


# ╔══════════════════════════════════════════════════════════════╗
# ║  ENVIRONMENT / CAMERA / LIGHTING                               ║
# ╚══════════════════════════════════════════════════════════════╝

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode  = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.03, 0.06, 0.1)
	env.ambient_light_energy = 0.3
	# Glow for neon bloom (reduced on web for performance)
	env.glow_enabled         = true
	if _is_web:
		env.glow_intensity       = 0.8
		env.glow_strength        = 0.6
		env.glow_hdr_threshold   = 1.2
		env.glow_hdr_scale       = 1.0
	else:
		env.glow_intensity       = 1.2
		env.glow_strength        = 1.0
		env.glow_hdr_threshold   = 0.8
		env.glow_hdr_scale       = 2.0
	env.glow_blend_mode      = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled   = true
	env.adjustment_contrast  = 1.15
	env.adjustment_saturation = 1.3
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Set viewport quality at runtime (lighter on web)
	var vp := get_viewport()
	if _is_web:
		vp.msaa_3d = Viewport.MSAA_2X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	else:
		vp.msaa_3d = Viewport.MSAA_4X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.position  = Vector3(0.0, 4.8, 2.5)
	camera.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
	camera.fov       = 52.0
	camera.current   = true
	add_child(camera)


func _setup_lighting() -> void:
	# Soft overhead key light (dimmer for Tron look)
	var dir_light := DirectionalLight3D.new()
	dir_light.rotation_degrees   = Vector3(-65, 25, 0)
	dir_light.light_energy       = 0.3
	dir_light.light_color        = Color(0.4, 0.6, 0.8)
	dir_light.shadow_enabled     = not _is_web  # shadows off on web
	add_child(dir_light)

	# Main overhead spot — cyan tinted
	var spot := SpotLight3D.new()
	spot.position          = Vector3(0, 4.0, 0)
	spot.rotation_degrees  = Vector3(-90, 0, 0)
	spot.spot_range        = 8.0
	spot.spot_angle        = 45.0
	spot.light_energy      = 1.0
	spot.light_color       = Color(0.3, 0.7, 1.0)
	spot.shadow_enabled    = not _is_web  # shadows off on web
	add_child(spot)

	if not _is_web:
		# Fill light from player side — warm orange (skip on web)
		var fill := SpotLight3D.new()
		fill.position          = Vector3(0, 3.0, 3.5)
		fill.rotation_degrees  = Vector3(-50, 0, 0)
		fill.spot_range        = 7.0
		fill.spot_angle        = 50.0
		fill.light_energy      = 0.5
		fill.light_color       = Color(1.0, 0.5, 0.2)
		add_child(fill)

		# Rim light from AI side — deep cyan (skip on web)
		var rim := SpotLight3D.new()
		rim.position          = Vector3(0, 3.0, -3.5)
		rim.rotation_degrees  = Vector3(-130, 0, 0)
		rim.spot_range        = 7.0
		rim.spot_angle        = 50.0
		rim.light_energy      = 0.5
		rim.light_color       = Color(0.0, 0.6, 1.0)
		add_child(rim)


# ╔══════════════════════════════════════════════════════════════╗
# ║  TABLE                                                         ║
# ╚══════════════════════════════════════════════════════════════╝

func _build_table() -> void:
	var table_root := Node3D.new()
	table_root.name = "Table"
	add_child(table_root)

	# ── Recessed playing surface (sunken into a lip for 3D depth) ──
	var surface_mesh := BoxMesh.new()
	surface_mesh.size = Vector3(TABLE_WIDTH - RAIL_THICK * 2, SURFACE_THICK, TABLE_LENGTH - RAIL_THICK * 2)
	var surface_inst := MeshInstance3D.new()
	surface_inst.mesh     = surface_mesh
	surface_inst.material_override = mat_surface
	surface_inst.position = Vector3(0, -SURFACE_THICK / 2.0 - 0.008, 0)
	table_root.add_child(surface_inst)

	# ── Raised outer lip / frame (table border, gives depth) ──
	var lip_mat := StandardMaterial3D.new()
	lip_mat.albedo_color = Color(0.015, 0.015, 0.04)
	lip_mat.metallic = 0.8
	lip_mat.roughness = 0.12
	lip_mat.emission_enabled = true
	lip_mat.emission = Color(0.0, 0.03, 0.06)
	lip_mat.emission_energy_multiplier = 0.3
	var lip_h := SURFACE_THICK + 0.016  # slightly taller than surface
	# Side lips
	for x_sign in [-1.0, 1.0]:
		var sl_mesh := BoxMesh.new()
		sl_mesh.size = Vector3(RAIL_THICK, lip_h, TABLE_LENGTH)
		var sl_inst := MeshInstance3D.new()
		sl_inst.mesh = sl_mesh
		sl_inst.material_override = lip_mat
		sl_inst.position = Vector3(x_sign * (_half_w - RAIL_THICK / 2.0), -lip_h / 2.0, 0)
		table_root.add_child(sl_inst)
	# End lips
	for z_sign in [-1.0, 1.0]:
		var el_mesh := BoxMesh.new()
		el_mesh.size = Vector3(TABLE_WIDTH, lip_h, RAIL_THICK)
		var el_inst := MeshInstance3D.new()
		el_inst.mesh = el_mesh
		el_inst.material_override = lip_mat
		el_inst.position = Vector3(0, -lip_h / 2.0, z_sign * (_half_l - RAIL_THICK / 2.0))
		table_root.add_child(el_inst)

	# ── Under-table neon glow strip (desktop only — skip on web) ──
	if not _is_web:
		var underglow_mat := StandardMaterial3D.new()
		underglow_mat.albedo_color = Color(0.0, 0.6, 0.8, 0.6)
		underglow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		underglow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		underglow_mat.emission_enabled = true
		underglow_mat.emission = Color(0.0, 0.6, 1.0)
		underglow_mat.emission_energy_multiplier = 2.0
		for x_sign in [-1.0, 1.0]:
			var ug_mesh := BoxMesh.new()
			ug_mesh.size = Vector3(0.02, 0.02, TABLE_LENGTH - 0.2)
			var ug_inst := MeshInstance3D.new()
			ug_inst.mesh = ug_mesh
			ug_inst.material_override = underglow_mat
			ug_inst.position = Vector3(x_sign * (_half_w + 0.01), -SURFACE_THICK - 0.02, 0)
			table_root.add_child(ug_inst)
		for z_sign in [-1.0, 1.0]:
			var ug_mesh := BoxMesh.new()
			ug_mesh.size = Vector3(TABLE_WIDTH - 0.2, 0.02, 0.02)
			var ug_inst := MeshInstance3D.new()
			ug_inst.mesh = ug_mesh
			ug_inst.material_override = underglow_mat
			ug_inst.position = Vector3(0, -SURFACE_THICK - 0.02, z_sign * (_half_l + 0.01))
			table_root.add_child(ug_inst)

	# Base / legs (with beveled inset for depth)
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(TABLE_WIDTH + 0.06, 0.5, TABLE_LENGTH + 0.06)
	var base_inst := MeshInstance3D.new()
	base_inst.mesh     = base_mesh
	base_inst.material_override = mat_base
	base_inst.position = Vector3(0, -SURFACE_THICK - 0.25, 0)
	table_root.add_child(base_inst)

	# Inset bevel step (intermediate between surface and base)
	var bevel_mat := StandardMaterial3D.new()
	bevel_mat.albedo_color = Color(0.02, 0.02, 0.05)
	bevel_mat.metallic = 0.7
	bevel_mat.roughness = 0.2
	var bevel_mesh := BoxMesh.new()
	bevel_mesh.size = Vector3(TABLE_WIDTH + 0.03, 0.04, TABLE_LENGTH + 0.03)
	var bevel_inst := MeshInstance3D.new()
	bevel_inst.mesh = bevel_mesh
	bevel_inst.material_override = bevel_mat
	bevel_inst.position = Vector3(0, -SURFACE_THICK - 0.02, 0)
	table_root.add_child(bevel_inst)

	# Goal slots (dark openings at each end)
	for z_sign in [-1.0, 1.0]:
		var slot_mesh := BoxMesh.new()
		slot_mesh.size = Vector3(GOAL_WIDTH, RAIL_HEIGHT + SURFACE_THICK, 0.15)
		var slot_inst := MeshInstance3D.new()
		slot_inst.mesh     = slot_mesh
		slot_inst.material_override = mat_goal_slot
		slot_inst.position = Vector3(0, (RAIL_HEIGHT - SURFACE_THICK) / 2.0,
									  z_sign * (_half_l + 0.075))
		table_root.add_child(slot_inst)

		# Glowing goal line on the surface (wider, brighter)
		var glow_mesh := BoxMesh.new()
		glow_mesh.size = Vector3(GOAL_WIDTH + 0.04, 0.008, 0.035)
		var glow_inst := MeshInstance3D.new()
		glow_inst.mesh = glow_mesh
		glow_inst.material_override = mat_goal_glow
		glow_inst.position = Vector3(0, 0.001, z_sign * (_half_l - 0.02))
		table_root.add_child(glow_inst)


func _build_markings() -> void:
	var markings := Node3D.new()
	markings.name = "Markings"
	add_child(markings)
	var y_mark := 0.002

	# Center line
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(TABLE_WIDTH - RAIL_THICK * 2, 0.003, 0.018)
	var line_inst := MeshInstance3D.new()
	line_inst.mesh     = line_mesh
	line_inst.material_override = mat_marking
	line_inst.position = Vector3(0, y_mark, 0)
	markings.add_child(line_inst)

	# Center circle
	var torus := TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.30
	torus.ring_segments = 48
	var torus_inst := MeshInstance3D.new()
	torus_inst.mesh     = torus
	torus_inst.material_override = mat_marking
	torus_inst.position = Vector3(0, y_mark - 0.01, 0)
	torus_inst.scale    = Vector3(1, 0.1, 1)
	markings.add_child(torus_inst)

	# Center dot
	var dot_mesh := CylinderMesh.new()
	dot_mesh.top_radius    = 0.03
	dot_mesh.bottom_radius = 0.03
	dot_mesh.height        = 0.004
	var dot_inst := MeshInstance3D.new()
	dot_inst.mesh     = dot_mesh
	dot_inst.material_override = mat_marking
	dot_inst.position = Vector3(0, y_mark, 0)
	markings.add_child(dot_inst)

	# ── Tron-style grid lines on the surface ──
	var grid_mat := StandardMaterial3D.new()
	grid_mat.albedo_color = Color(0.0, 0.5, 0.6, 0.25)
	grid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_mat.emission_enabled = true
	grid_mat.emission = Color(0.0, 0.4, 0.5)
	grid_mat.emission_energy_multiplier = 0.6

	var play_w := TABLE_WIDTH - RAIL_THICK * 2
	var play_l := TABLE_LENGTH - RAIL_THICK * 2
	var grid_spacing := 0.6 if _is_web else 0.3  # fewer grid lines on web
	var grid_thick := 0.004
	var grid_y := 0.001

	# Longitudinal lines (along Z)
	var nx := int(play_w / grid_spacing)
	for i in range(1, nx):
		var gx := -play_w / 2.0 + i * grid_spacing
		var g_mesh := BoxMesh.new()
		g_mesh.size = Vector3(grid_thick, 0.002, play_l)
		var g_inst := MeshInstance3D.new()
		g_inst.mesh = g_mesh
		g_inst.material_override = grid_mat
		g_inst.position = Vector3(gx, grid_y, 0)
		markings.add_child(g_inst)

	# Lateral lines (along X)
	var nz := int(play_l / grid_spacing)
	for i in range(1, nz):
		var gz := -play_l / 2.0 + i * grid_spacing
		var g_mesh := BoxMesh.new()
		g_mesh.size = Vector3(play_w, 0.002, grid_thick)
		var g_inst := MeshInstance3D.new()
		g_inst.mesh = g_mesh
		g_inst.material_override = grid_mat
		g_inst.position = Vector3(0, grid_y, gz)
		markings.add_child(g_inst)


# ╔══════════════════════════════════════════════════════════════╗
# ║  WALLS                                                         ║
# ╚══════════════════════════════════════════════════════════════╝

func _build_walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)

	# Side rails (full length)
	for x_sign in [-1.0, 1.0]:
		_add_wall(walls,
			Vector3(RAIL_THICK, RAIL_HEIGHT, TABLE_LENGTH),
			Vector3(x_sign * (_half_w - RAIL_THICK / 2.0), RAIL_HEIGHT / 2.0, 0))

	# End rail segments (leaving goal openings)
	var seg_width := (_half_w - GOAL_WIDTH / 2.0 - RAIL_THICK)
	for z_sign in [-1.0, 1.0]:
		for x_sign in [-1.0, 1.0]:
			var cx := float(x_sign) * (GOAL_WIDTH / 2.0 + seg_width / 2.0)
			_add_wall(walls,
				Vector3(seg_width, RAIL_HEIGHT, RAIL_THICK),
				Vector3(cx, RAIL_HEIGHT / 2.0, float(z_sign) * (_half_l - RAIL_THICK / 2.0)))

	# Corner posts at goal edges
	for z_sign in [-1.0, 1.0]:
		for x_sign in [-1.0, 1.0]:
			_add_wall(walls,
				Vector3(RAIL_THICK, RAIL_HEIGHT, RAIL_THICK),
				Vector3(x_sign * (GOAL_WIDTH / 2.0), RAIL_HEIGHT / 2.0,
						z_sign * (_half_l - RAIL_THICK / 2.0)))

	# ── Neon edge lines along the top of rails ──
	var neon_edge_mat := StandardMaterial3D.new()
	neon_edge_mat.albedo_color = Color(0.0, 1.0, 1.0)
	neon_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	neon_edge_mat.emission_enabled = true
	neon_edge_mat.emission = Color(0.0, 1.0, 1.0)
	neon_edge_mat.emission_energy_multiplier = 3.0
	var edge_y := RAIL_HEIGHT + 0.002
	var edge_h := 0.006

	# Side edge lines (full length)
	for x_sign in [-1.0, 1.0]:
		var edge_mesh := BoxMesh.new()
		edge_mesh.size = Vector3(0.01, edge_h, TABLE_LENGTH)
		var edge_inst := MeshInstance3D.new()
		edge_inst.mesh = edge_mesh
		edge_inst.material_override = neon_edge_mat
		edge_inst.position = Vector3(x_sign * (_half_w - RAIL_THICK / 2.0), edge_y, 0)
		walls.add_child(edge_inst)

	# End edge lines (segments beside goals)
	var seg_w := (_half_w - GOAL_WIDTH / 2.0 - RAIL_THICK)
	for z_sign in [-1.0, 1.0]:
		for x_sign in [-1.0, 1.0]:
			var cx := float(x_sign) * (GOAL_WIDTH / 2.0 + seg_w / 2.0)
			var edge_mesh := BoxMesh.new()
			edge_mesh.size = Vector3(seg_w, edge_h, 0.01)
			var edge_inst := MeshInstance3D.new()
			edge_inst.mesh = edge_mesh
			edge_inst.material_override = neon_edge_mat
			edge_inst.position = Vector3(cx, edge_y, float(z_sign) * (_half_l - RAIL_THICK / 2.0))
			walls.add_child(edge_inst)

	# ── Goal neon inserts (glowing strips embedded in the rails beside goals) ──
	var insert_mat := StandardMaterial3D.new()
	insert_mat.albedo_color = Color(1.0, 0.4, 0.0)
	insert_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	insert_mat.emission_enabled = true
	insert_mat.emission = Color(1.0, 0.5, 0.05)
	insert_mat.emission_energy_multiplier = 4.0

	var insert_depth := 0.015  # recessed into rail
	var insert_h := RAIL_HEIGHT * 0.5
	var seg_insert_w := (_half_w - GOAL_WIDTH / 2.0 - RAIL_THICK)
	for z_sign in [-1.0, 1.0]:
		# Horizontal inserts along end-rail inner face (the side facing the surface)
		for x_sign in [-1.0, 1.0]:
			var icx := float(x_sign) * (GOAL_WIDTH / 2.0 + seg_insert_w / 2.0)
			var i_mesh := BoxMesh.new()
			i_mesh.size = Vector3(seg_insert_w - 0.02, insert_h, insert_depth)
			var i_inst := MeshInstance3D.new()
			i_inst.mesh = i_mesh
			i_inst.material_override = insert_mat
			# Recessed into the inner face of the end rail
			var iz := float(z_sign) * (_half_l - RAIL_THICK)
			i_inst.position = Vector3(icx, insert_h / 2.0 + 0.005, iz)
			walls.add_child(i_inst)

		# Vertical inserts on the corner posts (facing inward toward goal)
		for x_sign in [-1.0, 1.0]:
			var cv_mesh := BoxMesh.new()
			cv_mesh.size = Vector3(insert_depth, insert_h, RAIL_THICK - 0.01)
			var cv_inst := MeshInstance3D.new()
			cv_inst.mesh = cv_mesh
			cv_inst.material_override = insert_mat
			# On the inner face of the corner post
			var cvx := float(x_sign) * (GOAL_WIDTH / 2.0 - insert_depth / 2.0)
			cv_inst.position = Vector3(cvx, insert_h / 2.0 + 0.005,
				z_sign * (_half_l - RAIL_THICK / 2.0))
			walls.add_child(cv_inst)

		# Floor insert — glowing strip under the goal opening
		var floor_mesh := BoxMesh.new()
		floor_mesh.size = Vector3(GOAL_WIDTH + 0.04, 0.008, 0.08)
		var floor_inst := MeshInstance3D.new()
		floor_inst.mesh = floor_mesh
		floor_inst.material_override = insert_mat
		floor_inst.position = Vector3(0, -0.001, z_sign * (_half_l + 0.02))
		walls.add_child(floor_inst)


func _add_wall(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1    # layer 1 = walls
	body.collision_mask  = 0
	var phys_mat := PhysicsMaterial.new()
	phys_mat.bounce  = 1.0
	phys_mat.friction = 0.0
	body.physics_material_override = phys_mat

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	# Rail body
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.material_override = mat_rail
	body.add_child(mesh_inst)

	# Beveled cap + groove details (skip on web for performance)
	if not _is_web:
		var cap_mesh := BoxMesh.new()
		cap_mesh.size = Vector3(size.x + 0.01, 0.012, size.z + 0.01)
		var cap_inst := MeshInstance3D.new()
		cap_inst.mesh = cap_mesh
		cap_inst.material_override = mat_rail
		cap_inst.position = Vector3(0, size.y / 2.0 + 0.006, 0)
		body.add_child(cap_inst)

		var groove_mat := StandardMaterial3D.new()
		groove_mat.albedo_color = Color(0.005, 0.005, 0.01)
		groove_mat.roughness = 0.9
		var groove_h := size.y * 0.3
		if size.x > 0.05 or size.z > 0.05:
			var groove_mesh := BoxMesh.new()
			if size.x > size.z:
				groove_mesh.size = Vector3(size.x - 0.02, groove_h, 0.005)
			else:
				groove_mesh.size = Vector3(0.005, groove_h, size.z - 0.02)
			var groove_inst := MeshInstance3D.new()
			groove_inst.mesh = groove_mesh
			groove_inst.material_override = groove_mat
			if size.x > size.z:
				groove_inst.position = Vector3(0, 0, -size.z / 2.0 - 0.001 if pos.z > 0 else size.z / 2.0 + 0.001)
			else:
				groove_inst.position = Vector3(-size.x / 2.0 - 0.001 if pos.x > 0 else size.x / 2.0 + 0.001, 0, 0)
			body.add_child(groove_inst)
	body.add_child(mesh_inst)
	parent.add_child(body)


# ╔══════════════════════════════════════════════════════════════╗
# ║  GOAL AREAS                                                    ║
# ╚══════════════════════════════════════════════════════════════╝

func _build_goal_areas() -> void:
	_add_goal_area(-1.0, 0)   # Player 2's goal → Player 1 scores
	_add_goal_area( 1.0, 1)   # Player 1's goal → Player 2 scores


func _add_goal_area(z_sign: float, scoring_player: int) -> void:
	var area := Area3D.new()
	area.position = Vector3(0, 0.02, z_sign * (_half_l + 0.12))
	area.collision_layer = 0
	area.collision_mask  = 2     # detect puck only
	area.monitoring      = true
	area.monitorable     = false

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(GOAL_WIDTH + 0.1, 0.15, 0.2)
	col.shape  = shape
	area.add_child(col)

	area.body_entered.connect(func(_body: Node3D):
		if GameManager.game_state == GameManager.GameState.PLAYING:
			GameManager.register_goal(scoring_player)
	)
	add_child(area)


# ╔══════════════════════════════════════════════════════════════╗
# ║  PUCK                                                          ║
# ╚══════════════════════════════════════════════════════════════╝

func _build_puck() -> void:
	puck = RigidBody3D.new()
	puck.name = "Puck"
	puck.mass  = 0.3
	puck.collision_layer = 2          # layer 2 = puck
	puck.collision_mask  = 1 | (1 << 2)   # collide with walls + paddles
	puck.gravity_scale   = 0.0
	puck.linear_damp     = 0.02
	puck.angular_damp    = 5.0
	puck.continuous_cd   = true
	puck.axis_lock_linear_y  = true
	puck.axis_lock_angular_x = true
	puck.axis_lock_angular_y = true
	puck.axis_lock_angular_z = true

	var phys_mat := PhysicsMaterial.new()
	phys_mat.bounce   = 1.0
	phys_mat.friction = 0.0
	puck.physics_material_override = phys_mat

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = PUCK_RADIUS
	shape.height = PUCK_HEIGHT
	col.shape = shape
	puck.add_child(col)

	# ── Main body with slightly beveled profile ──
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius    = PUCK_RADIUS - 0.003
	cyl.bottom_radius = PUCK_RADIUS
	cyl.height        = PUCK_HEIGHT
	cyl.radial_segments = 48
	mesh_inst.mesh = cyl
	mesh_inst.material_override = mat_puck
	puck.add_child(mesh_inst)

	# ── Glowing core inlay disc on top ──
	var inlay_mat := StandardMaterial3D.new()
	inlay_mat.albedo_color = Color(1.0, 0.6, 0.1)
	inlay_mat.emission_enabled = true
	inlay_mat.emission = Color(1.0, 0.5, 0.0)
	inlay_mat.emission_energy_multiplier = 4.0
	inlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var inlay_mesh := CylinderMesh.new()
	inlay_mesh.top_radius    = PUCK_RADIUS * 0.55
	inlay_mesh.bottom_radius = PUCK_RADIUS * 0.55
	inlay_mesh.height        = 0.002
	inlay_mesh.radial_segments = 48
	var inlay_inst := MeshInstance3D.new()
	inlay_inst.mesh = inlay_mesh
	inlay_inst.material_override = inlay_mat
	inlay_inst.position.y = PUCK_HEIGHT / 2.0 + 0.001
	puck.add_child(inlay_inst)

	# ── Bright edge ring (neon accent around perimeter) ──
	var edge_ring := TorusMesh.new()
	edge_ring.inner_radius  = PUCK_RADIUS - 0.006
	edge_ring.outer_radius  = PUCK_RADIUS + 0.001
	edge_ring.ring_segments = 48
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(1.0, 0.2, 0.0)
	edge_mat.emission_enabled = true
	edge_mat.emission = Color(1.0, 0.3, 0.0)
	edge_mat.emission_energy_multiplier = 3.5
	var edge_inst := MeshInstance3D.new()
	edge_inst.mesh = edge_ring
	edge_inst.material_override = edge_mat
	edge_inst.scale = Vector3(1, 0.2, 1)
	puck.add_child(edge_inst)

	# ── Bottom bevel ring ──
	var bevel_mesh := CylinderMesh.new()
	bevel_mesh.top_radius    = PUCK_RADIUS
	bevel_mesh.bottom_radius = PUCK_RADIUS - 0.005
	bevel_mesh.height        = 0.005
	bevel_mesh.radial_segments = 48
	var bevel_inst := MeshInstance3D.new()
	bevel_inst.mesh = bevel_mesh
	bevel_inst.material_override = mat_puck
	bevel_inst.position.y = -PUCK_HEIGHT / 2.0 + 0.0025
	puck.add_child(bevel_inst)

	puck.set_script(load("res://scripts/puck.gd"))
	add_child(puck)
	_reset_puck(Vector3.ZERO)


# ╔══════════════════════════════════════════════════════════════╗
# ║  PADDLES  (Node3D visual  +  StaticBody3D collider)            ║
# ╚══════════════════════════════════════════════════════════════╝

func _build_paddles() -> void:
	paddle1     = _create_paddle_visual("Paddle_P1", mat_paddle_r)
	paddle1_col = _create_paddle_collider("Paddle_P1_Col")
	paddle2     = _create_paddle_visual("Paddle_P2", mat_paddle_b)
	paddle2_col = _create_paddle_collider("Paddle_P2_Col")

	# Movement bounds (each player restricted to own half)
	_p1_bounds_min = Vector3(-_inner_w + PADDLE_RADIUS, 0,  0.15)
	_p1_bounds_max = Vector3( _inner_w - PADDLE_RADIUS, 0,  _inner_l - PADDLE_RADIUS)
	_p2_bounds_min = Vector3(-_inner_w + PADDLE_RADIUS, 0, -_inner_l + PADDLE_RADIUS)
	_p2_bounds_max = Vector3( _inner_w - PADDLE_RADIUS, 0, -0.15)

	add_child(paddle1)
	add_child(paddle1_col)
	var p1_start := Vector3(0, PADDLE_HEIGHT / 2.0, _half_l * 0.6)
	paddle1.position     = p1_start
	paddle1_col.position = p1_start
	_p1_target = p1_start

	add_child(paddle2)
	add_child(paddle2_col)
	var p2_start := Vector3(0, PADDLE_HEIGHT / 2.0, -_half_l * 0.6)
	paddle2.position     = p2_start
	paddle2_col.position = p2_start
	_p2_target = p2_start

	_ai_home_pos = Vector3(0, PADDLE_HEIGHT / 2.0,
		_p2_bounds_min.z + (_p2_bounds_max.z - _p2_bounds_min.z) * 0.3)


func _create_paddle_visual(n: String, mat: StandardMaterial3D) -> Node3D:
	var root := Node3D.new()
	root.name = n

	# ── Chamfered base (wide bottom tapers slightly) ──
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius    = PADDLE_RADIUS - 0.003
	base_mesh.bottom_radius = PADDLE_RADIUS
	base_mesh.height        = PADDLE_HEIGHT * 0.45
	base_mesh.radial_segments = 48
	var base_inst := MeshInstance3D.new()
	base_inst.mesh = base_mesh
	base_inst.material_override = mat
	base_inst.position.y = -PADDLE_HEIGHT * 0.15
	root.add_child(base_inst)

	# ── Neon accent ring at base edge (bright glow strip) ──
	var glow_ring := TorusMesh.new()
	glow_ring.inner_radius  = PADDLE_RADIUS - 0.005
	glow_ring.outer_radius  = PADDLE_RADIUS + 0.003
	glow_ring.ring_segments = 48
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = mat.emission
	glow_mat.emission_enabled = true
	glow_mat.emission = mat.emission
	glow_mat.emission_energy_multiplier = 3.5
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow_inst := MeshInstance3D.new()
	glow_inst.mesh = glow_ring
	glow_inst.material_override = glow_mat
	glow_inst.position.y = -PADDLE_HEIGHT * 0.35
	glow_inst.scale = Vector3(1, 0.2, 1)
	root.add_child(glow_inst)

	# ── Handle knob with grip ridges ──
	var knob_mesh := CylinderMesh.new()
	knob_mesh.top_radius    = PADDLE_RADIUS * 0.4
	knob_mesh.bottom_radius = PADDLE_RADIUS * 0.65
	knob_mesh.height        = PADDLE_HEIGHT * 0.65
	knob_mesh.radial_segments = 48
	var knob_inst := MeshInstance3D.new()
	knob_inst.mesh = knob_mesh
	knob_inst.material_override = mat
	knob_inst.position.y = PADDLE_HEIGHT * 0.15
	root.add_child(knob_inst)

	# ── Top cap (small glowing dome) ──
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius    = PADDLE_RADIUS * 0.15
	cap_mesh.bottom_radius = PADDLE_RADIUS * 0.38
	cap_mesh.height        = PADDLE_HEIGHT * 0.15
	cap_mesh.radial_segments = 32
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = mat.emission
	cap_mat.emission_enabled = true
	cap_mat.emission = mat.emission
	cap_mat.emission_energy_multiplier = 3.0
	cap_mat.metallic = 0.8
	cap_mat.roughness = 0.05
	var cap_inst := MeshInstance3D.new()
	cap_inst.mesh = cap_mesh
	cap_inst.material_override = cap_mat
	cap_inst.position.y = PADDLE_HEIGHT * 0.5
	root.add_child(cap_inst)

	# ── Middle accent ring (separates body from knob) ──
	var mid_ring := TorusMesh.new()
	mid_ring.inner_radius  = PADDLE_RADIUS * 0.6
	mid_ring.outer_radius  = PADDLE_RADIUS * 0.68
	mid_ring.ring_segments = 32
	var mid_inst := MeshInstance3D.new()
	mid_inst.mesh = mid_ring
	mid_inst.material_override = glow_mat
	mid_inst.position.y = -PADDLE_HEIGHT * 0.02
	mid_inst.scale = Vector3(1, 0.15, 1)
	root.add_child(mid_inst)

	return root


func _create_paddle_collider(n: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = n
	body.collision_layer = 1 << 2   # layer 3 = paddles
	body.collision_mask  = 0

	var phys_mat := PhysicsMaterial.new()
	phys_mat.bounce   = 1.0
	phys_mat.friction = 0.0
	body.physics_material_override = phys_mat

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = PADDLE_RADIUS + 0.02
	shape.height = PADDLE_HEIGHT * 3.0
	col.shape = shape
	body.add_child(col)

	return body


# ╔══════════════════════════════════════════════════════════════╗
# ║  USER INTERFACE                                                ║
# ║  No wrapper containers — panels anchored directly to center.   ║
# ╚══════════════════════════════════════════════════════════════╝

func _build_ui() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)

	_build_score_display(hud_layer)
	_build_countdown(hud_layer)
	_build_main_menu(hud_layer)
	_build_game_over(hud_layer)


func _build_score_display(parent: Node) -> void:
	score_label = Label.new()
	score_label.name = "ScoreLabel"
	score_label.text = "0  -  0"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_label.add_theme_font_size_override("font_size", 48)
	score_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	score_label.add_theme_constant_override("shadow_offset_x", 2)
	score_label.add_theme_constant_override("shadow_offset_y", 2)
	score_label.anchor_left   = 0.0
	score_label.anchor_right  = 1.0
	score_label.anchor_top    = 0.0
	score_label.anchor_bottom = 0.0
	score_label.offset_top    = 10
	score_label.offset_bottom = 70
	score_label.visible = false
	parent.add_child(score_label)


func _build_countdown(parent: Node) -> void:
	countdown_label = Label.new()
	countdown_label.name = "CountdownLabel"
	countdown_label.text = ""
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_label.add_theme_font_size_override("font_size", 96)
	countdown_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	countdown_label.add_theme_color_override("font_shadow_color", Color(0.3, 0.2, 0.0, 0.6))
	countdown_label.add_theme_constant_override("shadow_offset_x", 0)
	countdown_label.add_theme_constant_override("shadow_offset_y", 3)
	countdown_label.anchor_left   = 0.3
	countdown_label.anchor_right  = 0.7
	countdown_label.anchor_top    = 0.3
	countdown_label.anchor_bottom = 0.7
	countdown_label.visible = false
	parent.add_child(countdown_label)


func _build_main_menu(parent: Node) -> void:
	# NO wrapper — PanelContainer added directly, centered via anchors
	menu_panel = PanelContainer.new()
	menu_panel.name = "MenuPanel"
	menu_panel.custom_minimum_size = Vector2(400, 360)
	# Center using anchor 0.5 + symmetric offsets
	menu_panel.anchor_left   = 0.5
	menu_panel.anchor_right  = 0.5
	menu_panel.anchor_top    = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left   = -200
	menu_panel.offset_right  =  200
	menu_panel.offset_top    = -180
	menu_panel.offset_bottom =  180

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.14, 0.95)
	style.corner_radius_top_left     = 20
	style.corner_radius_top_right    = 20
	style.corner_radius_bottom_left  = 20
	style.corner_radius_bottom_right = 20
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_color = Color(0.3, 0.45, 0.9, 0.7)
	style.shadow_color = Color(0.1, 0.15, 0.4, 0.5)
	style.shadow_size  = 12
	style.content_margin_left   = 30
	style.content_margin_right  = 30
	style.content_margin_top    = 24
	style.content_margin_bottom = 24
	menu_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	menu_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "AIR HOCKEY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.2, 0.3, 0.8, 0.5))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	vbox.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "Fast-Paced Tabletop Action"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.55, 0.7, 0.8))
	vbox.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	# Buttons
	var btn_ai := Button.new()
	btn_ai.name = "BtnVsAI"
	btn_ai.text = "Play vs AI"
	btn_ai.custom_minimum_size = Vector2(280, 54)
	_style_button(btn_ai, Color(0.12, 0.25, 0.55))
	btn_ai.pressed.connect(_on_btn_vs_ai)
	vbox.add_child(btn_ai)

	var btn_2p := Button.new()
	btn_2p.name = "Btn2Player"
	btn_2p.text = "2-Player Local"
	btn_2p.custom_minimum_size = Vector2(280, 54)
	_style_button(btn_2p, Color(0.15, 0.2, 0.45))
	btn_2p.pressed.connect(_on_btn_vs_player)
	vbox.add_child(btn_2p)

	var btn_quit := Button.new()
	btn_quit.name = "BtnQuit"
	btn_quit.text = "Quit"
	btn_quit.custom_minimum_size = Vector2(280, 44)
	_style_button(btn_quit, Color(0.45, 0.12, 0.12))
	btn_quit.pressed.connect(_on_btn_quit)
	vbox.add_child(btn_quit)

	parent.add_child(menu_panel)


func _build_game_over(parent: Node) -> void:
	# NO wrapper — PanelContainer added directly, centered via anchors
	game_over_panel = PanelContainer.new()
	game_over_panel.name = "GameOverPanel"
	game_over_panel.custom_minimum_size = Vector2(400, 280)
	game_over_panel.visible = false
	# Center using anchor 0.5 + symmetric offsets
	game_over_panel.anchor_left   = 0.5
	game_over_panel.anchor_right  = 0.5
	game_over_panel.anchor_top    = 0.5
	game_over_panel.anchor_bottom = 0.5
	game_over_panel.offset_left   = -200
	game_over_panel.offset_right  =  200
	game_over_panel.offset_top    = -140
	game_over_panel.offset_bottom =  140

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.1, 0.96)
	style.corner_radius_top_left     = 20
	style.corner_radius_top_right    = 20
	style.corner_radius_bottom_left  = 20
	style.corner_radius_bottom_right = 20
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_color = Color(0.9, 0.7, 0.2, 0.8)
	style.shadow_color = Color(0.3, 0.2, 0.05, 0.4)
	style.shadow_size  = 12
	style.content_margin_left   = 30
	style.content_margin_right  = 30
	style.content_margin_top    = 24
	style.content_margin_bottom = 24
	game_over_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	game_over_panel.add_child(vbox)

	winner_label = Label.new()
	winner_label.text = "Player Wins!"
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	winner_label.add_theme_font_size_override("font_size", 38)
	winner_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	winner_label.add_theme_color_override("font_shadow_color", Color(0.3, 0.2, 0.0, 0.5))
	winner_label.add_theme_constant_override("shadow_offset_x", 0)
	winner_label.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(winner_label)

	var btn_again := Button.new()
	btn_again.name = "BtnPlayAgain"
	btn_again.text = "Play Again"
	btn_again.custom_minimum_size = Vector2(260, 50)
	_style_button(btn_again, Color(0.12, 0.4, 0.12))
	btn_again.pressed.connect(_on_btn_play_again)
	vbox.add_child(btn_again)

	var btn_menu := Button.new()
	btn_menu.name = "BtnMainMenu"
	btn_menu.text = "Main Menu"
	btn_menu.custom_minimum_size = Vector2(260, 46)
	_style_button(btn_menu)
	btn_menu.pressed.connect(_on_btn_back_menu)
	vbox.add_child(btn_menu)

	parent.add_child(game_over_panel)


func _style_button(btn: Button, base_color: Color = Color(0.15, 0.2, 0.45)) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = base_color
	normal.corner_radius_top_left     = 10
	normal.corner_radius_top_right    = 10
	normal.corner_radius_bottom_left  = 10
	normal.corner_radius_bottom_right = 10
	normal.content_margin_left   = 20
	normal.content_margin_right  = 20
	normal.content_margin_top    = 10
	normal.content_margin_bottom = 10
	normal.shadow_color = Color(0, 0, 0, 0.3)
	normal.shadow_size  = 4
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = base_color.lightened(0.25)
	hover.shadow_size = 6
	btn.add_theme_stylebox_override("hover", hover)

	var pressed_style := normal.duplicate()
	pressed_style.bg_color = base_color.darkened(0.2)
	pressed_style.shadow_size = 2
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var focus_style := normal.duplicate()
	focus_style.border_width_top    = 2
	focus_style.border_width_bottom = 2
	focus_style.border_width_left   = 2
	focus_style.border_width_right  = 2
	focus_style.border_color = Color(0.5, 0.6, 1.0, 0.8)
	btn.add_theme_stylebox_override("focus", focus_style)

	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(0.92, 0.92, 0.97))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))


# ╔══════════════════════════════════════════════════════════════╗
# ║  BUTTON CALLBACKS                                              ║
# ╚══════════════════════════════════════════════════════════════╝

func _on_btn_vs_ai() -> void:
	_play_sfx(sfx_click)
	_start_game(GameManager.GameMode.VS_AI)

func _on_btn_vs_player() -> void:
	_play_sfx(sfx_click)
	_start_game(GameManager.GameMode.VS_PLAYER)

func _on_btn_quit() -> void:
	_play_sfx(sfx_click)
	get_tree().quit()

func _on_btn_play_again() -> void:
	_play_sfx(sfx_click)
	game_over_panel.visible = false
	_start_game(GameManager.game_mode)

func _on_btn_back_menu() -> void:
	_play_sfx(sfx_click)
	game_over_panel.visible = false
	GameManager.return_to_menu()
	_show_menu()


# ╔══════════════════════════════════════════════════════════════╗
# ║  GAME FLOW                                                     ║
# ╚══════════════════════════════════════════════════════════════╝

func _show_menu() -> void:
	menu_panel.visible          = true
	game_over_panel.visible     = false
	score_label.visible         = false
	countdown_label.visible     = false
	puck.freeze = true


func _hide_menu() -> void:
	menu_panel.visible = false


func _show_game_over() -> void:
	puck.freeze = true
	var is_p1_winner := GameManager.score[0] >= GameManager.winning_score
	var is_perfect := (is_p1_winner and GameManager.score[1] == 0) or (not is_p1_winner and GameManager.score[0] == 0)

	# Choose sound: perfect victory fanfare or normal game over
	if is_perfect:
		_play_sfx(sfx_perfect)
	else:
		_play_sfx(sfx_game_over)
		if is_p1_winner:
			_play_sfx(sfx_cheer)
		else:
			_play_sfx(sfx_boo)

	if winner_label:
		var w := "Player 1" if is_p1_winner else "Player 2"
		if is_perfect:
			winner_label.text = "PERFECT!\n%s Wins!" % w
			winner_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.0))
		else:
			winner_label.text = "%s Wins!" % w
			winner_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))

	# ── Animated entrance: scale from 0 + fade in ──
	game_over_panel.visible = true
	game_over_panel.modulate = Color(1, 1, 1, 0)
	game_over_panel.scale = Vector2(0.3, 0.3)
	game_over_panel.pivot_offset = game_over_panel.size / 2.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(game_over_panel, "modulate", Color(1, 1, 1, 1), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(game_over_panel, "scale", Vector2(1.0, 1.0), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Extra flash for perfect game
	if is_perfect:
		var flash_tween := create_tween()
		flash_tween.set_loops(3)
		flash_tween.tween_property(winner_label, "modulate", Color(1.0, 0.2, 0.0, 1.0), 0.25)
		flash_tween.tween_property(winner_label, "modulate", Color(1.0, 0.9, 0.3, 1.0), 0.25)


func _hide_game_over() -> void:
	game_over_panel.visible = false


func _start_game(mode: GameManager.GameMode) -> void:
	_hide_menu()
	_hide_game_over()
	score_label.visible = true

	_reset_puck_for_play()

	var p1_pos := Vector3(0, PADDLE_HEIGHT / 2.0, _half_l * 0.6)
	paddle1.position     = p1_pos
	paddle1_col.position = p1_pos
	_p1_target = p1_pos

	var p2_pos := Vector3(0, PADDLE_HEIGHT / 2.0, -_half_l * 0.6)
	paddle2.position     = p2_pos
	paddle2_col.position = p2_pos
	_p2_target = p2_pos

	GameManager.start_game(mode)


func _reset_puck(pos: Vector3) -> void:
	puck.linear_velocity  = Vector3.ZERO
	puck.angular_velocity = Vector3.ZERO
	puck.position = Vector3(pos.x, PUCK_HEIGHT / 2.0, pos.z)


func _reset_puck_for_play() -> void:
	puck.freeze = false
	_reset_puck(Vector3.ZERO)
	var dir_z := 1.0 if _last_scorer == 0 else -1.0
	puck.linear_velocity = Vector3(randf_range(-0.5, 0.5), 0, dir_z) * PUCK_START_SPEED


func _on_score_changed(scores: Array[int]) -> void:
	score_label.text = "%d  -  %d" % [scores[0], scores[1]]


func _on_goal_scored(scoring_player: int) -> void:
	_last_scorer = scoring_player
	_reset_puck(Vector3.ZERO)
	puck.freeze = true
	_reset_timer = RESET_DELAY
	countdown_label.visible = true
	countdown_label.text = str(ceili(RESET_DELAY))
	_play_sfx(sfx_goal)
	# Crowd reaction: cheer for player 1 scoring, boo when opponent scores
	if scoring_player == 0:
		_play_sfx(sfx_cheer)
	else:
		_play_sfx(sfx_boo)
	# Fire goal celebration particles
	var gp := goal_particles_p1 if scoring_player == 0 else goal_particles_p2
	if gp:
		gp.restart()
		gp.emitting = true


func _on_game_state_changed(state: GameManager.GameState) -> void:
	match state:
		GameManager.GameState.GAME_OVER:
			_show_game_over()
		GameManager.GameState.MENU:
			_show_menu()


# ╔══════════════════════════════════════════════════════════════╗
# ║  SOUND SYSTEM                                                  ║
# ╚══════════════════════════════════════════════════════════════╝

func _build_sounds() -> void:
	sfx_hit = _make_player(SoundGen.make_hit_sound())
	sfx_wall = _make_player(SoundGen.make_wall_bounce_sound())
	sfx_goal = _make_player(SoundGen.make_goal_sound())
	sfx_countdown = _make_player(SoundGen.make_countdown_beep(false))
	sfx_game_over = _make_player(SoundGen.make_game_over_sound())
	sfx_click = _make_player(SoundGen.make_menu_click_sound())
	sfx_cheer = _make_player(SoundGen.make_crowd_cheer_sound())
	sfx_boo = _make_player(SoundGen.make_crowd_boo_sound())
	sfx_perfect = _make_player(SoundGen.make_perfect_victory_sound())


func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -6.0
	p.bus = "Master"
	add_child(p)
	return p


func _play_sfx(player: AudioStreamPlayer) -> void:
	if player and not player.playing:
		player.pitch_scale = 1.0
		player.play()


func _play_sfx_pitched(player: AudioStreamPlayer, pitch: float) -> void:
	if player:
		player.pitch_scale = pitch
		player.play()


# ╔══════════════════════════════════════════════════════════════╗
# ║  PARTICLE EFFECTS                                              ║
# ╚══════════════════════════════════════════════════════════════╝

func _build_goal_particles() -> void:
	goal_particles_p1 = _create_goal_burst(Vector3(0, 0.05, -_half_l - 0.05), Color(1.0, 0.4, 0.0))
	goal_particles_p2 = _create_goal_burst(Vector3(0, 0.05, _half_l + 0.05), Color(0.0, 0.8, 1.0))
	_build_puck_trail()


func _create_goal_burst(pos: Vector3, color: Color) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.position = pos
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 16 if _is_web else 40
	particles.lifetime = 0.8
	particles.explosiveness = 0.95
	particles.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 3, 4))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -4.0, 0)
	mat.damping_min = 1.0
	mat.damping_max = 2.0
	mat.scale_min = 0.02
	mat.scale_max = 0.06
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(GOAL_WIDTH * 0.4, 0.05, 0.05)

	# Color ramp: bright neon → fade out
	var burst_ramp := Gradient.new()
	burst_ramp.set_color(0, Color(color.r, color.g, color.b, 1.0))
	burst_ramp.add_point(0.5, Color(color.r * 0.8, color.g * 0.8, color.b * 0.8, 0.7))
	burst_ramp.set_color(1, Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.0))
	var burst_tex := GradientTexture1D.new()
	burst_tex.gradient = burst_ramp
	mat.color_ramp = burst_tex

	particles.process_material = mat

	# Simple quad mesh for particles
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.04, 0.04)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = color
	mesh_mat.emission_enabled = true
	mesh_mat.emission = color
	mesh_mat.emission_energy_multiplier = 3.5
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh

	add_child(particles)
	return particles


func _build_puck_trail() -> void:
	puck_trail = GPUParticles3D.new()
	puck_trail.emitting = false
	puck_trail.amount = 16 if _is_web else 40
	puck_trail.lifetime = 0.3 if _is_web else 0.45
	puck_trail.amount_ratio = 0.0
	puck_trail.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 2, 6))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 5.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.15
	mat.gravity = Vector3.ZERO
	mat.damping_min = 2.0
	mat.damping_max = 4.0
	mat.scale_min = 0.015
	mat.scale_max = 0.045

	# Neon orange color ramp (bright → fade)
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(1.0, 0.5, 0.0, 0.9))
	color_ramp.add_point(0.4, Color(1.0, 0.25, 0.0, 0.6))
	color_ramp.set_color(1, Color(1.0, 0.1, 0.0, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex

	puck_trail.process_material = mat

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.04, 0.04)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.8)
	mesh_mat.emission_enabled = true
	mesh_mat.emission = Color(1.0, 0.4, 0.0)
	mesh_mat.emission_energy_multiplier = 3.0
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_mat
	puck_trail.draw_pass_1 = mesh

	add_child(puck_trail)
