## scripts/audio_manager.gd
## Autoload: music, ambience, machine loops and UI/gameplay SFX.
##
## Every path below is a file that really exists in assets/audio (sources and licences
## are listed in assets/audio/README.md).  The pack arrives as .ogg / .mp3 / .wav, so
## loaders accept any AudioStream and only add WAV-specific loop bookkeeping when needed.
##
## Routing map (what triggers what):
##   player.gd  -> set_footsteps()                while the astronaut is walking
##   EventBus.item_collected  -> ore_crack / water_bleep / item_pickup
##   EventBus.building_placed -> construction_build
##   EventBus.building_toggled-> switch_on/off (+ water pump & O2 generator loops)
##   EventBus.crop_harvested  -> item_pickup
##   EventBus.fact_unlocked   -> research_scan
##   EventBus.build_menu_focus-> interface_zoom
##   EventBus.day_changed     -> sol_end_chime
##   EventBus.notice          -> alarms / ui_error by keyword
##   EventBus.game_event_started/ended, space_weather_warning -> storm, leak, radiation
##   EventBus.mission_over    -> mission_confirm or warning_alert
extends Node

## One click file is reused for hover/confirm, which is normal for a prototype.
const _UI_CLICK := "res://assets/audio/ui/ui_click_01.mp3"

# --- music & ambience -----------------------------------------------------
const MENU_THEME := "res://assets/audio/music/menu_space_music.ogg"
const DISASTER_DRONE := "res://assets/audio/music/disaster_high_alert.ogg"
const MARS_WIND := "res://assets/audio/ambience/mars_perseverance_wind_sol04.mp3"

# --- user interface -------------------------------------------------------
const UI_HOVER := _UI_CLICK
const UI_CONFIRM := _UI_CLICK
const UI_BACK := "res://assets/audio/ui/ui_back.wav"
const UI_ERROR := "res://assets/audio/ui/ui_error.wav"
const MISSION_CONFIRM := "res://assets/audio/ui/mission_confirm.wav"
const INTERFACE_ZOOM := "res://assets/audio/ui/interface_zoom.wav"
const WATER_BLEEP := "res://assets/audio/ui/water_bleep.wav"

# --- player ---------------------------------------------------------------
const FOOTSTEPS := "res://assets/audio/sfx/footstep_walk.wav"
const MASK_BREATH_SHORT := "res://assets/audio/sfx/mask_breath_short.mp3"
const BREATHING_MASK := "res://assets/audio/sfx/breathing_mask.mp3"

# --- gathering & building -------------------------------------------------
const ITEM_PICKUP := "res://assets/audio/sfx/item_pickup.mp3"
const ORE_CRACK := "res://assets/audio/sfx/ore_crack.mp3"
const CONSTRUCTION := "res://assets/audio/sfx/construction_build.wav"
const DEMOLISH := "res://assets/audio/sfx/demolish_bricks.mp3"
const SOLAR_CLEANING := "res://assets/audio/sfx/solar_cleaning.mp3"
const RESEARCH_SCAN := "res://assets/audio/sfx/research_scan.mp3"

# --- machines -------------------------------------------------------------
const SWITCH_ON := "res://assets/audio/sfx/switch_on.mp3"
const SWITCH_OFF := "res://assets/audio/sfx/switch_off.mp3"
const WATER_PUMP_LOOP := "res://assets/audio/sfx/water_pump_loop.mp3"
const OXYGEN_GENERATOR_LOOP := "res://assets/audio/sfx/oxygen_generator_loop.wav"

# --- alarms ---------------------------------------------------------------
const WARNING_ALERT := "res://assets/audio/sfx/warning_alert.mp3"
const POWER_ALARM := "res://assets/audio/sfx/power_shortage_alarm.wav"
const DUST_STORM_LOOP := "res://assets/audio/sfx/dust_storm_wind_loop.ogg"
const OXYGEN_LEAK_ALARM := "res://assets/audio/sfx/oxygen_leak.ogg"
const RADIATION_ALARM := "res://assets/audio/sfx/radiation_warning_alarm.ogg"
const SHIELD_PROTECTION := "res://assets/audio/sfx/shield_protection_hum.wav"
const SOL_END := "res://assets/audio/sfx/sol_end_chime.wav"

