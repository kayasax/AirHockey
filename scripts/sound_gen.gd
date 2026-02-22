## Sound Generator — creates rich procedural WAV AudioStreams for the air hockey game.
## 44100 Hz stereo, multi-harmonic synthesis with reverb simulation.
## No external files needed.
extends RefCounted
class_name SoundGen

const SR := 44100  # Sample rate

# ─── Helper: write a stereo sample pair into data ───
static func _write_stereo(data: PackedByteArray, idx: int, left: float, right: float) -> void:
	var lv := int(clampf(left, -1.0, 1.0) * 32767.0)
	var rv := int(clampf(right, -1.0, 1.0) * 32767.0)
	var b := idx * 4
	data[b]     = lv & 0xFF
	data[b + 1] = (lv >> 8) & 0xFF
	data[b + 2] = rv & 0xFF
	data[b + 3] = (rv >> 8) & 0xFF

# ─── Helper: create a stereo WAV stream from data ───
static func _make_stream(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SR
	stream.stereo = true
	stream.data = data
	return stream

# ─── Helper: sawtooth wave ───
static func _saw(phase: float) -> float:
	return 2.0 * fmod(phase, 1.0) - 1.0

# ─── Helper: square wave with adjustable duty ───
static func _square(phase: float, duty: float = 0.5) -> float:
	return 1.0 if fmod(phase, 1.0) < duty else -1.0

# ─── Helper: simple reverb tail via comb filter ───
static func _apply_reverb(samples: Array[float], decay: float = 0.3, delay_ms: float = 40.0) -> Array[float]:
	var delay_samples := int(SR * delay_ms / 1000.0)
	var out: Array[float] = []
	out.resize(samples.size())
	for i in samples.size():
		out[i] = samples[i]
		if i >= delay_samples:
			out[i] += out[i - delay_samples] * decay
		# Second shorter tap for density
		var tap2 := int(delay_samples * 0.6)
		if i >= tap2:
			out[i] += out[i - tap2] * decay * 0.5
	return out


# ╔═══════════════════════════════════════════════════════════╗
# ║  HIT SOUND — sharp impact with metallic ring-out         ║
# ╚═══════════════════════════════════════════════════════════╝
static func make_hit_sound(freq: float = 800.0, duration: float = 0.15) -> AudioStreamWAV:
	var num := int(SR * duration)
	var left_buf: Array[float] = []
	var right_buf: Array[float] = []
	left_buf.resize(num)
	right_buf.resize(num)

	for i in num:
		var t := float(i) / SR
		var p := float(i) / num
		# Sharp exponential decay with fast attack
		var env := pow(1.0 - p, 3.0)
		# Transient click (first 3ms)
		var click := 0.0
		if t < 0.003:
			click = (1.0 - t / 0.003) * 0.9
		# Main tone with harmonics (adds metallic character)
		var phase := t * freq
		var s := sin(phase * TAU) * 0.4
		s += sin(phase * 2.0 * TAU) * 0.2
		s += sin(phase * 3.01 * TAU) * 0.1  # slightly detuned 3rd for shimmer
		s += _saw(phase * 4.0) * 0.05  # subtle grit
		s = s * env + click
		# Stereo spread — slight delay on right
		left_buf[i] = s
		right_buf[i] = s * 0.85

	# Apply reverb
	left_buf = _apply_reverb(left_buf, 0.2, 25.0)
	right_buf = _apply_reverb(right_buf, 0.2, 35.0)

	var data := PackedByteArray()
	data.resize(num * 4)
	for i in num:
		_write_stereo(data, i, left_buf[i], right_buf[i])
	return _make_stream(data)


# ╔═══════════════════════════════════════════════════════════╗
# ║  WALL BOUNCE — punchy thud with bright click              ║
# ╚═══════════════════════════════════════════════════════════╝
static func make_wall_bounce_sound() -> AudioStreamWAV:
	var duration := 0.1
	var num := int(SR * duration)
	var left_buf: Array[float] = []
	var right_buf: Array[float] = []
	left_buf.resize(num)
	right_buf.resize(num)

	for i in num:
		var t := float(i) / SR
		var p := float(i) / num
		var env := pow(1.0 - p, 4.0)
		# Low thud — pitch drops fast (200→80Hz)
		var thud_freq := 200.0 - p * 120.0
		var thud := sin(t * thud_freq * TAU) * 0.5
		# Mid crack
		var crack := sin(t * 900.0 * TAU) * env * env * 0.3
		# High click transient
		var click := 0.0
		if t < 0.002:
			click = (1.0 - t / 0.002) * 0.7
		# Noise burst (first 5ms)
		var noise := 0.0
		if t < 0.005:
			noise = randf_range(-0.4, 0.4) * (1.0 - t / 0.005)
		var s := (thud + crack) * env + click + noise
		left_buf[i] = s
		right_buf[i] = s * 0.9

	left_buf = _apply_reverb(left_buf, 0.15, 20.0)
	right_buf = _apply_reverb(right_buf, 0.15, 30.0)

	var data := PackedByteArray()
	data.resize(num * 4)
	for i in num:
		_write_stereo(data, i, left_buf[i], right_buf[i])
	return _make_stream(data)


# ╔═══════════════════════════════════════════════════════════╗
# ║  GOAL SOUND — triumphant rising fanfare with bass drop    ║
# ╚═══════════════════════════════════════════════════════════╝
static func make_goal_sound() -> AudioStreamWAV:
	var duration := 0.7
	var num := int(SR * duration)
	var left_buf: Array[float] = []
	var right_buf: Array[float] = []
	left_buf.resize(num)
	right_buf.resize(num)

	for i in num:
		var t := float(i) / SR
		var p := float(i) / num
		var env := pow(1.0 - p, 1.5)
		# Rising pitch sweep (C5 → A6): 523 → 1760 Hz
		var freq := 523.0 + p * p * 1237.0
		# Main tone with rich harmonics
		var phase := t * freq
		var s := sin(phase * TAU) * 0.35
		s += sin(phase * 2.0 * TAU) * 0.2       # octave
		s += sin(phase * 1.5 * TAU) * 0.15      # perfect fifth
		s += sin(phase * 3.0 * TAU) * 0.08      # 12th harmonic
		s += _saw(phase * 0.5) * 0.06           # sub saw
		# Sub bass impact (first 200ms)
		if t < 0.2:
			var bass_env := pow(1.0 - t / 0.2, 2.0)
			s += sin(t * 80.0 * TAU) * bass_env * 0.4
		# Victory shimmer (high sparkle)
		s += sin(t * freq * 4.0 * TAU) * env * env * 0.1
		s *= env
		# Wide stereo — left/right offset
		left_buf[i] = s * 1.0
		right_buf[i] = s * 0.8

	left_buf = _apply_reverb(left_buf, 0.35, 50.0)
	right_buf = _apply_reverb(right_buf, 0.35, 65.0)

	var data := PackedByteArray()
	data.resize(num * 4)
	for i in num:
		_write_stereo(data, i, left_buf[i], right_buf[i])
	return _make_stream(data)


# ╔═══════════════════════════════════════════════════════════╗
# ║  COUNTDOWN BEEP — clean digital tone with attack          ║
# ╚═══════════════════════════════════════════════════════════╝
static func make_countdown_beep(high: bool = false) -> AudioStreamWAV:
	var duration := 0.18
	var num := int(SR * duration)
	var left_buf: Array[float] = []
	var right_buf: Array[float] = []
	left_buf.resize(num)
	right_buf.resize(num)
	var freq := 1400.0 if high else 880.0

	for i in num:
		var t := float(i) / SR
		var p := float(i) / num
		# Smooth attack + decay envelope
		var attack := minf(t / 0.005, 1.0)  # 5ms attack
		var decay := pow(1.0 - p, 2.0)
		var env := attack * decay
		# Clean tone with subtle 5th
		var s := sin(t * freq * TAU) * 0.4
		s += sin(t * freq * 1.5 * TAU) * 0.12   # perfect fifth
		s += sin(t * freq * 2.0 * TAU) * 0.08   # octave
		s *= env
		left_buf[i] = s
		right_buf[i] = s

	var data := PackedByteArray()
	data.resize(num * 4)
	for i in num:
		_write_stereo(data, i, left_buf[i], right_buf[i])
	return _make_stream(data)


# ╔═══════════════════════════════════════════════════════════╗
# ║  GAME OVER — majestic chord with shimmer fadeout           ║
# ╚═══════════════════════════════════════════════════════════╝
static func make_game_over_sound() -> AudioStreamWAV:
	var duration := 1.2
	var num := int(SR * duration)
	var left_buf: Array[float] = []
	var right_buf: Array[float] = []
	left_buf.resize(num)
	right_buf.resize(num)

	for i in num:
		var t := float(i) / SR
		var p := float(i) / num
		# Soft attack + long smooth decay
		var attack := minf(t / 0.02, 1.0)
		var env := attack * pow(1.0 - p, 1.2)
		# Rich major 7th chord (C5, E5, G5, B5) with harmonics
		var s := sin(t * 523.25 * TAU) * 0.25    # C5
		s += sin(t * 659.25 * TAU) * 0.2         # E5
		s += sin(t * 783.99 * TAU) * 0.18        # G5
		s += sin(t * 987.77 * TAU) * 0.12        # B5
		# Octave doubling for fullness
		s += sin(t * 1046.5 * TAU) * 0.08        # C6
		s += sin(t * 1318.5 * TAU) * 0.06        # E6
		s *= env
		# Sparkle / shimmer (high frequency modulated)
		var shimmer := sin(t * 2093.0 * TAU) * sin(t * 6.0 * TAU) * env * env * 0.1
		s += shimmer
		# Stereo widening — pan chord components
		left_buf[i] = s + sin(t * 523.25 * TAU) * env * 0.05
		right_buf[i] = s + sin(t * 783.99 * TAU) * env * 0.05

	left_buf = _apply_reverb(left_buf, 0.4, 60.0)
	right_buf = _apply_reverb(right_buf, 0.4, 80.0)

	var data := PackedByteArray()
	data.resize(num * 4)
	for i in num:
		_write_stereo(data, i, left_buf[i], right_buf[i])
	return _make_stream(data)


# ╔═══════════════════════════════════════════════════════════╗
# ║  MENU CLICK — snappy digital pop                          ║
# ╚═══════════════════════════════════════════════════════════╝
static func make_menu_click_sound() -> AudioStreamWAV:
	var duration := 0.08
	var num := int(SR * duration)
	var left_buf: Array[float] = []
	var right_buf: Array[float] = []
	left_buf.resize(num)
	right_buf.resize(num)

	for i in num:
		var t := float(i) / SR
		var p := float(i) / num
		var env := pow(1.0 - p, 4.0)
		# Sharp attack click
		var click := 0.0
		if t < 0.002:
			click = (1.0 - t / 0.002) * 0.6
		# Two-tone pop (1200 + 1800 Hz)
		var s := sin(t * 1200.0 * TAU) * 0.3
		s += sin(t * 1800.0 * TAU) * 0.15
		s = s * env + click
		left_buf[i] = s
		right_buf[i] = s

	var data := PackedByteArray()
	data.resize(num * 4)
	for i in num:
		_write_stereo(data, i, left_buf[i], right_buf[i])
	return _make_stream(data)
