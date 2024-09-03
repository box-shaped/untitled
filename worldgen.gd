extends TileMapLayer 


# Constants to define map dimensions
var MAP_SIZE = 48:
	set(value):
		MAP_HEIGHT = value
		MAP_WIDTH = value
		
var MAP_HEIGHT = 48

var MAP_WIDTH = 48




# Dictionary defining different tile types and their properties
var VARIANTS = {
	# Grass variants
	"Grass0": {"ID":1, "INDEX": Vector2i(0,1), "TYPE": "GRASS"},
	"Grass1": {"ID":1, "INDEX": Vector2i(1,1), "TYPE": "GRASS"},
	"Grass2": {"ID":1, "INDEX": Vector2i(2,1), "TYPE": "GRASS"},
	# Tree variants
	"Tree0": {"ID":3, "INDEX": Vector2i(1,0), "TYPE": "TREE"},
	# Beach variants
	"Beach0": {"ID":0, "INDEX": Vector2i(3,0), "TYPE": "BEACH"},
	"Beach1": {"ID":0, "INDEX": Vector2i(4,0), "TYPE": "BEACH"},
	"Beach2": {"ID":4, "INDEX": Vector2i(0,0), "TYPE": "BEACH"},
	# Ocean variants
	"Ocean": {"ID":4, "INDEX": Vector2i(3,0), "TYPE": "OCEAN"},
	# Deep Ocean variants
	"DeepOcean": {"ID":4, "INDEX": Vector2i(4,0), "TYPE": "DEEPOCEAN"}
}

# Dictionary defining which tile types can be adjacent to each other
var CONNECTABLE = {
	"GRASS": ["GRASS", "TREE", "BEACH"],
	"TREE": ["GRASS", "TREE"],
	"BEACH": ["GRASS", "OCEAN"],
	"OCEAN": ["BEACH", "OCEAN", "DEEPOCEAN"],
	"DEEPOCEAN": ["OCEAN", "DEEPOCEAN"]
}

# Array to store the map's current state, including possible tile types and collapse status
var tile_data: Array

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_BACKSLASH:
			print("Regenerating Map 16x16")
			clear()
			MAP_SIZE = 16
			_ready()
		if event.keycode == KEY_Z:
			print("Regenerating Map 32x32")
			clear()
			MAP_SIZE = 32
			_ready()
		if event.keycode == KEY_X:
			print("Regenerating Map 64x64")
			clear()
			MAP_SIZE = 64
			_ready()
		if event.keycode == KEY_SPACE:
			print("Regenerating Map 8x8")
			clear()
			MAP_SIZE = 8
			_ready()
			
# Called when the node is added to the scene
func _ready() -> void:
	var startTime = Time.get_unix_time_from_system()
	$Label.set_text("Generating Map...")
	await get_tree().create_timer(0.000001).timeout
	randomize()  # Seed the random number generator to ensure different results on each run
	initialize_tile_data()  # Initialize tile data array with all possibilities
	generate_map()
	var center = Vector2(MAP_HEIGHT*8/2,MAP_WIDTH*8/2)
	$CAMERA.set_global_position(center)  # Start the map generation process
	var endTime = Time.get_unix_time_from_system()
	var elapsed = snapped(endTime-startTime,0.001)
	print(elapsed)
	var labelpos = Vector2(MAP_WIDTH/2*8,-30)
	$Label.set_global_position(labelpos)
	var message = (str(elapsed)+"s to generate. ("+str(MAP_WIDTH)+"x"+str(MAP_HEIGHT)+")")
	$Label.set_text(message)

# Initializes tile_data with all possible tile types and marks all tiles as uncollapsed
func initialize_tile_data():
	tile_data = []  # Clear previous data if any
	for y in range(MAP_HEIGHT):
		var row = []  # Create a new row
		for x in range(MAP_WIDTH):
			# Initialize each cell with all possible types and set collapsed to false
			row.append({
				"possible_types": CONNECTABLE.keys(),
				"collapsed": false
			})
		tile_data.append(row)  # Add the row to the tile data array

# Generates the map by collapsing cells with the lowest entropy
func generate_map():
	var cells = []  # List to keep track of all cells
	# Populate the cells list with all positions on the map
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			cells.append(Vector2i(x, y))
	
	# Continue collapsing cells until all have been processed
	while cells:
		
		var cell = get_lowest_entropy_cell(cells)  # Find the cell with the lowest entropy
		cells.erase(cell)  # Remove the cell from the list to mark it as processed
		contract_tile(cell)  # Collapse the selected cell to a specific tile type

# Finds and returns the cell with the lowest entropy (fewest possible tile types)
func get_lowest_entropy_cell(cells: Array) -> Vector2i:
	var lowest_entropy = INF  # Start with a very high entropy value
	var lowest_entropy_cells = []  # List to store cells with the current lowest entropy
	
	for cell in cells:
		# Calculate entropy as the number of possible tile types
		var entropy = tile_data[cell.y][cell.x]["possible_types"].size()
		if entropy < lowest_entropy:
			lowest_entropy = entropy  # Update the lowest entropy value
			lowest_entropy_cells = [cell]  # Start a new list with this cell
		elif entropy == lowest_entropy:
			lowest_entropy_cells.append(cell)  # Add cell to list of lowest entropy cells if it matches
	
	# Randomly select one of the cells with the lowest entropy
	return lowest_entropy_cells[randi() % lowest_entropy_cells.size()]

