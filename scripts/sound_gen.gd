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
# ║  HIT SOUND — soft rubbery thud (reduced stridency)       ║
# ╚═══════════════════════════════════════════════════════════╝
static func make_hit_sound(freq: float = 400.0, duration: float = 0.12) -> AudioStreamWAV:
	var num := int(SR * duration)
	var left_buf: Array[float] = []
	var right_buf: Array[float] = []
	left_buf.resize(num)
	right_buf.resize(num)

	for i in num:
		var t := float(i) / SR
		var p := float(i) / num
		# Softer decay curve
		var env := pow(1.0 - p, 2.5)
		# Gentle click transient (first 2ms, quieter)
		var click := 0.0
		if t < 0.002:
			click = (1.0 - t / 0.002) * 0.4
		# Lower, warmer tone — fewer high harmonics
		var phase := t * freq
		var s := sin(phase * TAU) * 0.45              # fundamental (lower freq)
		s += sin(phase * 2.0 * TAU) * 0.15            # 2nd harmonic (quieter)
		s += sin(phase * 1.5 * TAU) * 0.08            # perfect 5th (warmth)
		# NO sawtooth grit, NO detuned 3rd — keeps it soft
		s = s * env + click
		# Stereo spread
		left_buf[i] = s
		right_buf[i] = s * 0.9

	# Lighter reverb
	left_buf = _apply_reverb(left_buf, 0.15, 20.0)
	right_buf = _apply_reverb(right_buf, 0.15, 28.0)

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


# ╔═══════════════════════════════════════════════════════════╗
# ║  CROWD APPLAUSE — filtered noise swell simulating cheers  ║
# ╚═══════════════════════════════════════════════════════════╝
static func make_crowd_cheer_sound() -> AudioStreamWAV:
	var duration := 1.8
	var num := int(SR * duration)
	var left_buf: Array[float] = []
	var right_buf: Array[float] = []
	left_buf.resize(num)
	right_buf.resize(num)

	# Pre-generate random noise for deterministic left/right channels
	var noise_l: Array[float] = []
	var noise_r: Array[float] = []
	noise_l.resize(num)
	noise_r.resize(num)
	for i in num:
		noise_l[i] = randf_range(-1.0, 1.0)
		noise_r[i] = randf_range(-1.0, 1.0)

	for i in num:
		var t := float(i) / SR
		var p := float(i) / num
		# Swell envelope: rises then fades
		var env := 0.0
		if p < 0.15:
			env = p / 0.15  # rise
		elif p < 0.5:
			env = 1.0  # sustain
		else:
			env = pow(1.0 - (p - 0.5) / 0.5, 1.5)  # fade
		env *= 0.45

		# Filtered noise (simple moving average = low pass)
		var wl := 0.0
		var wr := 0.0
		var width := 8
		for j in range(-width, width + 1):
			var idx := clampi(i + j, 0, num - 1)
			wl += noise_l[idx]
			wr += noise_r[idx]
		wl /= float(width * 2 + 1)
		wr /= float(width * 2 + 1)

		# Add rhythmic clapping pattern (multiple frequencies)
		var clap_rate := 6.0  # claps per second
		var clap_phase := fmod(t * clap_rate, 1.0)
		var clap_env := maxf(0.0, 1.0 - clap_phase * 8.0) if clap_phase < 0.125 else 0.0
		var clap := randf_range(-0.3, 0.3) * clap_env

		# Add vocal "aah" undertone (sine cluster around 300-600Hz)
		var vocal := sin(t * 350.0 * TAU) * 0.06
		vocal += sin(t * 520.0 * TAU) * 0.04
		vocal += sin(t * 700.0 * TAU) * 0.03

		left_buf[i] = (wl + clap + vocal) * env
		right_buf[i] = (wr + clap * 0.8 + vocal) * env

	left_buf = _apply_reverb(left_buf, 0.3, 45.0)
	right_buf = _apply_reverb(right_buf, 0.3, 60.0)

	var data := PackedByteArray()
	data.resize(num * 4)
	for i in num:
		_write_stereo(data, i, left_buf[i], right_buf[i])
	return _make_stream(data)


