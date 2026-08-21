extends Node
class_name CombatAffinityTutorialCoordinator

var _combat: MeleeCombatCoordinator
var _entity_catalog: EntityCatalog
var _view: CombatAffinityTutorialView
var _progress: TutorialProgress
var _callout_arbiter: TutorialCalloutArbiter
var _pause_gameplay: Callable
var _resume_gameplay: Callable
var _pending_definition: EntityDefinition

func _ready() -> void:
	set_process(false)

func setup(
	combat: MeleeCombatCoordinator,
	entity_catalog: EntityCatalog,
	view: CombatAffinityTutorialView,
	progress: TutorialProgress,
	callout_arbiter: TutorialCalloutArbiter,
	pause_gameplay: Callable,
	resume_gameplay: Callable,
) -> void:
	assert(combat != null and entity_catalog != null and view != null and progress != null and callout_arbiter != null)
	assert(pause_gameplay.is_valid() and resume_gameplay.is_valid())
	assert(_combat == null and _entity_catalog == null and _view == null and _progress == null and _callout_arbiter == null)
	_combat = combat
	_entity_catalog = entity_catalog
	_view = view
	_progress = progress
	_callout_arbiter = callout_arbiter
	_pause_gameplay = pause_gameplay
	_resume_gameplay = resume_gameplay
	_combat.melee_outcome_committed.connect(_on_melee_outcome_committed)
	_combat.projectile_outcome_committed.connect(_on_projectile_outcome_committed)
	_view.dismissed.connect(_on_view_dismissed)

func _exit_tree() -> void:
	if _combat != null and _combat.melee_outcome_committed.is_connected(_on_melee_outcome_committed):
		_combat.melee_outcome_committed.disconnect(_on_melee_outcome_committed)
	if _combat != null and _combat.projectile_outcome_committed.is_connected(_on_projectile_outcome_committed):
		_combat.projectile_outcome_committed.disconnect(_on_projectile_outcome_committed)
	if _view != null and _view.dismissed.is_connected(_on_view_dismissed):
		_view.dismissed.disconnect(_on_view_dismissed)
	if _callout_arbiter != null:
		_callout_arbiter.release(self)
		_callout_arbiter.cancel_priority(self)

func _process(_delta: float) -> void:
	if _pending_definition == null:
		set_process(false)
		return
	if not _callout_arbiter.try_acquire(self):
		return
	var definition := _pending_definition
	_pending_definition = null
	_progress.complete_damage_affinity_tip()
	_view.show_dialog(build_dialog_text(definition))
	_pause_gameplay.call()
	set_process(false)

func record_damage_response(target_definition_id: StringName, response: int) -> void:
	if (
		_progress.is_damage_affinity_tip_completed()
		or _pending_definition != null
		or _view.is_showing()
		or response != DamageAffinityDefinition.Response.RESISTANT
		or not _entity_catalog.has_definition(target_definition_id)
	):
		return
	_pending_definition = _entity_catalog.get_definition(target_definition_id)
	set_process(true)
	_callout_arbiter.request_priority(self)
	_process(0.0)

func _on_melee_outcome_committed(outcome: MeleeOutcome) -> void:
	if outcome.contact.source_runtime_id != MeleeCombatCoordinator.PLAYER_RUNTIME_ID:
		return
	record_damage_response(outcome.contact.target_definition_id, outcome.damage_response)

func _on_projectile_outcome_committed(outcome: ProjectileOutcome) -> void:
	record_damage_response(outcome.contact.target_definition_id, outcome.damage_response)

func _on_view_dismissed() -> void:
	_callout_arbiter.release(self)
	_resume_gameplay.call()

static func build_dialog_text(definition: EntityDefinition) -> String:
	assert(definition != null)
	var weak_types: Array[String] = []
	var resistant_types: Array[String] = []
	for affinity in definition.damage_affinities:
		var type_name := _colored_damage_type(affinity.damage_type.id, affinity.response)
		if affinity.response == DamageAffinityDefinition.Response.WEAK:
			weak_types.append(type_name)
		elif affinity.response == DamageAffinityDefinition.Response.RESISTANT:
			resistant_types.append(type_name)
	var details: Array[String] = []
	if not resistant_types.is_empty():
		details.append("resistant to %s damage" % _join_terms(resistant_types))
	if not weak_types.is_empty():
		details.append("weak to %s damage" % _join_terms(weak_types))
	var affinity_description := ""
	if details.size() == 2:
		affinity_description = "%s, but %s" % [details[0], details[1]]
	elif not details.is_empty():
		affinity_description = details[0]
	var enemy_line := "For example, %s are %s." % [_pluralize_name(String(definition.id).capitalize()), affinity_description]
	var weakness_color := CombatPresentationPalette.WEAK_DAMAGE_COLOR.to_html(false)
	var resistance_color := CombatPresentationPalette.RESISTANT_DAMAGE_COLOR.to_html(false)
	return (
		"[center]Enemies can be weak or resistant to different types of damage (blunt/slash/pierce).\n\n"
		+ "Pay attention to the damage numbers. Yellow numbers indicate a [b][color=#%s]weakness[/color][/b] against your weapon's damage type, grey numbers indicate a [b][color=#%s]resistance[/color][/b].\n\n" % [weakness_color, resistance_color]
		+ enemy_line
		+ "\n\nTry experimenting with different weapon types against different enemies.[/center]"
	)

static func _colored_damage_type(damage_type_id: StringName, response: int) -> String:
	var color := CombatPresentationPalette.WEAK_DAMAGE_COLOR
	if response == DamageAffinityDefinition.Response.RESISTANT:
		color = CombatPresentationPalette.RESISTANT_DAMAGE_COLOR
	return "[b][color=#%s]%s[/color][/b]" % [color.to_html(false), String(damage_type_id)]

static func _pluralize_name(name: String) -> String:
	if name.ends_with("y") and name.length() > 1 and name.substr(name.length() - 2, 1).to_lower() not in ["a", "e", "i", "o", "u"]:
		return name.substr(0, name.length() - 1) + "ies"
	if name.ends_with("s") or name.ends_with("x") or name.ends_with("z") or name.ends_with("ch") or name.ends_with("sh"):
		return name + "es"
	return name + "s"

static func _join_terms(terms: Array[String]) -> String:
	if terms.size() <= 1:
		return terms[0] if not terms.is_empty() else ""
	if terms.size() == 2:
		return "%s and %s" % [terms[0], terms[1]]
	return "%s, and %s" % [", ".join(terms.slice(0, terms.size() - 1)), terms.back()]