# Collapses the specified cell into a specific tile type and updates neighboring cells
func contract_tile(cell: Vector2i):
	var possible_types = tile_data[cell.y][cell.x]["possible_types"]  # Get possible types for the cell
	possible_types = filter_possible_types(cell, possible_types)  # Filter types based on neighbors

	# If no valid types remain, default to a basic Grass tile (error handling)
	if possible_types.is_empty():
		set_cell( cell, VARIANTS["Grass0"]["ID"], VARIANTS["Grass0"]["INDEX"])
		return
	
	# Randomly choose a type from the filtered list
	var chosen_type = possible_types[randi() % possible_types.size()]
	var chosen_tile = get_random_tile_of_type(chosen_type)  # Get a specific tile variant of the chosen type
	
	# Set the chosen tile in the TileMap
	set_cell( cell, VARIANTS[chosen_tile]["ID"], VARIANTS[chosen_tile]["INDEX"])
	tile_data[cell.y][cell.x]["collapsed"] = true  # Mark this cell as collapsed
	tile_data[cell.y][cell.x]["possible_types"] = [chosen_type]  # Update to reflect the chosen type
	tile_data[cell.y][cell.x]["chosen_tile"] = chosen_tile  # Store the exact tile used

	# Propagate constraints to update neighbors based on the new tile
	propagate_constraints(cell)

# Filters out tile types that do not comply with adjacency rules based on neighboring cells
func filter_possible_types(cell: Vector2i, possible_types: Array) -> Array:
	var filtered_types = possible_types.duplicate()  # Create a copy of the possible types
	var neighbors = get_neighboring_cells(cell)  # Get list of neighboring cells

	# Check each neighbor to refine the list of possible types
	for neighbor in neighbors:
		if tile_data[neighbor.y][neighbor.x]["collapsed"]:
			# Get the type of the collapsed neighbor
			var neighbor_type = tile_data[neighbor.y][neighbor.x]["possible_types"][0]
			# Check each possible type against the neighbor's constraints
			for possible_type in possible_types:
				if !CONNECTABLE[neighbor_type].has(possible_type):
					filtered_types.erase(possible_type)  # Remove incompatible types
	
	return filtered_types  # Return the refined list of possible types

# Returns an array of valid neighboring cells for a given cell (up, down, left, right)
func get_neighboring_cells(cell: Vector2i) -> Array:
	var neighbors = []
	
	# Right neighbor
	if cell.x < MAP_WIDTH - 1:
		neighbors.append(Vector2i(cell.x + 1, cell.y))
	# Down neighbor
	if cell.y < MAP_HEIGHT - 1:
		neighbors.append(Vector2i(cell.x, cell.y + 1))
	# Left neighbor
	if cell.x > 0:
		neighbors.append(Vector2i(cell.x - 1, cell.y))
	# Up neighbor
	if cell.y > 0:
		neighbors.append(Vector2i(cell.x, cell.y - 1))
	
	return neighbors  # Return the list of neighboring cells

# Selects a random tile variant of a given type from the VARIANTS dictionary
func get_random_tile_of_type(type: String) -> String:
	var tiles_of_type = []  # List to store all tile variants of the given type
	
	# Loop through all defined tiles and add those that match the requested type
	for tile in VARIANTS:
		if VARIANTS[tile]["TYPE"] == type:
			tiles_of_type.append(tile)
	
	# Randomly select a tile from the list, or default to "Grass0" if none found
	if tiles_of_type.size() > 0:
		return tiles_of_type[randi() % tiles_of_type.size()]
	else:
		return "Grass0"  # Fallback option

# Propagates constraints to neighboring cells to ensure map consistency after a tile is collapsed
# Iteratively propagates constraints to neighboring cells to ensure map consistency after a tile is collapsed
func propagate_constraints(start_cell: Vector2i):
	var queue = [start_cell]  # Initialize a queue with the start cell

	while queue.size() > 0:
		var cell = queue.pop_front()  # Get the next cell from the queue
		var neighbors = get_neighboring_cells(cell)  # Get neighboring cells

			# Update each neighbor that has not yet been collapsed
		for neighbor in neighbors:
			if !tile_data[neighbor.y][neighbor.x]["collapsed"]:
				var possible_types = tile_data[neighbor.y][neighbor.x]["possible_types"]
				possible_types = filter_possible_types(neighbor, possible_types)  # Filter possible types based on updated neighbors

				# Collapse the neighbor if possible types have been reduced
				if possible_types.size() < tile_data[neighbor.y][neighbor.x]["possible_types"].size():
					tile_data[neighbor.y][neighbor.x]["possible_types"] = possible_types  # Update possible types
					if possible_types.size() == 1:  # If only one possible type remains, collapse it
						contract_tile(neighbor)  # Collapse the tile
					else:
						queue.append(neighbor)  # Continue to propagate constraints if still multiple options


# Empty function for frame-by-frame processing; not used in this script
func _process(delta: float) -> void:
	pass
