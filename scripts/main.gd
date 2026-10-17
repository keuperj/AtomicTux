extends Node2D

const Arena = preload("res://scripts/arena.gd")
const Bot = preload("res://scripts/bot.gd")
const Sound = preload("res://scripts/sound.gd")
const TUX = preload("res://assets/art/tux.png")
const MOVE_CENTER := Vector2(1120, 580)
const BOMB_CENTER := Vector2(150, 580)
const ICONS := {
	"bomb": preload("res://assets/icons/bomb.svg"),
	"fire": preload("res://assets/icons/fire.svg"),
	"speed": preload("res://assets/icons/speed.svg"),
	"kick": preload("res://assets/icons/kick.svg")
}
const CELL := 52.0
const BOARD := Vector2(302, 142)
const INK := Color("091421")
const PANEL := Color("111f30")
const LINE := Color("263c50")
const WHITE := Color("edf6fc")
const MUTED := Color("829caf")
const TEAL := Color("68efcd")
const GOLD := Color("ffce74")
const COLORS := [Color("68efcd"), Color("ff8597"), Color("b09aff"), Color("ffc96a")]
const NAMES := ["YOU", "EMBER", "BYTE", "NOVA"]
var arena := Arena.new()
var sound := Sound.new()
var font: Font = ThemeDB.fallback_font
var mode := "menu"
var level := 1
var clock := 0.0
var accumulator := 0.0
var countdown := 0.0
var buttons: Array = []
var held: Dictionary = {}
var particles: Array = []
var shake := 0.0
var flash := ""
var flash_time := 0.0
var victories := 0
var rounds := 0
var muted := false
var best := 0
var match_seed := 0
var panel_styles: Dictionary = {}

func _ready() -> void:
	get_tree().quit_on_go_back = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(sound)
	_load_settings()
	arena.exploded.connect(_on_exploded)
	arena.collected.connect(_on_collected)
	arena.eliminated.connect(func(id):
		if id != 0:
			flash = NAMES[id] + " eliminated"
			flash_time = 1.8)
	get_viewport().size_changed.connect(_resize)
	_resize()
	arena.start(42813, level)
	_make_buttons()
	if "--smoke-game" in OS.get_cmdline_user_args():
		_start_match()
		countdown = 0.0

func _exit_tree() -> void:
	sound.stop()
	sound.stream = null

func _resize() -> void:
	var size := get_viewport_rect().size
	var ratio := minf(size.x / 1280.0, size.y / 800.0)
	scale = Vector2.ONE * ratio
	position = (size - Vector2(1280, 800) * ratio) / 2.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		held.clear()
		if mode == "playing":
			mode = "paused"
			_make_buttons()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_toggle_pause()

func _process(delta: float) -> void:
	clock += delta
	flash_time = maxf(0.0, flash_time - delta)
	shake = maxf(0.0, shake - delta * 30.0)
	for particle in particles:
		particle.life -= delta
		particle.pos += particle.velocity * delta
		particle.velocity *= 0.95
	particles = particles.filter(func(p): return p.life > 0.0)
	if mode == "playing":
		if countdown > 0.0:
			countdown = maxf(0.0, countdown - delta)
		else:
			accumulator += minf(delta, 0.1)
			while accumulator >= 1.0 / 60.0 and mode == "playing":
				accumulator -= 1.0 / 60.0
				arena.tick(1.0 / 60.0)
				if arena.finished:
					_finish()
					break
				var direction := _direction()
				if direction != Vector2i.ZERO:
					arena.move_actor(0, direction)
				for id in range(1, 4):
					Bot.step(arena, id)
	queue_redraw()

