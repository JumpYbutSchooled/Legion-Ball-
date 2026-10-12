extends Node
## Background music, synthesized in code like the sound effects (scripts/sfx.gd), so
## there are no audio files to ship or license. Created by scripts/services.gd as
## /root/Music.
##   "menu": deep space. Slow swelling minor-9 pads, a sub drone, a whisper of cosmic
##           wind and sparse echoing star pings. ~34 s loop.
##   "game": breakcore, a whole song: 36 bars at 174 BPM (~50 s) in sections (intro, theme,
##           a higher B melody, a breakdown, the theme again, outro), with a gliding lead
##           melody over chopped breaks, a reese bass ducked by the kick, arps and pads.
## Picks the track itself: the game track while an arena is loaded (it has
## request_hit), the menu track everywhere else. Crossfades between them.
## Built once on a worker thread at startup (a few seconds); silent until then.
## Volume: Settings "music_volume" (0..1).

## CD quality (was 22.05 kHz: duller, and the saws aliased).
const RATE := 44100
const Graphics := preload("res://scripts/graphics.gd")
const SoundCache := preload("res://scripts/sound_cache.gd")
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
## Identifies this build of the music in the disk cache (scripts/sound_cache.gd).
var _key := ""
var _check := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	Graphics.ensure_buses()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	# Built before (this version)? Load it; otherwise build it, then keep it.
	_key = SoundCache.key_for(get_script(), RATE)
	var cached := SoundCache.load_set("music", _key)
	if cached.has("game"):
		_streams = cached
		return
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
	# The menu's music can start while the long game song is still being made.
	_set_streams.call_deferred(s.duplicate())
	s["game"] = _loop_wav(_breakcore())
	SoundCache.save_set("music", _key, s)
	_set_streams.call_deferred(s)


## Called twice: with the menu track, then with both.
func _set_streams(s: Dictionary) -> void:
	_streams = s
	if _task >= 0 and s.has("game"):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## The loop as a stereo WAV, widened: the sides carry the difference between the sound
