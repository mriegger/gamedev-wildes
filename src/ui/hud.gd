extends CanvasLayer
class_name HUD

## HUD - composes persistent gameplay interfaces, requires injected dependencies

@onready var hotbar: Hotbar = $Hotbar as Hotbar

var player: PlayerMotor = null
var _inv_model: InventoryModel = null
var inventory_model: InventoryModel:
	get:
		return _inv_model
	set(v):
		_inv_model = v
		if hotbar:
			hotbar.inventory_model = v

func setup(p_player: PlayerMotor, p_inventory: InventoryModel):
	player = p_player
	inventory_model = p_inventory
	print("[HUD] Setup player=%s inv=%s hotbar=%s" % [player != null, _inv_model != null, hotbar != null])

func _ready():
	print("[HUD] _ready waiting for setup()")
	if hotbar and _inv_model:
		hotbar.inventory_model = _inv_model