func _direction() -> Vector2i:
	for value in held.values():
		if value is Vector2i and value != Vector2i.ZERO:
			return value
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): return Vector2i.UP
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): return Vector2i.DOWN
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): return Vector2i.LEFT
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): return Vector2i.RIGHT
	return Vector2i.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: _bomb()
			KEY_ESCAPE, KEY_P: _toggle_pause()
			KEY_ENTER:
				if mode == "menu" or mode == "result": _start_match()
	if event is InputEventScreenTouch:
		var local: Vector2 = (event.position - position) / scale
		if event.pressed: _pointer_down(event.index, local)
		else: held.erase(event.index)
	elif event is InputEventScreenDrag:
		if held.has(event.index):
			held[event.index] = _pad_direction((event.position - position) / scale)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: _pointer_down(-1, (event.position - position) / scale)
		else: held.erase(-1)
	elif event is InputEventMouseMotion and held.has(-1):
		held[-1] = _pad_direction((event.position - position) / scale)

func _pointer_down(id: int, point: Vector2) -> void:
	if mode == "playing":
		var direction := _pad_direction(point)
		if direction != Vector2i.ZERO:
			held[id] = direction
			return
		if point.distance_to(BOMB_CENTER) < 78.0:
			_bomb()
			return
	for button in buttons:
		if button.rect.has_point(point):
			button.action.call()
			return

func _pad_direction(point: Vector2) -> Vector2i:
	var offset := point - MOVE_CENTER
	if offset.length() > 114.0 or offset.length() < 16.0:
		return Vector2i.ZERO
	if absf(offset.x) > absf(offset.y): return Vector2i(signi(int(offset.x)), 0)
	return Vector2i(0, signi(int(offset.y)))

func _bomb() -> void:
	if mode == "playing" and countdown <= 0.0 and arena.place_bomb(0):
		sound.play_effect("place")

func _toggle_pause() -> void:
	if mode == "playing": mode = "paused"
	elif mode == "paused": mode = "playing"
	held.clear()
	_make_buttons()

func _start_match() -> void:
	match_seed = randi()
	arena.start(match_seed, level)
	mode = "playing"
	countdown = 3.0
	accumulator = 0.0
	particles.clear()
	held.clear()
	flash_time = 0.0
	_make_buttons()

func _finish() -> void:
	mode = "result"
	held.clear()
	rounds += 1
	if arena.winner == 0:
		victories += 1
		best += 1
		_save_settings()
	_make_buttons()

func _menu() -> void:
	mode = "menu"
	held.clear()
	arena.start(42813, level)
	_make_buttons()

func _cycle_level() -> void:
	level = (level + 1) % 3
	_save_settings()
	_make_buttons()

func _mute() -> void:
	muted = not muted
	sound.enabled = not muted
	_save_settings()
	_make_buttons()

func _make_buttons() -> void:
	buttons.clear()
	if mode == "menu":
		_button(Rect2(80, 450, 360, 64), "PLAY SOLO   →", _start_match, true)
		_button(Rect2(80, 528, 218, 48), "AI: " + ["RELAXED", "NORMAL", "FIERCE"][level], _cycle_level)
		_button(Rect2(310, 528, 130, 48), "SOUND " + ("OFF" if muted else "ON"), _mute)
	elif mode == "playing":
		_button(Rect2(1112, 37, 112, 44), "PAUSE  Ⅱ", _toggle_pause)
	elif mode == "paused":
		_button(Rect2(480, 403, 320, 56), "RESUME   →", _toggle_pause, true)
		_button(Rect2(480, 473, 320, 48), "SOUND " + ("OFF" if muted else "ON"), _mute)
		_button(Rect2(480, 535, 320, 48), "MAIN MENU", _menu)
	elif mode == "result":
		_button(Rect2(480, 443, 320, 58), "PLAY AGAIN   →", _start_match, true)
		_button(Rect2(480, 517, 320, 48), "MAIN MENU", _menu)