## and a 13 ms echo of itself (wrapping round the loop), so it fills the room instead of
## sitting in the middle, and still sums back to the original in mono.
func _loop_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	var d := int(0.013 * RATE)
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		var x := samples[i]
		var side := (x - samples[(i - d + n) % n]) * 0.32
		data.encode_s16(i * 4, int(clampf(x * 0.92 + side, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(x * 0.92 - side, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = true
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
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
		var cutoff := _k(lerpf(0.004, 0.03, lfo))
		low += cutoff * (rng.randf_range(-1.0, 1.0) - low) * 1.41
		band += _k(0.02) * (low - band)
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
# A whole song, not a short loop: 36 bars at 174 BPM (about 50 seconds) in D minor, in
# sections, with a lead melody over the top. It still loops seamlessly (the outro runs
# back into the intro).
#   intro (4)  pads, an arp and hats, a riser into...
#   A     (8)  the full break, reese bass, the lead's main theme (Dm  Bb  F  C)
#   B     (8)  a new, higher melody over Dm  Bb  Gm  A
#   break (4)  no drums: pads, the lead in long notes, a riser back in
#   A2    (8)  the theme again, busier
#   outro (4)  the B chords, the melody resolving, back round to the intro

const BPM := 174.0
const PROG_A := [[38, [62, 65, 69]], [34, [58, 62, 65]], [41, [60, 65, 69]], [36, [60, 64, 67]]]
const PROG_B := [[38, [62, 65, 69]], [34, [58, 62, 65]], [43, [62, 67, 70]], [45, [61, 64, 69]]]
## The lead, a bar at a time: [MIDI note (0 = rest), length in 16ths], adding up to 16.
const THEME := [
	[[74, 4], [77, 2], [81, 2], [79, 3], [77, 1], [76, 2], [74, 2]],
	[[77, 4], [74, 2], [70, 2], [72, 4], [74, 4]],
	[[81, 4], [84, 2], [81, 2], [79, 3], [77, 1], [79, 4]],
	[[76, 6], [79, 2], [77, 4], [76, 4]],
]
const THEME_END := [[76, 2], [77, 2], [79, 2], [81, 10]]
const MELODY_B := [
	[[81, 2], [81, 2], [86, 4], [84, 2], [81, 2], [77, 4]],
	[[82, 6], [81, 2], [77, 4], [74, 4]],
	[[79, 2], [82, 2], [86, 4], [84, 2], [82, 2], [79, 4]],
	[[81, 4], [85, 4], [88, 8]],
]
const MELODY_B_END := [[85, 2], [88, 2], [85, 2], [81, 2], [76, 8]]
const BREAK_LINE := [[[74, 16]], [[72, 8], [70, 8]], [[69, 16]], [[67, 8], [72, 8]]]
const REST := [[0, 16]]


## The song's bars, in order: each {root, chord, drums, bass, lead (one bar of notes),
## arp, pad, riser, fill}.
func _song() -> Array:
	var bars := []
	var add := func(prog: Array, count: int, drums: String, bass: String, lead: Array, arp: bool, pad: bool) -> void:
		for i in count:
			var c: Array = prog[i % 4]
			bars.append({"root": c[0], "chord": c[1], "drums": drums, "bass": bass,
				"lead": lead[i] if i < lead.size() else REST, "arp": arp, "pad": pad, "riser": false, "fill": i % 4 == 3})
	add.call(PROG_A, 4, "hats", "off", [], true, true)
	add.call(PROG_A, 8, "full", "on", THEME + THEME.slice(0, 3) + [THEME_END], false, false)
	add.call(PROG_B, 8, "full", "on", MELODY_B + MELODY_B.slice(0, 3) + [MELODY_B_END], true, false)
	add.call(PROG_A, 4, "none", "soft", BREAK_LINE, false, true)
	add.call(PROG_A, 8, "full", "on", THEME + THEME.slice(0, 3) + [THEME_END], true, false)
	add.call(PROG_B, 4, "half", "on", MELODY_B.slice(0, 3) + [MELODY_B_END], true, true)
	# Risers in the bar before each drop.
	bars[3]["riser"] = true
	bars[23]["riser"] = true
	return bars


func _breakcore() -> PackedFloat32Array:
	var step := 60.0 / BPM / 4.0  # A 16th note, in seconds.
	var song := _song()
	var steps := song.size() * 16
	var n := int(steps * step * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	# Drums.
	var drums := PackedFloat32Array()
	drums.resize(n)
	var kick := _kick()
	var snare := _snare(0.2)
	var ghost := _snare(0.09)
	var hat := _hat(0.035)
	var open_hat := _hat(0.16)
	# An amen-flavoured two-bar break: K kick, S snare, g ghost snare, h hat, o open hat.
	var pattern := ["K.h.S.hgh.KKS.hg", "h.K.S.hgh.K.S.og"]
	var half_pattern := "K.h.h.h.S.h.h.hg"
	var duck := PackedFloat32Array()
	duck.resize(steps)
	duck.fill(1.0)
	for s in steps:
		var bar_i := s >> 4
		var bar: Dictionary = song[bar_i]
		var pos := s % 16
		var at := int(s * step * RATE)
		var mode: String = bar["drums"]
		if mode == "none":
			continue
		if mode == "hats":
			if pos % 2 == 0:
				_add_wrapped(drums, hat, at, 0.3 if pos % 4 == 0 else 0.18)
			if pos == 14:
				_add_wrapped(drums, open_hat, at, 0.22)
			continue
		var ch: String = (half_pattern if mode == "half" else pattern[bar_i % 2])[pos]
		# Fills on the last bar of every four: snare rolls speeding up.
		if mode == "full" and bar["fill"] and pos >= 8:
			var rolls := 2 if pos < 12 else (4 if pos < 14 else 8)
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
		if mode == "full":
			if ch != "." and rng.randf() < 0.16:
				var hit := snare if ch == "S" else (kick if ch == "K" else hat)
				_add_wrapped(drums, hit, at + int(step * 0.5 * RATE), 0.5)
			if rng.randf() < 0.22:
				_add_wrapped(drums, hat, at + int(step * 0.5 * RATE), 0.18)

	# Reese bass: two detuned saws through a moving low-pass, ducked after kicks. In the
	# breakdown a soft sustained sine instead.
	var bass := PackedFloat32Array()
	bass.resize(n)
	var ph1 := 0.0
	var ph2 := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var bar_len := 16.0 * step
	for i in n:
		var t := float(i) / RATE
		var s := int(t / step) % steps
		var bar: Dictionary = song[s >> 4]
		var mode: String = bar["bass"]
		if mode == "off":
			lp *= 0.999
			lp2 *= 0.999
			bass[i] = lp2 * 0.3
			continue
		var freq := _midi(float(bar["root"]) - 12.0)
		if mode == "on" and s % 4 == 3:
			freq *= 2.0  # octave jumps on the off-beats for bounce
		ph1 = fmod(ph1 + freq / RATE, 1.0)
		ph2 = fmod(ph2 + freq * 1.012 / RATE, 1.0)
		if mode == "soft":
			bass[i] = sin(ph1 * TAU) * 0.28 * minf(fmod(t, bar_len) * 4.0, 1.0)
			continue
		var saw := (ph1 * 2.0 - 1.0) + (ph2 * 2.0 - 1.0)
		var wob := 0.5 + 0.5 * sin(TAU * t / bar_len * 0.5)
		var cutoff := _k(lerpf(0.02, 0.09, wob))
		lp += cutoff * (saw - lp)
		lp2 += cutoff * (lp - lp2)
		var in_step := fmod(t, step) / step
		var gate := 1.0 if duck[s] > 0.5 else smoothstep(0.0, 1.0, in_step)
		bass[i] = tanh(lp2 * 2.2) * 0.4 * gate

	# Arp: quick plucks running up and down the chord.
	var arp := PackedFloat32Array()
	arp.resize(n)
	var shape := [0, 1, 2, 3, 2, 1, 0, 1]
	for s in steps:
		var bar: Dictionary = song[s >> 4]
		if not bar["arp"]:
			continue
		var chord: Array = bar["chord"]
		var k: int = shape[s % shape.size()]
		var note: float = chord[k % 3] + 12 * (k / 3)
		_add_wrapped(arp, _pluck(_midi(note), step * 1.8), int(s * step * RATE), 0.1)
	_echo(arp, step * 3.0, 0.35, 0.45)

	# Pads under the intro, the breakdown and the outro.
	var half := PackedFloat32Array()
	half.resize(n >> 1)
	for b in song.size():
		var bar: Dictionary = song[b]
		if not bar["pad"]:
			continue
		var start := int(b * bar_len * RATE / 2.0)
		for note in bar["chord"]:
			var voice := _pad_voice(_midi(float(note) - 12.0), bar_len + 1.5, 0.4, 1.2, 0.13, rng)
			_add_wrapped(half, voice, start)
	var pads := PackedFloat32Array()
	pads.resize(n)
	for i in n:
		var x := i * 0.5
		var a := int(x)
		pads[i] = lerpf(half[a % half.size()], half[(a + 1) % half.size()], x - a)

	# The lead.
	var notes := []  # [start sample, length in samples, MIDI note]
	for b in song.size():
		var at16 := 0
		for nt in song[b]["lead"]:
			if int(nt[0]) > 0:
				notes.append([int((b * 16 + at16) * step * RATE), int(int(nt[1]) * step * RATE), int(nt[0])])
			at16 += int(nt[1])
	var lead := _lead(notes, n)
	_echo(lead, step * 3.0, 0.3, 0.32)

	# Risers: noise sweeping up into the drops.
	var riser := PackedFloat32Array()
	riser.resize(n)
	for b in song.size():
		if song[b]["riser"]:
			var start := int(b * bar_len * RATE)
			var len_s := int(bar_len * RATE)
			var lo := 0.0
			var lo2 := 0.0
			for j in len_s:
				var u := float(j) / len_s
				var c := _k(lerpf(0.01, 0.4, u * u))
				lo += c * (rng.randf_range(-1.0, 1.0) - lo)
				lo2 += c * (lo - lo2)
				riser[(start + j) % n] += (lo - lo2) * u * u * 0.9

	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = drums[i] * 0.9 + bass[i] + arp[i] + pads[i] * 0.8 + lead[i] + riser[i]
	return _master(out, 1.5, 0.85)


## The lead synth: three detuned saws (smoothed so they don't alias) and a sub, gliding
## between notes, a vibrato that blooms on longer notes, and a filter that opens bright
## on each note and settles. One continuous voice, so legato notes slide into each other.
func _lead(notes: Array, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var phases := [0.0, 0.33, 0.66]
	var detune := [1.0, 1.007, 0.9935]
	var sub := 0.0
	var freq := 440.0
	var amp := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var glide := _k(0.004)
	var attack := _k(0.01)
	var release := _k(0.0025)
	var ni := 0
	for i in n:
		# Which note (if any) is playing here.
		while ni < notes.size() and i >= int(notes[ni][0]) + int(notes[ni][1]):
			ni += 1
		var on := ni < notes.size() and i >= int(notes[ni][0])
		var since := 0.0
		if on:
			var target := _midi(float(notes[ni][2]))
			since = float(i - int(notes[ni][0])) / RATE
			freq += (target - freq) * glide
		amp += ((1.0 if on else 0.0) - amp) * (attack if on else release)
		if amp < 0.0005 and not on:
			out[i] = 0.0
			continue
		var vib := 1.0 + 0.005 * sin(TAU * 5.5 * since) * smoothstep(0.12, 0.35, since)
		var f := freq * vib
		var s := 0.0
		for v in 3:
			var dt: float = f * detune[v] / RATE
			var ph: float = fmod(phases[v] + dt, 1.0)
			phases[v] = ph
			s += 2.0 * ph - 1.0 - _blep(ph, dt)
		s /= 3.0
		sub = fmod(sub + f * 0.5 / RATE, 1.0)
		s += sin(sub * TAU) * 0.35
		var cutoff := _k(0.07 + 0.22 * exp(-since * 7.0))
		lp += cutoff * (s - lp)
		lp2 += cutoff * (lp - lp2)
		out[i] = lp2 * amp * 0.34
	return out


## Smooths a saw's jump (PolyBLEP), so the lead doesn't buzz with aliasing.
static func _blep(ph: float, dt: float) -> float:
	if ph < dt:
		var x := ph / dt
		return x + x - x * x - 1.0
	if ph > 1.0 - dt:
		var x := (ph - 1.0) / dt
		return x * x + x + x + 1.0
	return 0.0


## A one-pole filter strength tuned at 22.05 kHz, at this sample rate.
static func _k(c: float) -> float:
	return 1.0 - pow(1.0 - clampf(c, 0.0, 0.999), 22050.0 / RATE)


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
		lp += _k(lerpf(0.5, 0.05, minf(t / length, 1.0))) * (sq - lp)
		out[i] = lp * exp(-t * 6.0 / length)
	return out
