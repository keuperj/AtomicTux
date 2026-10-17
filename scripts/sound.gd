class_name TuxSound
extends AudioStreamPlayer
## Cached, layered foley: soft impacts, low rumble, glass and air.
const RATE := 44100
const VARIANTS := 3
const VOICES := 8
var enabled := true:
	set(value):
		enabled = value
		if not value:
			for voice in voices: voice.stop()
var samples: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0
var last_boom_ms := -1000
var random := RandomNumberGenerator.new()

func _ready() -> void:
	random.randomize()
	for kind in ["place", "boom", "pickup", "shield"]:
		samples[kind] = []
		for variant in VARIANTS:
			samples[kind].append(_synthesize(kind, variant))
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -9.0
		add_child(voice)
		voices.append(voice)

func play_effect(kind: String) -> void:
	if not enabled or not samples.has(kind) or voices.is_empty(): return
	if kind == "boom":
		# A chain reaction is one impact, not a wall of clipped identical sounds.
		var now := Time.get_ticks_msec()
		if now - last_boom_ms < 65: return
		last_boom_ms = now
	var voice := voices[next_voice]
	for candidate in voices:
		if not candidate.playing:
			voice = candidate
			break
	next_voice = (next_voice + 1) % VOICES
	voice.stream = samples[kind][random.randi_range(0, VARIANTS - 1)]
	voice.play()

func _synthesize(kind: String, variant: int) -> AudioStreamWAV:
	var duration: float = {"place":0.23, "boom":0.95, "pickup":0.58, "shield":0.65}[kind]
	var count := int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 7129 + variant * 173 + kind.hash()
	var low := 0.0
	var body := 0.0
	var pitch := 1.0 + (variant - 1) * 0.045
	for i in count:
		var time := float(i) / RATE
		var white := noise.randf_range(-1, 1)
		low = lerpf(low, white, 0.035)
		body = lerpf(body, white, 0.23)
		var value := 0.0
		match kind:
			"place":
				# A padded, hollow object landing, with a short surface rustle.
				value = 0.52 * sin(TAU * 165 * pitch * time) * exp(-time * 29)
				value += 0.20 * sin(TAU * 287 * pitch * time) * exp(-time * 46)
				value += body * 0.45 * exp(-time * 60)
			"boom":
				# Rounded pressure transient, rolling bass, then scattered debris.
				value = low * 3.2 * exp(-time * 5.5)
				value += body * 0.48 * exp(-time * 18)
				value += 0.45 * sin(TAU * 57 * pitch * time) * exp(-time * 8)
				value += 0.15 * sin(TAU * 91 * pitch * time) * exp(-time * 12)
				value += body * 0.22 * exp(-time * 6) * pow(sin(time * 47), 8)
			"pickup":
				# Small glass/ceramic resonance rather than an ascending beep.
				value = 0.28 * sin(TAU * 880 * pitch * time) * exp(-time * 12)
				value += 0.12 * sin(TAU * 1433 * pitch * time) * exp(-time * 18)
				value += 0.08 * sin(TAU * 2371 * pitch * time) * exp(-time * 29)
				value += body * 0.18 * exp(-time * 80)
			"shield":
				# A cushioned impact with a breathy release.
				value = low * 2.4 * exp(-time * 7)
				value += body * 0.3 * sin(PI * minf(time / 0.4, 1)) * exp(-time * 5)
				value += 0.25 * sin(TAU * 210 * pitch * time) * exp(-time * 16)
		var attack := minf(time / 0.003, 1.0)
		var tail := clampf(float(count - 1 - i) / (RATE * 0.04), 0, 1)
		bytes.encode_s16(i * 2, int(tanh(value) * attack * tail * 26000))
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = RATE
	sample.data = bytes
	return sample