func _button(rect: Rect2, label: String, action: Callable, primary: bool = false) -> void:
	buttons.append({"rect": rect, "label": label, "action": action, "primary": primary})

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), INK)
	for i in 65:
		var p := Vector2(fmod(i * 193.7, 1280), fmod(i * 97.3, 800))
		draw_circle(p, 1.0, Color(0.3, 0.7, 0.8, 0.08 + 0.06 * sin(clock + i)))
	if mode == "menu":
		_draw_menu()
	else:
		_draw_match()
		if mode == "paused" or mode == "result": _draw_overlay()
	for button in buttons:
		var hover: bool = button.rect.has_point((get_global_mouse_position() - position) / scale)
		var color: Color = TEAL if button.primary else PANEL
		if hover: color = color.lightened(0.1)
		_panel(button.rect, color, color if button.primary else LINE, 12)
		_text_center(button.rect.get_center() + Vector2(0, 7), button.label, 20, INK if button.primary else WHITE)

func _draw_menu() -> void:
	_text(Vector2(80, 76), "ATOMIC / ARCADE LAB", 17, TEAL)
	_text(Vector2(80, 213), "Atomic", 84, WHITE)
	_text(Vector2(80, 296), "Tux", 104, TEAL)
	_text(Vector2(83, 348), "Little penguins. Big chain reactions.", 23, WHITE)
	_text(Vector2(83, 389), "Outsmart three bots. Be the last Tux standing.", 18, MUTED)
	_text(Vector2(83, 624), "01   DROP       02   DODGE       03   DOMINATE", 15, TEAL)
	_text(Vector2(83, 661), "WASD / arrows to move · Space to drop a bomb", 16, MUTED)
	_text(Vector2(83, 687), "Playing on a phone? Use the pad and bomb button.", 16, MUTED)
	_panel(Rect2(572, 111, 628, 577), Color("0d2130"), LINE, 28)
	for y in 7:
		for x in 8:
			var rect := Rect2(605 + x * 70, 145 + y * 70, 62, 62)
			_panel(rect, Color("112d39") if (x+y)%2 == 0 else Color("13343d"), Color.TRANSPARENT, 8)
	for radius in [205, 245]:
		draw_arc(Vector2(888, 387), radius, 0, TAU, 96, Color(0.4, 0.95, 0.8, 0.12), 2, true)
	draw_circle(Vector2(891, 580), 135, Color(0, 0, 0, 0.2))
	var bob := sin(clock * 2) * 8
	draw_texture_rect(TUX, Rect2(660, 162 + bob, 460, 460), false)
	_draw_bomb(Vector2(1080, 554), 34, 0.9)
	_panel(Rect2(737, 625, 300, 42), INK, LINE, 21)
	_text_center(Vector2(887, 653), "ONE TUX. ZERO SECOND CHANCES.", 14, GOLD)
	_text(Vector2(80, 758), "OPEN SOURCE  /  GODOT  /  MADE FOR ANDROID", 13, MUTED)
	_text(Vector2(947, 758), "SOLO ARENA   •   v0.1", 14, TEAL)

