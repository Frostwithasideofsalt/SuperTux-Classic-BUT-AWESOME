#  SuperTux - A 2D, Open-Source Platformer Game licensed under GPL-3.0-or-later
#  Copyright (C) 2022 Alexander Small <alexsmudgy20@gmail.com>
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation; either version 3
#  of the License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.


extends Node2D

var level_intro = preload("res://scenes/menus/LevelIntroduction.tscn")
var player_node = preload("res://scenes/player/Tux.tscn")
var worldmap_player_node = preload("res://scenes/worldmap/Player.tscn")
var pause_menu = preload("res://scenes/menus/PauseScreen.tscn")
var is_autoscrolling = false

onready var worldmap_objects = get_node_or_null("Objects")
onready var extro_level = WorldmapManager.extro_level

export var is_worldmap = false
export var level_title = ""
export var level_author = ""
export var music = "ChipDisko"
export var particle_system = ""
export var uses_timer = true
export var time = 300
export var gravity = 10
export var autoscroll_speed = 0.0
export var starting_powerup = 0
export var worldmap_spawn = Vector2()
export var worldmap_player_object : PackedScene

onready var custom_camera = get_node_or_null("Camera2D")

# Called when the node enters the scene tree for the first time.
func _ready():
	ResolutionManager.connect("window_resized", self, "window_resized")
	Scoreboard.show()
	WorldmapManager.is_level_worldmap = is_worldmap
	
	if !is_worldmap:
		_set_level_gravity()
	else:
		uses_timer = false
		
		if worldmap_player_object != null:
			_create_worldmap_player(worldmap_spawn, worldmap_player_object)
	
	# Set the player's starting powerup
	if Scoreboard.player_initial_state < starting_powerup:
		Scoreboard.player_initial_state = starting_powerup
	
	if uses_timer: Scoreboard.enable_level_timer(time)
	else: Scoreboard.disable_level_timer()
	
	# Display the level title card and wait until it disappears
	if !is_worldmap: yield(_level_title_card(), "completed")
	else:
		Global.emit_signal("level_ready")
	
	# Then we load the pause menu into the level so you can pause the game
	_load_pause_menu()
	
	# If we're using a custom camera, make it override the player's camera
	# (You can use custom cameras by adding a Camera2D node into the level)
	if custom_camera != null:
		custom_camera.current = true
	
	# If the level has a specified autoscroll speed, we make our own
	# custom camera node to override the player's
	elif autoscroll_speed != 0:
		create_autoscroll_camera()
		ResolutionManager.emit_signal("window_resized")
	
	# If we're using the level timer, start the clock!
	if uses_timer:
		Scoreboard.set_level_timer(time)
	
	# And play the level music!
	if music == "" or !music:
		Music.stop_all()
	else:
		Music.play(music)
	
	emit_signal("level_ready")

func _process(delta):
	if is_autoscrolling:
		autoscroll(delta)

func _set_level_gravity():
	if gravity < 10 && gravity > 0:
		
		# If gravity is lower than normal (under 10), we add
		# more gravity it the closer it is to 5 to more closely
		# imitate how Milestone 1's gravity behaviour
		var additional_gravity = (gravity / (10.0 - gravity)) + ((10.0 - gravity) / gravity)
		additional_gravity = (10 - additional_gravity)
		additional_gravity /= 10
		
		gravity += additional_gravity
	
	if gravity > 10:
		var additional_gravity = (gravity - 10) * 0.5
		
		gravity += additional_gravity
	
	Global.gravity = gravity / 10.0

func _level_title_card():
	# Stop the music
	Music.stop_all()
	
	# Delete the player from the level
	# (we're going to display the title card, so we don't want Tux
	# to be able to move or die during this!)
	var player_pos = Vector2.ZERO
	if Global.player == null:
		yield(Global, "player_loaded")
		player_pos = Global.player.global_position
	Global.player.queue_free()
	
	# Instantiate (spawn) the level title card
	var title = level_intro.instance()
	title.title = level_title
	title.author = level_author
	add_child(title)
	
	# Wait until the title card disappears,
	yield(title, "tree_exited")
	
	# Then we re-add the player into the level
	var player = player_node.instance()
	player.global_position = player_pos
	Global.current_scene.add_child(player)
	
	Global.emit_signal("level_ready")
	
	if get_tree() == null: return
	yield(get_tree(), "idle_frame")

func _load_pause_menu():
	var pause_screen_instance = pause_menu.instance()
	Global.current_scene.add_child(pause_screen_instance)

func _create_worldmap_player(position : Vector2, player_object : PackedScene):
	var player_position = position
	if WorldmapManager.worldmap_player_position != null:
		player_position = WorldmapManager.worldmap_player_position
	
	var player = worldmap_player_node.instance()
	player.global_position = player_position * 32 + Vector2(16,16)
	
	if WorldmapManager.player_stop_direction != null:
		player.stop_direction = WorldmapManager.player_stop_direction
	
	player.tilemaps = []
	player.level_dots = []
	
	# Set the worldmap player's level dots variable to an array of all the level dot objects
	for child in worldmap_objects.get_children():
		if is_instance_valid(child):
			player.level_dots.append(child)
	
	# Set the worldmap player's tile map variable to an array of all the level's tilemaps
	for tilemap in get_children():
		if tilemap is TileMap:
			if is_instance_valid(tilemap):
				player.tilemaps.append(tilemap)
	
	Global.current_scene.add_child(player)
	player.set_owner(Global.current_scene)

func create_autoscroll_camera():
	var camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_bottom = 480
	add_child(camera)
	custom_camera = camera
	is_autoscrolling = true
	window_resized()
	var camera_pos = ResolutionManager.window_resolution.x * 0.5 * camera.zoom.x
	if Global.spawn_position != null:
		camera_pos = Global.spawn_position.x
	camera.position = Vector2(camera_pos, 320)
	camera.current = true

func autoscroll(delta):
	if custom_camera != null:
		custom_camera.position.x += autoscroll_speed * delta * 60 * 2
		if Global.player: custom_camera.position.y = Global.player.position.y

func level_complete():
	is_autoscrolling = false
	if extro_level != null:
		WorldmapManager.extro_level = null
		WorldmapManager.save_progress(true) # Clear the level in worldmap and save progress
		Global.goto_level(extro_level)
		return
	if WorldmapManager.worldmap_level != null:
		WorldmapManager.return_to_worldmap(true, true) # Clear the level in the worldmap and save progress
	else:
		Global.goto_title_screen()

func window_resized():
	if is_autoscrolling and custom_camera:
		var max_size = Vector2(640, 480)
		var window_size = ResolutionManager.window_resolution
		var zoom = max(max_size.x / window_size.x, max_size.y / window_size.y)
		custom_camera.zoom = Vector2.ONE * zoom
