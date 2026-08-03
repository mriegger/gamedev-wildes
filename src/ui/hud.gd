extends CanvasLayer
class_name HUD

@onready var hotbar: Hotbar = $Hotbar as Hotbar

var _inv_model: InventoryModel = null
var inventory_model: InventoryModel:
	get:
		return _inv_model
	set(v):
		_inv_model = v
		if hotbar:
			hotbar.inventory_model = v

func setup(p_inventory: InventoryModel):
	inventory_model = p_inventory

func _ready():
	if hotbar and _inv_model:
		hotbar.inventory_model = _inv_model
