## Sound Generator — creates procedural WAV AudioStreams for the air hockey game.
## No external files needed.
extends RefCounted
class_name SoundGen

static func make_hit_sound(freq: float = 800.0, duration: float = 0.08) -> AudioStreamWAV:
	var sample_rate := 22050
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)  # 16-bit mono

	for i in num_samples:
		var t := float(i) / sample_rate
		var envelope := 1.0 - (float(i) / num_samples)
		envelope *= envelope  # exponential decay
		var sample := sin(t * freq * TAU) * envelope
		# Add a click transient at the start
		if i < int(sample_rate * 0.005):
			sample += (1.0 - float(i) / (sample_rate * 0.005)) * 0.8
		sample = clampf(sample, -1.0, 1.0)
		var val := int(sample * 32767.0)
		data[i * 2]     = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


static func make_wall_bounce_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.06
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in num_samples:
		var t := float(i) / sample_rate
		var envelope := 1.0 - (float(i) / num_samples)
		envelope = envelope * envelope * envelope
		# Low thud + high click
		var sample := sin(t * 300.0 * TAU) * envelope * 0.6
		sample += sin(t * 1200.0 * TAU) * envelope * envelope * 0.4
		# Noise burst at start
		if i < int(sample_rate * 0.003):
			sample += randf_range(-0.5, 0.5) * (1.0 - float(i) / (sample_rate * 0.003))
		sample = clampf(sample, -1.0, 1.0)
		var val := int(sample * 32767.0)
		data[i * 2]     = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


static func make_goal_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.5
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in num_samples:
		var t := float(i) / sample_rate
		var progress := float(i) / num_samples
		var envelope := (1.0 - progress) * (1.0 - progress)
		# Rising pitch fanfare
		var freq := 440.0 + progress * 660.0
		var sample := sin(t * freq * TAU) * envelope * 0.5
		# Harmonic
		sample += sin(t * freq * 2.0 * TAU) * envelope * 0.25
		# Sub bass hit
		sample += sin(t * 110.0 * TAU) * envelope * envelope * 0.3
		sample = clampf(sample, -1.0, 1.0)
		var val := int(sample * 32767.0)
		data[i * 2]     = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


static func make_countdown_beep(high: bool = false) -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.12
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var freq := 1200.0 if high else 800.0

	for i in num_samples:
		var t := float(i) / sample_rate
		var envelope := 1.0 - (float(i) / num_samples)
		var sample := sin(t * freq * TAU) * envelope * 0.4
		sample += sin(t * freq * 1.5 * TAU) * envelope * 0.15
		sample = clampf(sample, -1.0, 1.0)
		var val := int(sample * 32767.0)
		data[i * 2]     = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


static func make_game_over_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.8
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in num_samples:
		var t := float(i) / sample_rate
		var progress := float(i) / num_samples
		var envelope := (1.0 - progress)
		envelope *= envelope
		# Three-note chord (major triad)
		var sample := sin(t * 523.25 * TAU) * 0.35  # C5
		sample += sin(t * 659.25 * TAU) * 0.25      # E5
		sample += sin(t * 783.99 * TAU) * 0.2       # G5
		sample *= envelope
		# Victory shimmer
		sample += sin(t * 1046.5 * TAU) * envelope * envelope * 0.15
		sample = clampf(sample, -1.0, 1.0)
		var val := int(sample * 32767.0)
		data[i * 2]     = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


static func make_menu_click_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.05
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in num_samples:
		var t := float(i) / sample_rate
		var envelope := 1.0 - (float(i) / num_samples)
		envelope *= envelope
		var sample := sin(t * 1000.0 * TAU) * envelope * 0.5
		sample = clampf(sample, -1.0, 1.0)
		var val := int(sample * 32767.0)
		data[i * 2]     = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