# ╔═══════════════════════════════════════════════════════════╗
# ║  CROWD BOO — low rumble with descending "aww" tone        ║
# ╚═══════════════════════════════════════════════════════════╝
static func make_crowd_boo_sound() -> AudioStreamWAV:
	var duration := 1.5
	var num := int(SR * duration)
	var left_buf: Array[float] = []
	var right_buf: Array[float] = []
	left_buf.resize(num)
	right_buf.resize(num)

	var noise_l: Array[float] = []
	var noise_r: Array[float] = []
	noise_l.resize(num)
	noise_r.resize(num)
	for i in num:
		noise_l[i] = randf_range(-1.0, 1.0)
		noise_r[i] = randf_range(-1.0, 1.0)

	for i in num:
		var t := float(i) / SR
		var p := float(i) / num
		# Slow swell and fade
		var env := 0.0
		if p < 0.2:
			env = p / 0.2
		elif p < 0.6:
			env = 1.0
		else:
			env = pow(1.0 - (p - 0.6) / 0.4, 1.3)
		env *= 0.4

		# Low-pass filtered noise (wider kernel = darker)
		var wl := 0.0
		var wr := 0.0
		var width := 14
		for j in range(-width, width + 1):
			var idx := clampi(i + j, 0, num - 1)
			wl += noise_l[idx]
			wr += noise_r[idx]
		wl /= float(width * 2 + 1)
		wr /= float(width * 2 + 1)

		# Descending "ooooh" vocal tone (drops pitch over time)
		var vocal_freq := 280.0 - p * 100.0  # 280 → 180 Hz
		var vocal := sin(t * vocal_freq * TAU) * 0.12
		vocal += sin(t * vocal_freq * 1.5 * TAU) * 0.06  # 5th harmonic
		vocal += sin(t * vocal_freq * 0.5 * TAU) * 0.08  # sub octave

		left_buf[i] = (wl * 0.7 + vocal) * env
		right_buf[i] = (wr * 0.7 + vocal) * env

	left_buf = _apply_reverb(left_buf, 0.35, 55.0)
	right_buf = _apply_reverb(right_buf, 0.35, 70.0)

	var data := PackedByteArray()
	data.resize(num * 4)
	for i in num:
		_write_stereo(data, i, left_buf[i], right_buf[i])
	return _make_stream(data)


# ╔═══════════════════════════════════════════════════════════╗
# ║  PERFECT VICTORY — epic fanfare for 7-0 shutout           ║
# ╚═══════════════════════════════════════════════════════════╝
static func make_perfect_victory_sound() -> AudioStreamWAV:
	var duration := 2.5
	var num := int(SR * duration)
	var left_buf: Array[float] = []
	var right_buf: Array[float] = []
	left_buf.resize(num)
	right_buf.resize(num)

	for i in num:
		var t := float(i) / SR
		var p := float(i) / num
		# 3-phase envelope: brass fanfare → sustain → sparkle fadeout
		var env := 0.0
		if p < 0.05:
			env = p / 0.05  # attack
		elif p < 0.3:
			env = 1.0
		elif p < 0.6:
			env = 0.85 + sin(p * 12.0 * TAU) * 0.08  # vibrato sustain
		else:
			env = pow(1.0 - (p - 0.6) / 0.4, 1.8)  # sparkle fadeout

		# Rising 3-note arpeggio:  C5 → E5 → G5 → C6
		var freq := 523.25   # C5
		if p > 0.2 and p <= 0.4:
			freq = 659.25    # E5
		elif p > 0.4 and p <= 0.6:
			freq = 783.99    # G5
		elif p > 0.6:
			freq = 1046.5    # C6

		# Brass-like timbre (fundamental + harmonics + saw character)
		var phase := t * freq
		var s := sin(phase * TAU) * 0.3
		s += sin(phase * 2.0 * TAU) * 0.2
		s += sin(phase * 3.0 * TAU) * 0.12
		s += sin(phase * 4.0 * TAU) * 0.06
		s += _saw(phase) * 0.08  # brass edge
		s *= env

		# Triumphant sub bass pulse
		if p < 0.3:
			s += sin(t * 65.0 * TAU) * pow(1.0 - p / 0.3, 2.0) * 0.3

		# High sparkle arpeggios in the tail
		if p > 0.5:
			var sparkle_freq := 2093.0 + sin(t * 3.0 * TAU) * 500.0
			s += sin(t * sparkle_freq * TAU) * pow(env, 2.0) * 0.12

		# Crowd applause layered in (noise-based)
		var crowd := (randf_range(-0.15, 0.15))
		if p < 0.15:
			crowd *= p / 0.15
		elif p > 0.7:
			crowd *= pow(1.0 - (p - 0.7) / 0.3, 1.5)
		s += crowd

		left_buf[i] = s
		right_buf[i] = s * 0.85 + sin(t * freq * 1.002 * TAU) * env * 0.05  # chorus

	left_buf = _apply_reverb(left_buf, 0.4, 70.0)
	right_buf = _apply_reverb(right_buf, 0.4, 90.0)

	var data := PackedByteArray()
	data.resize(num * 4)
	for i in num:
		_write_stereo(data, i, left_buf[i], right_buf[i])
	return _make_stream(data)