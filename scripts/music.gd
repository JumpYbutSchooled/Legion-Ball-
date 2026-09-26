extends Node
## Background music, synthesized in code like the sound effects (scripts/sfx.gd), so
## there are no audio files to ship or license. Created by scripts/services.gd as
## /root/Music.
##   "menu": deep space. Slow swelling minor-9 pads, a sub drone, a whisper of cosmic
##           wind and sparse echoing star pings. ~34 s loop.
##   "game": breakcore. 174 BPM chopped breaks with snare rolls and stutters, a growling
##           reese bass ducked by the kick, and a fast arp over the second half. 8 bars.
## Picks the track itself: the game track while an arena is loaded (it has
## request_hit), the menu track everywhere else. Crossfades between them.
## Built once on a worker thread at startup (a few seconds); silent until then.
## Volume: Settings "music_volume" (0..1).

const RATE := 22050
const FADE_TIME := 1.6
## Seed for the break chops, so the loop is the same every time.
const SEED := 1742

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
## Which of the two players is the live one.
var _live := 0
var _track := ""
var _enabled := true
var _task := -1
var _check := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_task = WorkerThreadPool.add_task(_build_all)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _process(delta: float) -> void:
	if not _enabled:
		return
	_check -= delta
	if _check <= 0.0:
		_check = 0.4
		var scene := get_tree().current_scene
		_select("game" if scene and scene.has_method("request_hit") else "menu")
	# Crossfade: the live player rises to the set volume, the other sinks and stops.
	var goal := _volume_db()
	for i in _players.size():
		var p := _players[i]
		if i == _live and p.playing:
			p.volume_db = move_toward(p.volume_db, goal, delta * 80.0 / FADE_TIME)
		elif p.playing:
			p.volume_db = move_toward(p.volume_db, -80.0, delta * 80.0 / FADE_TIME)
			if p.volume_db <= -79.0:
				p.stop()


func _select(track: String) -> void:
	if track == _track or not _streams.has(track):
		return
	_track = track
	_live = 1 - _live
	var p := _players[_live]
	p.stream = _streams[track]
	p.volume_db = -40.0
	p.play()


func _volume_db() -> float:
	var settings := get_tree().root.get_node_or_null("Settings")
	var v: float = settings.call("get_value", "music_volume") if settings else 0.6
	return linear_to_db(maxf(v, 0.0001)) - 6.0 if v > 0.0 else -80.0


# --- Synthesis -------------------------------------------------------------------------

func _build_all() -> void:
	var s := {}
	s["menu"] = _loop_wav(_deep_space())
	s["game"] = _loop_wav(_breakcore())
	_set_streams.call_deferred(s)


func _set_streams(s: Dictionary) -> void:
	_streams = s
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _loop_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = samples.size()
	return w