var _music_player: AudioStreamPlayer
var _mars_player: AudioStreamPlayer
var _weather_player: AudioStreamPlayer
var _disaster_player: AudioStreamPlayer
var _walk_player: AudioStreamPlayer
var _breath_player: AudioStreamPlayer
var _pump_player: AudioStreamPlayer
var _oxygen_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
## player -> the path it should keep repeating (mp3/ogg have no in-file loop here).
var _loop_paths: Dictionary = {}
var _footsteps_on: bool = false
var _breathing_on: bool = false


func _ready() -> void:
	_music_player = _make_player("MusicPlayer")
	_mars_player = _make_player("MarsAmbiencePlayer")
	_weather_player = _make_player("WeatherPlayer")
	_disaster_player = _make_player("DisasterMusicPlayer")
	_walk_player = _make_player("FootstepPlayer")
	_breath_player = _make_player("BreathingPlayer")
	_pump_player = _make_player("WaterPumpPlayer")
	_oxygen_player = _make_player("OxygenGeneratorPlayer")
	for index: int in range(8):
		_sfx_players.append(_make_player("SFXPlayer%d" % index))

	EventBus.game_event_started.connect(_on_game_event_started)
	EventBus.game_event_ended.connect(_on_game_event_ended)
	EventBus.space_weather_warning.connect(_on_space_weather_warning)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_toggled.connect(_on_building_toggled)
	EventBus.crop_harvested.connect(_on_crop_harvested)
	EventBus.fact_unlocked.connect(_on_fact_unlocked)
	EventBus.build_menu_focus.connect(_on_build_menu_focus)
	EventBus.mission_over.connect(_on_mission_over)
	EventBus.notice.connect(_on_notice)
	for loop_player: AudioStreamPlayer in [
		_music_player, _mars_player, _weather_player, _disaster_player,
		_walk_player, _breath_player, _pump_player, _oxygen_player,
	]:
		loop_player.finished.connect(_on_loop_finished.bind(loop_player))


func enter_menu() -> void:
	_mars_player.stop()
	set_footsteps(false)
	set_oxygen_critical(false)
	_stop_machines()
	_stop_event_audio()
	_play_loop(_music_player, MENU_THEME, -17.0)


func enter_gameplay() -> void:
	_music_player.stop()
	set_oxygen_critical(false)
	_stop_event_audio()
	_play_loop(_mars_player, MARS_WIND, -27.0)


# ---------------------------------------------------------------- public hooks

## Called by player.gd every physics frame with "am I walking right now".
func set_footsteps(active: bool) -> void:
	if active == _footsteps_on:
		return
	_footsteps_on = active
	if active:
		_play_loop(_walk_player, FOOTSTEPS, -16.0)
	else:
		_stop_loop(_walk_player)


## Called when the suit's oxygen reserve gets low: a rebreather hiss under the mix.
func set_oxygen_critical(active: bool) -> void:
	if active == _breathing_on:
		return
	_breathing_on = active
	if active:
		_play_loop(_breath_player, MASK_BREATH_SHORT, -13.0)
	else:
		_stop_loop(_breath_player)


func play_solar_cleaning() -> void:
	_play_sfx(SOLAR_CLEANING, -10.0)


## Available for a future "remove building" feature; no demolish key exists yet.
func play_demolish() -> void:
	_play_sfx(DEMOLISH, -10.0)


func play_ui_hover() -> void:
	_play_sfx(UI_HOVER, -30.0)


func play_ui_confirm() -> void:
	_play_sfx(UI_CONFIRM, -18.0)


func play_ui_back() -> void:
	_play_sfx(UI_BACK, -16.0)


func play_ui_error() -> void:
	_play_sfx(UI_ERROR, -12.0)


# ---------------------------------------------------------------- internals


func _make_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = "Master"
	add_child(player)
	return player


func _play_loop(player: AudioStreamPlayer, path: String, volume_db: float) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("AudioManager: missing audio asset: %s" % path)
		return
	if _loop_paths.get(player, "") == path and player.playing:
		return
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.data.is_empty():
			push_warning("AudioManager: empty audio asset: %s" % path)
			return
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var bytes_per_frame := 4 if wav.stereo else 2
		@warning_ignore("integer_division")
		wav.loop_end = maxi(1, int(wav.data.size() / bytes_per_frame))
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	_loop_paths[player] = path
	player.play()


