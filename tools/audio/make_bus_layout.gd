extends SceneTree
## Tool script: builds the bus graph described in audio/manifest.json ("buses", generated from
## tools/audio/score.py) and saves it as res://default_bus_layout.tres, the engine's default
## audio/buses/default_bus_layout path, so no project setting is needed.
## Usage (repo root): godot --headless --path . -s res://tools/audio/make_bus_layout.gd

func _init() -> void:
	var f := FileAccess.open("res://audio/manifest.json", FileAccess.READ)
	var man: Dictionary = JSON.parse_string(f.get_as_text())
	var buses: Array = man["buses"]
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	while AudioServer.get_bus_effect_count(0) > 0:
		AudioServer.remove_bus_effect(0, 0)
	for i in buses.size():
		var b: Dictionary = buses[i]
		if i > 0:
			AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, b["name"])
		AudioServer.set_bus_volume_db(i, float(b["volume_db"]))
		if i > 0:
			AudioServer.set_bus_send(i, StringName(b["send"]))
		var fx: Array = b["effects"]
		for j in fx.size():
			var e: Dictionary = fx[j]
			var eff: AudioEffect = ClassDB.instantiate(e["class"])
			assert(eff != null, "unknown effect class " + str(e["class"]))
			var props: Dictionary = e["props"]
			for k: String in props:
				assert(k in eff, "unknown property " + k)
				eff.set(k, props[k])
			AudioServer.add_bus_effect(i, eff)
			AudioServer.set_bus_effect_enabled(i, j, bool(e["enabled"]))
	var err := ResourceSaver.save(AudioServer.generate_bus_layout(), "res://default_bus_layout.tres")
	print("save err=", err)
	quit()