static func _midi(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## Adds `src` into `dst` starting at `at`, wrapping past the end back to the start, so
## tails that ring past the loop point land at its beginning (a seamless loop).
static func _add_wrapped(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain := 1.0) -> void:
	var n := dst.size()
	for i in src.size():
		var k := (at + i) % n
		dst[k] += src[i] * gain


## Soft-clips everything into range and normalises to `peak`.
static func _master(buf: PackedFloat32Array, drive: float, peak: float) -> PackedFloat32Array:
	var top := 0.0001
	for i in buf.size():
		buf[i] = tanh(buf[i] * drive)
		top = maxf(top, absf(buf[i]))
	var k := peak / top
	for i in buf.size():
		buf[i] *= k
	return buf


## A feedback echo that wraps round the loop (so the echoes of the end continue at the start).
static func _echo(buf: PackedFloat32Array, seconds: float, feedback: float, mix: float) -> void:
	var d := int(seconds * RATE)
	var n := buf.size()
	var wet := PackedFloat32Array()
	wet.resize(n)
	# Two passes round the loop so the feedback settles across the seam.
	for pass_i in 2:
		for i in n:
			var j := (i - d + n) % n
			wet[i] = buf[j] * mix + wet[j] * feedback
	for i in n:
		buf[i] += wet[i]


# --- Deep space (menu) ------------------------------------------------------------------

func _deep_space() -> PackedFloat32Array:
	var chord_len := 8.5
	# i - VI - III - VII in D minor, voiced as wide minor-9 / major-7 clouds (MIDI notes).
	var chords := [
		[38, 50, 57, 60, 64, 65],   # Dm9
		[34, 46, 53, 57, 60, 62],   # Bbmaj9
		[41, 53, 57, 60, 64, 67],   # Fmaj9
		[36, 48, 55, 59, 62, 64],   # Cmaj9-ish
	]
	var n := int(chord_len * chords.size() * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	# Pads are dark and filtered, so they're rendered at half rate (half the work) and
	# stretched back up.
	var half := PackedFloat32Array()
	half.resize(n >> 1)
	for c in chords.size():
		var start := int(c * chord_len * RATE / 2.0)
		for note in chords[c]:
			# Each note swells in slowly and hangs on past the next chord (wrapped).
			var voice := _pad_voice(_midi(note), chord_len + 4.0, 3.2, 4.5, 0.35 if note < 45 else 0.16, rng)
			_add_wrapped(half, voice, start + int(rng.randf_range(0.0, 0.3) * RATE))
	for i in n:
		var x := i * 0.5
		var a := int(x)
		buf[i] = lerpf(half[a % half.size()], half[(a + 1) % half.size()], x - a)
	# Star pings: sparse high sine bells from the scale, echoing away.
	var scale := [74, 76, 77, 79, 81, 84, 86, 88, 89]
	var pings := PackedFloat32Array()
	pings.resize(n)
	var t := 0.8
	while t < n / float(RATE):
		var bell := _bell(_midi(scale[rng.randi() % scale.size()]), 2.6)
		_add_wrapped(pings, bell, int(t * RATE), rng.randf_range(0.05, 0.12))
		t += rng.randf_range(1.2, 3.8)
	_echo(pings, 0.62, 0.55, 0.7)
	for i in n:
		buf[i] += pings[i]
	# Cosmic wind: filtered noise, its brightness and level drifting (periodic over the loop).
	var low := 0.0
	var band := 0.0
	for i in n:
		var ph := float(i) / n
		var lfo := 0.5 + 0.5 * sin(TAU * ph * 3.0)
		var cutoff := lerpf(0.004, 0.03, lfo)
		low += cutoff * (rng.randf_range(-1.0, 1.0) - low)
		band += 0.02 * (low - band)
		buf[i] += (low - band) * lerpf(0.5, 1.6, 0.5 + 0.5 * sin(TAU * ph * 2.0 + 1.0))
	return _master(buf, 1.2, 0.8)


## One pad note, at half rate: three detuned saws through a soft low-pass that opens as
## it swells.
func _pad_voice(freq: float, length: float, attack: float, release: float, gain: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var rate := RATE / 2.0
	var count := int(length * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var p1 := rng.randf()
	var p2 := rng.randf()
	var p3 := rng.randf()
	var lp := 0.0
	var lp2 := 0.0
	for i in count:
		var t := float(i) / rate
		var env := minf(t / attack, 1.0) * clampf((length - t) / release, 0.0, 1.0)
		env = env * env * (3.0 - 2.0 * env)
		p1 = fmod(p1 + freq / rate, 1.0)
		p2 = fmod(p2 + freq * 1.0035 / rate, 1.0)
		p3 = fmod(p3 + freq * 0.9968 / rate, 1.0)
		var s := p1 + p2 + p3 - 1.5
		var cutoff := lerpf(0.02, 0.12, env) * clampf(700.0 / freq, 0.3, 1.5)
		lp += cutoff * (s / 1.5 - lp)
		lp2 += cutoff * (lp - lp2)
		out[i] = lp2 * env * gain
	return out


## A soft bell: a sine and a quiet inharmonic partial with a long decay.
func _bell(freq: float, length: float) -> PackedFloat32Array:
	var count := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / RATE
		var env := minf(t / 0.004, 1.0) * exp(-t * 2.2)
		out[i] = (sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.76 * t) * exp(-t * 4.0)) * env
	return out


# --- Breakcore (game) ------------------------------------------------------------------

func _breakcore() -> PackedFloat32Array:
	var bpm := 174.0
	var step := 60.0 / bpm / 4.0  # A 16th note, in seconds.
	var bars := 8
	var steps := bars * 16
	var n := int(steps * step * RATE)
	var drums := PackedFloat32Array()
	drums.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var kick := _kick()
	var snare := _snare(0.2)
	var ghost := _snare(0.09)
	var hat := _hat(0.035)
	var open_hat := _hat(0.16)
	# An amen-flavoured two-bar break: K kick, S snare, g ghost snare, h hat, o open hat.
	var pattern := [
		"K.h.S.hgh.KKS.hg",
		"h.K.S.hgh.K.S.og",
	]
	# How each 16th of the envelope is ducked by kicks (for the bass sidechain).
	var duck := PackedFloat32Array()
	duck.resize(steps)
	duck.fill(1.0)
	for s in steps:
		var bar := s >> 4
		var pos := s % 16
		var ch: String = pattern[bar % 2][pos]
		var at := int(s * step * RATE)
		# The last bar of every four is a fill: snare rolls speeding up and stutters.
		var fill := bar % 4 == 3 and pos >= 8
		if fill:
			var rolls := 2 if pos < 12 else 4
			if pos >= 14:
				rolls = 8
			for r in rolls:
				var sub := at + int(r * step / rolls * RATE)
				_add_wrapped(drums, snare if r == 0 else ghost, sub, lerpf(0.5, 1.0, float(r) / rolls))
			if pos == 8 or pos == 12:
				_add_wrapped(drums, kick, at, 0.9)
				duck[s] = 0.0
			continue
		match ch:
			"K":
				_add_wrapped(drums, kick, at)
				duck[s] = 0.0
			"S":
				_add_wrapped(drums, snare, at)
			"g":
				_add_wrapped(drums, ghost, at, 0.45)
			"h":
				_add_wrapped(drums, hat, at, 0.35)
			"o":
				_add_wrapped(drums, open_hat, at, 0.3)
		# Random chops: now and then a hit is doubled into a stutter.
		if ch != "." and rng.randf() < 0.18:
			var hit := snare if ch == "S" else (kick if ch == "K" else hat)
			_add_wrapped(drums, hit, at + int(step * 0.5 * RATE), 0.55)
		# The odd 32nd hat.
		if rng.randf() < 0.25:
			_add_wrapped(drums, hat, at + int(step * 0.5 * RATE), 0.2)

	# Reese bass: two detuned saws through a moving low-pass, ducked hard after kicks.
	var roots := [38, 38, 41, 36, 38, 38, 34, 36]  # One root per bar (D minor).
	var bass := PackedFloat32Array()
	bass.resize(n)
	var ph1 := 0.0
	var ph2 := 0.0
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := int(t / step) % steps
		var bar := s >> 4
		var freq := _midi(roots[bar] - 12.0)
		# Octave jumps on the off-beats for bounce.
		if s % 4 == 3:
			freq *= 2.0
		ph1 = fmod(ph1 + freq / RATE, 1.0)
		ph2 = fmod(ph2 + freq * 1.012 / RATE, 1.0)
		var saw := (ph1 * 2.0 - 1.0) + (ph2 * 2.0 - 1.0)
		var wob := 0.5 + 0.5 * sin(TAU * float(i) / n * bars * 2.0)
		var cutoff := lerpf(0.02, 0.09, wob)
		lp += cutoff * (saw - lp)
		lp2 += cutoff * (lp - lp2)
		# Sidechain: after a kick the bass swells back in over the 16th.
		var in_step := fmod(t, step) / step
		var gate := 1.0 if duck[s] > 0.5 else smoothstep(0.0, 1.0, in_step)
		bass[i] = tanh(lp2 * 2.2) * 0.42 * gate

	# Arp: fast, bright 16ths over the second half of the loop.
	var arp := PackedFloat32Array()
	arp.resize(n)
	var arp_notes := [62, 65, 69, 72, 74, 72, 69, 65]
	for s in range(steps >> 1, steps):
		var bar := s >> 4
		var note: float = arp_notes[s % arp_notes.size()] + (roots[bar] - 38)
		_add_wrapped(arp, _pluck(_midi(note), step * 1.8), int(s * step * RATE), 0.12)
	_echo(arp, step * 3.0, 0.35, 0.5)

	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = drums[i] * 0.9 + bass[i] + arp[i]
	return _master(out, 1.6, 0.85)


func _kick() -> PackedFloat32Array:
	var count := int(0.28 * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		phase += TAU * lerpf(48.0, 170.0, exp(-t * 28.0)) / RATE
		var click := exp(-t * 400.0) * 0.6
		out[i] = tanh((sin(phase) * exp(-t * 9.0) + click) * 1.8)
	return out


func _snare(length: float) -> PackedFloat32Array:
	var count := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = count
	var hp := 0.0
	var prev := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		hp = 0.7 * (hp + noise - prev)
		prev = noise
		var body := sin(TAU * 190.0 * t) * exp(-t * 30.0)
		out[i] = (hp * 0.9 + body * 0.6) * exp(-t * 4.0 / length)
	return out


func _hat(length: float) -> PackedFloat32Array:
	var count := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = count + 7
	var prev := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		out[i] = (noise - prev) * 0.5 * exp(-t * 3.5 / length)
		prev = noise
	return out


## A bright square-ish pluck with a quick decay.
func _pluck(freq: float, length: float) -> PackedFloat32Array:
	var count := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	var lp := 0.0
	for i in count:
		var t := float(i) / RATE
		phase = fmod(phase + freq / RATE, 1.0)
		var sq := 1.0 if phase < 0.5 else -1.0
		lp += lerpf(0.5, 0.05, minf(t / length, 1.0)) * (sq - lp)
		out[i] = lp * exp(-t * 6.0 / length)
	return out