func _stop_loop(player: AudioStreamPlayer) -> void:
	player.stop()
	_loop_paths.erase(player)


## Compressed sources (ogg/mp3) have no loop markers, so restart them by hand.
func _on_loop_finished(player: AudioStreamPlayer) -> void:
	if _loop_paths.has(player):
		player.play()


func _play_sfx(path: String, volume_db: float) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("AudioManager: missing audio asset: %s" % path)
		return
	var player: AudioStreamPlayer
	for candidate: AudioStreamPlayer in _sfx_players:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = _sfx_players[0]
		player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


func _stop_event_audio() -> void:
	_weather_player.stop()
	_disaster_player.stop()
	_loop_paths.erase(_weather_player)
	_loop_paths.erase(_disaster_player)


## Water pump and oxygen generator run as long as their building is switched on.
func _stop_machines() -> void:
	_stop_loop(_pump_player)
	_stop_loop(_oxygen_player)


# ---------------------------------------------------------------- event routing

func _on_game_event_started(event: Dictionary) -> void:
	_play_loop(_disaster_player, DISASTER_DRONE, -25.0)
	match str(event.get("type", "")):
		"dust_storm":
			_play_loop(_weather_player, DUST_STORM_LOOP, -17.0)
		"oxygen_leak":
			_play_sfx(OXYGEN_LEAK_ALARM, -10.0)
			_play_sfx(BREATHING_MASK, -12.0)
		"radiation_warning":
			_play_sfx(RADIATION_ALARM, -9.0)
		_:
			_play_sfx(WARNING_ALERT, -10.0)


func _on_game_event_ended(_event_id: String) -> void:
	_stop_event_audio()


func _on_space_weather_warning(_event: Dictionary) -> void:
	_play_sfx(WARNING_ALERT, -9.0)


func _on_day_changed(_day: int) -> void:
	_play_sfx(SOL_END, -13.0)


func _on_item_collected(type: String, _amount: int) -> void:
	match type:
		"ore":
			_play_sfx(ORE_CRACK, -10.0)
		"water":
			_play_sfx(WATER_BLEEP, -14.0)
		_:
			_play_sfx(ITEM_PICKUP, -12.0)


func _on_building_placed(_building_id: String, _cell: Vector2i) -> void:
	_play_sfx(CONSTRUCTION, -9.0)


func _on_building_toggled(building_id: String, is_on: bool) -> void:
	_play_sfx(SWITCH_ON if is_on else SWITCH_OFF, -12.0)
	match building_id:
		"water_extraction":
			if is_on:
				_play_loop(_pump_player, WATER_PUMP_LOOP, -22.0)
			else:
				_stop_loop(_pump_player)
		"oxygen_generator":
			if is_on:
				_play_loop(_oxygen_player, OXYGEN_GENERATOR_LOOP, -24.0)
			else:
				_stop_loop(_oxygen_player)


func _on_crop_harvested(_crop_id: String, _amount: int) -> void:
	_play_sfx(ITEM_PICKUP, -11.0)


func _on_fact_unlocked(_fact: Dictionary) -> void:
	_play_sfx(RESEARCH_SCAN, -12.0)


func _on_build_menu_focus(_building_id: String) -> void:
	_play_sfx(INTERFACE_ZOOM, -22.0)


func _on_mission_over(state: String, _reason: String) -> void:
	_stop_machines()
	set_footsteps(false)
	set_oxygen_critical(false)
	if state == "complete":
		_play_sfx(MISSION_CONFIRM, -8.0)
	else:
		_play_sfx(WARNING_ALERT, -8.0)


func _on_notice(text: String) -> void:
	var message := text.to_upper()
	if message.contains("SHIELD HELD"):
		_play_sfx(SHIELD_PROTECTION, -10.0)
	elif message.contains("RADIATION"):
		_play_sfx(RADIATION_ALARM, -10.0)
	elif message.contains("NO POWER") or message.contains("SHUT DOWN"):
		_play_sfx(POWER_ALARM, -10.0)
	elif message.contains("CANNOT") or message.contains("NOT ENOUGH"):
		play_ui_error()
	elif message.contains("SURVIVAL LOG"):
		_play_sfx(RESEARCH_SCAN, -16.0)