func _draw_match() -> void:
	_text(Vector2(48, 68), "AtomicTux", 32, WHITE)
	_text(Vector2(305, 55), "SOLO ARENA", 14, TEAL)
	_text(Vector2(305, 82), "THE CIRCUIT GARDEN", 20, WHITE)
	var seconds := ceili(arena.remaining)
	_text_center(Vector2(640, 73), "%02d:%02d" % [seconds / 60, seconds % 60], 34, GOLD if seconds < 30 else WHITE)
	_text(Vector2(822, 57), "SURVIVORS", 12, MUTED)
	var alive := arena.actors.filter(func(a): return a.alive).size()
	_text(Vector2(842, 86), "%d / 4" % alive, 27, TEAL)
	draw_line(Vector2(48, 108), Vector2(1232, 108), LINE, 1)
	_draw_board()
	_text(Vector2(48, 161), "THE LINEUP", 14, MUTED)
	for id in 4:
		var actor: Dictionary = arena.actors[id]
		var y := 187.0 + id * 66
		_panel(Rect2(46, y, 222, 56), PANEL, TEAL if id == 0 else LINE, 10)
		draw_texture_rect(TUX, Rect2(56, y+4, 48, 48), false, Color.WHITE if actor.alive else Color(0.35,0.35,0.35,0.5))
		draw_circle(Vector2(104, y + 39), 5, COLORS[id] if actor.alive else MUTED)
		_text(Vector2(119, y+25), NAMES[id], 17, COLORS[id] if actor.alive else MUTED)
		_text(Vector2(119, y+43), ("PLAYER 01" if id == 0 else "AI / " + ["RELAXED", "NORMAL", "FIERCE"][level]) if actor.alive else "ELIMINATED", 11, MUTED)
	_text(Vector2(1010, 162), "YOUR LOADOUT", 14, MUTED)
	var player: Dictionary = arena.actors[0]
	_stat(191, "BOMBS", "%d / %d" % [player.capacity - player.bombs, player.capacity], TEAL, "bomb")
	_stat(274, "BLAST RANGE", "%d TILES" % player.power, GOLD, "fire")
	_stat(357, "SPEED", "%d%%" % roundi(0.17 / player.move_time * 100), Color("b09aff"), "speed")
	_panel(Rect2(1010,440,222,35),PANEL,LINE,8)
	draw_texture_rect(ICONS.kick,Rect2(1018,443,29,29),false)
	_text(Vector2(1055,463),"KICK ON" if player.kick else "KICK: FIND UPGRADE",13,Color("83caff") if player.kick else MUTED)
	_draw_controls()
	_text_center(Vector2(640, 751), flash if flash_time > 0 else "BREAK CRATES. GRAB UPGRADES. WATCH THE FUSE.", 15, GOLD if flash_time > 0 else MUTED)
	_text_center(Vector2(640, 778), "WASD / ARROWS   move     •     SPACE   bomb     •     ESC   pause", 12, MUTED)
	if countdown > 0 and mode == "playing":
		draw_rect(Rect2(BOARD, Vector2(676, 572)), Color(0.02,0.06,0.1,0.55))
		_text_center(Vector2(640, 414), str(ceili(countdown)), 100, TEAL)
		_text_center(Vector2(640, 462), "GET READY", 20, WHITE)

