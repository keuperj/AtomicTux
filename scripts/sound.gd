class_name TuxSound
extends AudioStreamPlayer
## Tiny synthesized effects: no external audio dependencies.
var enabled := true

func play_effect(kind: String) -> void:
	if not enabled:
		return
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = 22050
	var duration := 0.28 if kind == "boom" else 0.12
	var count := int(duration * sample.mix_rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		var frequency := lerpf(140.0, 35.0, t) if kind == "boom" else lerpf(540.0, 1080.0, t)
		phase += TAU * frequency / sample.mix_rate
		var value := sin(phase)
		if kind == "boom":
			value = value * 0.55 + randf_range(-0.45, 0.45)
		var pcm := int(value * pow(1.0 - t, 2.0) * 12500.0)
		bytes.encode_s16(i * 2, pcm)
	sample.data = bytes
	stream = sample
	play()