func _draw_board() -> void:
	var offset := Vector2(sin(clock * 100), cos(clock * 83)) * shake
	_panel(Rect2(BOARD - Vector2(8,8), Vector2(692,588)), Color("1b3a43"), Color("345864"), 15)
	for y in Arena.HEIGHT:
		for x in Arena.WIDTH:
			var cell := Vector2i(x, y)
			var origin := BOARD + Vector2(cell) * CELL + offset
			var rect := Rect2(origin + Vector2(2,2), Vector2(48,48))
			var tile: int = arena.tile(cell)
			_panel(rect, Color("15323a") if (x+y)%2 == 0 else Color("18383e"), Color.TRANSPARENT, 5)
			if tile == Arena.WALL:
				_panel(Rect2(origin+Vector2(2,5),Vector2(48,45)), Color("0b1c29"), Color.TRANSPARENT, 6)
				_panel(Rect2(origin+Vector2(3,1),Vector2(46,42)), Color("355464"), Color("446879"), 6)
				draw_line(origin+Vector2(11,9),origin+Vector2(40,9),Color("557b8c"),2)
				draw_circle(origin+Vector2(25,25),3,Color("233d4d"))
			elif tile == Arena.CRATE:
				_panel(Rect2(origin+Vector2(4,7),Vector2(44,42)),Color("4a3028"),Color.TRANSPARENT,5)
				_panel(Rect2(origin+Vector2(4,3),Vector2(44,42)),Color("b47e4e"),Color("d4a16c"),5)
				for dx in [14, 36]: draw_line(origin+Vector2(dx,6),origin+Vector2(dx,42),Color("775032"),2)
				draw_line(origin+Vector2(9,37),origin+Vector2(42,11),Color("e1b47c"),6)
				draw_line(origin+Vector2(9,39),origin+Vector2(42,13),Color("93653f"),2)
			elif arena.pickups.has(cell) and not arena.flames.has(cell):
				var kind: String = arena.pickups[cell]
				var color := TEAL if kind == "bomb" else GOLD if kind == "fire" else Color("83caff") if kind == "kick" else Color("b09aff")
				_panel(Rect2(origin+Vector2(6,6),Vector2(40,40)),color.darkened(0.72),color,9)
				draw_texture_rect(ICONS[kind], Rect2(origin+Vector2(8,8),Vector2(36,36)), false)
	for bomb in arena.bombs:
		var bomb_center: Vector2 = BOARD + Vector2(bomb.cell)*CELL + Vector2(26,27)+offset
		if bomb.direction != Vector2i.ZERO:
			for trail in range(1,4):
				draw_circle(bomb_center-Vector2(bomb.direction)*trail*9,5-trail,Color(0.51,0.79,1.0,0.7-trail*0.15))
		_draw_bomb(bomb_center, 17, bomb.fuse)
	for cell in arena.flames:
		var center: Vector2 = BOARD + Vector2(cell)*CELL + Vector2(26,26)+offset
		var strength: float = arena.flames[cell] / Arena.FIRE_TIME
		draw_circle(center, 27, Color(1.0,0.31,0.1,0.28 * strength))
		_panel(Rect2(center-Vector2(24,17),Vector2(48,34)),Color("ff893e"),Color.TRANSPARENT,10)
		_panel(Rect2(center-Vector2(17,24),Vector2(34,48)),Color("ffb84f"),Color.TRANSPARENT,10)
		draw_circle(center, 12 + sin(clock*40)*3, Color("fff0af"))
	for actor in arena.actors:
		if not actor.alive: continue
		var blend := 1.0 - clampf(actor.cooldown / actor.move_time, 0, 1)
		var center := BOARD + Vector2(actor.previous).lerp(Vector2(actor.cell), minf(1.0, blend*2.5))*CELL + Vector2(26,26)+offset
		draw_circle(center+Vector2(0,15),21,Color(0,0,0,0.3))
		draw_arc(center+Vector2(0,10),21,0,TAU,32,COLORS[actor.id],3,true)
		var bob := sin(blend*PI)*3 if actor.cooldown > 0 else sin(clock*2+actor.id)*1.2
		draw_texture_rect(TUX,Rect2(center-Vector2(26,34+bob),Vector2(52,57)),false)
		draw_circle(center+Vector2(0,-31-bob),5,COLORS[actor.id])
	for particle in particles:
		draw_circle(particle.pos, maxf(1,particle.life*6), Color(1,0.72,0.3,minf(1,particle.life*2)))

func _draw_bomb(center: Vector2, radius: float, fuse: float) -> void:
	var pulse := 1.0 + sin(clock*(12 if fuse < 1.0 else 5))*0.07
	draw_circle(center+Vector2(0,4),radius*pulse+2,Color(0,0,0,0.3))
	draw_circle(center,radius*pulse,Color("172331"))
	draw_arc(center,radius*pulse,0,TAU,32,Color("657784"),2,true)
	draw_circle(center+Vector2(-radius*0.3,-radius*0.3),radius*0.23,Color("465c6b"))
	draw_line(center+Vector2(3,-radius+2),center+Vector2(7,-radius-8),GOLD,3,true)
	draw_circle(center+Vector2(7,-radius-8),4+sin(clock*28)*1.5,GOLD)
	if radius < 20:
		draw_arc(center,radius+4,-PI/2,-PI/2+TAU*clampf(fuse/Arena.FUSE,0,1),32,TEAL if fuse>1 else Color("ff7d64"),2,true)

func _draw_controls() -> void:
	var center := MOVE_CENTER
	draw_circle(center,100,Color("101e2e"))
	draw_arc(center,100,0,TAU,64,LINE,2,true)
	for direction in Arena.DIRECTIONS:
		var rect := Rect2(center+Vector2(direction)*61-Vector2(27,27),Vector2(54,54))
		var active: bool = _direction() == direction and mode == "playing"
		_panel(rect,TEAL.darkened(0.6) if active else Color("213448"),TEAL if active else LINE,12)
		var tip := rect.get_center()+Vector2(direction)*10
		var base := rect.get_center()-Vector2(direction)*6
		var perpendicular := Vector2(-direction.y,direction.x)*8
		draw_colored_polygon(PackedVector2Array([tip,base+perpendicular,base-perpendicular]),TEAL if active else WHITE)
	draw_circle(center,9,Color("365065"))
	_text_center(MOVE_CENTER + Vector2(0,130), "MOVE", 13, MUTED)
	draw_circle(BOMB_CENTER,78,Color("493832"))
	draw_circle(BOMB_CENTER + Vector2(0,-4),70,GOLD)
	_draw_bomb(BOMB_CENTER + Vector2(0,-13),25,1.5)
	_text_center(BOMB_CENTER + Vector2(0,39),"DROP",16,INK)
	_text_center(BOMB_CENTER + Vector2(0,130),"BOMB / SPACE",13,MUTED)

func _stat(y: float, label: String, value: String, color: Color, kind: String) -> void:
	_panel(Rect2(1010,y,222,69),PANEL,LINE,10)
	draw_texture_rect(ICONS[kind],Rect2(1182,y+15,38,38),false)
	_text(Vector2(1028,y+24),label,12,MUTED)
	_text(Vector2(1028,y+53),value,24,color)

func _draw_overlay() -> void:
	draw_rect(Rect2(0,0,1280,800),Color(0.02,0.04,0.07,0.85))
	_panel(Rect2(421,204,438,418),PANEL,LINE,24)
	if mode == "paused":
		_text_center(Vector2(640,274),"TAKE A BREATHER",14,TEAL)
		_text_center(Vector2(640,340),"Paused",48,WHITE)
		_text_center(Vector2(640,376),"Your arena can wait.",18,MUTED)
	else:
		var won := arena.winner == 0
		var draw_game: bool = arena.actors[0].alive and not won
		_text_center(Vector2(640,258),"ROUND COMPLETE",14,TEAL)
		_text_center(Vector2(640,325),"Victory!" if won else "Time's up!" if draw_game else "Oh, Tux.",48,TEAL if won else GOLD)
		_text_center(Vector2(640,370),"Last penguin standing." if won else "The arena ends in a draw." if draw_game else "Caught in the chain reaction.",18,WHITE)
		_text_center(Vector2(640,408),"SESSION  %d WINS / %d ROUNDS" % [victories,rounds],14,MUTED)

func _panel(rect: Rect2, fill: Color, border: Color, radius: int) -> void:
	var key := "%s/%s/%d" % [fill.to_html(), border.to_html(), radius]
	if not panel_styles.has(key):
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.border_color = border
		style.set_border_width_all(1 if border.a > 0 else 0)
		style.set_corner_radius_all(radius)
		panel_styles[key] = style
	draw_style_box(panel_styles[key],rect)

func _text(point: Vector2, value: String, size: int, color: Color) -> void:
	draw_string(font,point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _text_center(point: Vector2, value: String, size: int, color: Color) -> void:
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	_text(point-Vector2(width/2,0),value,size,color)

func _on_exploded(cells: Array) -> void:
	shake = 3.0
	sound.play_effect("boom")
	for cell in cells:
		for i in 4:
			particles.append({"pos": BOARD+Vector2(cell)*CELL+Vector2(26,26),"velocity":Vector2.from_angle(randf()*TAU)*randf_range(30,110),"life":randf_range(0.2,0.6)})

func _on_collected(id: int, kind: String) -> void:
	if id == 0:
		flash = {"bomb":"EXTRA BOMB", "fire":"BLAST RANGE UP", "speed":"SPEED UP", "kick":"BOMB KICK — WALK INTO A BOMB"}[kind]
		flash_time = 2.0
		sound.play_effect("pickup")

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		level = clampi(int(config.get_value("game","difficulty",1)),0,2)
		muted = bool(config.get_value("game","muted",false))
		best = int(config.get_value("game","wins",0))
	sound.enabled = not muted

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("game","difficulty",level)
	config.set_value("game","muted",muted)
	config.set_value("game","wins",best)
	config.save("user://settings.cfg")
