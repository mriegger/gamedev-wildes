# Progression, runes, and enchanting

This document defines how player XP, player levels, item proficiency, rarity, runes, and
enchantments fit together. It separates current behavior from the agreed target design so planned
systems are not mistaken for implemented features.

The status labels used below are:

- **Implemented:** present in the game now.
- **Target:** an agreed design direction that still requires implementation.
- **TBD:** intentionally unresolved balance or behavior.

## System roles

| System | Status | Scope | Purpose | Persistence and reversibility |
| --- | --- | --- | --- | --- |
| Player XP and level | Implemented; linear requirements and spending are targets | Player-wide | Permanent progression, milestone access, and perk awards | Levels are permanent; current-level XP can eventually be spent |
| Perks | Target | Player-wide | Bounded character specialization | Allocations persist; respec is deferred |
| Item proficiency | Implemented | Shared by stable item type ID | Rewards gear use and unlocks rune sockets | Persistent, capped by its definition, and never spent |
| Rarity | Implemented; expanded potential is a target | Item definition | Describes an item's tier and future potential | Permanent content metadata |
| Runes | Implemented | Physical item copy | Reversible build customization | Persist in sockets and can be removed |
| Enchantments | Target | Physical item copy | Predictable permanent item improvement | Persist on that copy; replacement and removal rules are TBD |

These systems must keep distinct jobs:

- Player levels unlock broad capabilities and award bounded global perks.
- Item proficiency represents mastery of a weapon or armor type.
- Runes provide removable build choices and, eventually, unique abilities.
- Enchantments provide permanent, predictable vertical improvement to one item copy.
- Rarity describes the item's authored potential without replacing its stat, proficiency, rune,
  or enchantment definitions.

## Player XP and levels

### Implemented behavior

The player starts at level 1 with zero XP. Player progression currently has no maximum level.
`ActorStats` owns the current level and the XP accumulated toward the next level. Excess XP carries
across level boundaries, and progression is saved with the player.

Player XP currently comes only from player-caused melee defeats. Sheep and zombies each award ten
XP. The reward belongs to each entity definition and remains a provisional content value.

The HUD displays the current level and current-level XP above the hotbar. Death and respawn do not
remove levels or XP. Levels do not yet grant stats, perks, recipes, or other gameplay benefits.

The current level requirement is:

```text
round(100 * 1.25^(level - 1))
```

The next progression stack replaces this exponential curve with the linear requirement:

```text
100 + 25 * (level - 1)
```

Both values remain authored configuration. Existing saves preserve their completed level and
migrate current-level XP proportionally from the old requirement to the new one.

### Target level rewards

Levels will have two reward types.

**Milestone unlocks** grant access at authored levels. Target milestone categories include:

- enchantment tiers;
- recipes;
- crafting capabilities;
- future progression features that should be earned once and never revoked.

The exact unlocks and their required levels remain TBD.

**Perk points** use an authored award cadence. The initial configuration awards one point for every
level reached after level 1, so level 1 begins with zero points and level 5 has earned four. The
configuration keeps both points per award and levels per award explicit so balance can change
through a save migration instead of a code rewrite.

The first bounded perk catalog is:

| Perk | Effect per rank | Maximum rank |
| --- | --- | --- |
| Health | +10 maximum HP | 10 |
| Strength | +1 strength | 10 |
| Defense | +1 defense | 10 |

Unspent points are the points earned for the player's level minus allocated ranks. Saves persist
allocations by stable perk ID; older saves therefore receive all points earned for their existing
level. Maximum-HP changes preserve the current health percentage. Mobility and recovery remain
outside the catalog until they have concrete gameplay behavior.

Respec is deferred. The allocation model must support replacing a complete allocation snapshot so
a later respec item can be added as a real transaction without changing the saved shape. The item,
cost, refund rules, and interface remain TBD.

### Spending XP on enchanting

Enchanting will use the existing player XP rather than a second core currency. Only XP in the
current level bar is spendable. A completed level can never be removed.

This stack does not add an XP-spending command. That command belongs with the first real enchanting
transaction so the item change and payment can be validated and committed together.

The progression invariant is:

```text
0 <= current XP < XP required for the next level
```

An enchantment succeeds only when the player can pay its entire cost from current XP. It cannot
borrow XP from a completed level. An insufficient payment rejects the operation without changing
the player or item.

For a hypothetical level requirement:

```text
Before: Level 10, 80 / 300 XP
Cost:   40 XP
After:  Level 10, 40 / 300 XP
```

This makes enchanting a choice between improving gear now and reaching the next milestone or perk
sooner. Earned levels, milestone unlocks, and perk points remain permanent.

Because leveling happens automatically, the greatest integer XP value a player can retain is one
less than the next-level requirement. A fixed enchantment cost equal to that full requirement is
therefore impossible to pay. High-tier costs must remain below that ceiling or use a level-relative
cost.

## Item proficiency

### Implemented behavior

Item proficiency is separate from player XP and cannot be spent. It is keyed by stable item type
ID, so all copies of the same item type share progress. Mastering one Copper Sword therefore
unlocks the same proficiency level for every Copper Sword, while each physical sword keeps its own
socketed runes.

Current earning rules are:

- a weapon earns the exact damage it applies to each target;
- every equipped armor piece receives full credit from each committed incoming melee outcome.

The earning policy is isolated from combat resolution so future sources can change without
rewriting proficiency state. Each combat item references a `ProficiencyDefinition` containing its
level requirements and rune-slot unlock levels. A definition can expose at most three sockets.

Current Common combat gear has one proficiency level. It reaches that level after one hundred
damage and unlocks its one rune socket at level 1. It begins with no free socket.

### Relationship to other systems

- Player level does not unlock an individual item's rune sockets.
- Item proficiency does not unlock player milestones or perks.
- Item proficiency is never an enchanting payment.
- Rarity may guide which proficiency profile content authors assign, but the profile remains the
  authoritative source for thresholds and socket unlocks.

## Rarity

### Implemented behavior

Rarity currently provides a stable ID, display name, and display color. Only Common exists as
playable content. Rarity does not automatically change base stats, proficiency thresholds, rune
slots, or enchantment capacity.

### Possible future relationships

Rarity should communicate an item's authored base power and improvement potential. The following
relationships are possible but remain TBD:

- base stat budgets;
- the number of rune sockets authored through the proficiency profile;
- enchantment tier or capacity limits;
- the magnitude or availability of rune content.

The agreed target is for rarity to limit enchantment potential, but its capacity model is not yet
chosen. The final rarity names and number of tiers are also not settled. Mechanics should therefore
depend on typed definitions and explicit capacities rather than hard-coded branches for Common,
Rare, or Epic. This keeps adding, removing, or renaming tiers a content change.

Rune rarity and gear rarity are independent. A gear item may accept a rune of a different rarity
unless a future explicit rule restricts it.

## Runes and socketing

### Implemented behavior

A rune is typed item content with:

- a rarity;
- weapon and armor compatibility;
- optional head, chest, legs, or feet restrictions;
- one or more additive or multiplicative stat modifiers.

The Basic Rune is Common, stacks to 99, fits every current melee weapon and armor slot, and grants
`+100 HP`. It has a dedicated icon and a recipe that costs 32 Sand.

Rune slots belong to a physical gear copy, while the proficiency that unlocks them is shared by
item type. Socketing requires compatible gear, a compatible rune, and an unlocked empty slot. It
consumes exactly one rune. Unsocketing returns the rune and is rejected if inventory cannot accept
it. Both operations validate the complete change before committing.

The Runes workspace contains one gear target and three visible socket positions. Each position is
shown as unavailable, locked, empty, or filled. Hovering a rune shows its rarity, compatibility,
and modifiers. Hovering gear shows base stats, proficiency, and aggregated rune contributions in
red.

Rune effects are active only when:

- the containing melee weapon is selected; or
- the containing armor is equipped.

Duplicate runes stack. Runes on unselected weapons or unequipped armor stay persisted but inactive.
Changes to maximum HP preserve the player's current health percentage.

### Target direction

Runes should become the main source of reversible, build-defining effects. Numeric modifiers are
the first supported effect, but future runes may add unique triggered behavior. A new behavior
family must include a typed definition, validation, executor, and real gameplay caller together.

Actual weapon-only, armor-only, armor-piece-specific, and higher-rarity rune content remains to be
authored. Future ranged or magic weapon families will also need explicit compatibility and
activation support.

Socketing does not consume player XP. Its progression gate remains item proficiency.

## Enchantments

### Target role

Enchantments are planned and are not implemented. They permanently improve one physical weapon or
armor copy with predictable stat changes. They should not provide the removable, ability-focused
identity reserved for runes.

"Permanent" means the enchantment stays attached to that item copy until an explicit upgrade,
replacement, removal, or destruction rule changes it. It does not mean the bonus is globally
active: weapon effects apply while that weapon is selected, and armor effects apply while that
armor is equipped.

An enchantment must never mutate a canonical item resource. Doing so would change every copy of
that item type. Saves should store stable enchantment IDs and plain rank or value data on the
physical inventory stack, then derive runtime effects from that state.

Enchantable and socketable gear must remain count-one and unmergeable while state belongs to an
`InventoryStack`. If stackable stateful gear is ever introduced, inventory must gain explicit item
instances rather than merging copies with different sockets or enchantments.

### Proposed version-one loop

1. Reach the player-level milestone that unlocks an enchantment tier.
2. Open the enchanting interface and place one weapon or armor item in its gear slot.
3. Review deterministic, compatible stat improvements and their full XP costs.
4. Select an enchantment and tier or rank.
5. Validate the gear copy, level milestone, enchantment capacity, current XP, and complete result.
6. Commit the item change and XP payment together.
7. Update the item tooltip to show the permanent enchantment separately from base stats and rune
   bonuses.

Version one should use XP alone. Higher tiers may later require authored materials or catalysts,
but those would supplement XP rather than replace it with another core progression currency.

### Enchantment content boundaries

Enchantments may provide predictable numerical improvements such as weapon damage or armor
defense. The eligible stat set must be explicit for each gear family. Enchantment values, costs,
and compatibility belong to typed content definitions rather than UI or transaction code.

Actor-stat enchantments can use the selected-weapon or equipped-armor activation rules. A true
per-copy weapon base-damage enchantment needs combat to query the physical item's derived value;
it cannot edit the shared `MeleeAttackProfile`. The first enchantment catalog must choose its
supported value families together with their real runtime consumers.

Rarity is expected to limit enchantment potential, but the exact rule is TBD. Possible models
include a maximum rank, a point budget, or a limited number of enchantment entries. Rune sockets
and enchantment capacity are separate limits.

The following behaviors remain TBD:

- enchantment tier names and player-level requirements;
- raw XP costs and scaling;
- eligible stats and values;
- rarity capacities;
- whether multiple enchantments stack;
- upgrading, overwriting, removal, and refunds;
- whether later tiers require materials;
- the order in which base values, perks, equipment, enchantments, and runes combine.

## Persistence and transaction rules

The completed system must preserve these invariants:

- Player levels, current XP, derived unspent perk points, perk allocations, earned milestone IDs, item
  proficiency, sockets, and enchantments persist.
- Saves contain stable IDs and plain values, not resource or scene paths.
- A persisted-shape change requires an explicit save-version migration.
- Milestones and perk awards use stable IDs or explicit award state so loading or re-evaluating a
  reward table cannot duplicate or remove earned rewards.
- Rebalancing a persisted reward schedule requires an explicit migration policy.
- Socket and enchantment state follows the physical item copy through moves and save/load.
- Stateful gear remains count-one and cannot merge with a different physical copy.
- Item definitions and catalogs remain immutable at runtime.
- Cross-system operations validate the entire result before committing.
- A failed enchantment changes neither XP nor the target item.
- Runtime modifier replacement remains bounded and cannot leave stale rune or enchantment effects.
- Maximum-HP changes define and consistently apply a health-preservation rule.

## UI responsibilities

Presentation displays state and sends commands; it does not own progression or item truth.

Implemented UI includes:

- the player level and XP bar above the hotbar;
- gear proficiency, rarity, and stats in item tooltips;
- rune compatibility and modifiers in rune tooltips;
- the Runes workspace with three socket positions and four visual states;
- red aggregated rune bonuses on socketed gear.

Planned UI includes:

- a Progression workspace showing level, XP, available points, and bounded perk allocation;
- milestone presentation;
- an enchanting interface with gear eligibility, available choices, exact XP cost, current XP, and
  a preview of the committed result;
- enchantment details on gear tooltips;
- clear rejection reasons without partially changing state.

Player XP and item proficiency XP must always use distinct labels so their roles are not confused.

## Settled decisions

- Player levels are permanent.
- Player level has no maximum.
- Death does not remove player XP or levels.
- Enchanting uses current-level player XP and cannot reduce a completed level.
- Milestone unlocks and earned perk points remain available after XP is spent.
- Player XP requirements use an authored linear curve beginning at 100 and increasing by 25 per
  level.
- Level 1 awards no perk point; the initial cadence awards one point for every later level.
- Health, Strength, and Defense each have ten ranks and grant +10 HP, +1 strength, and +1 defense
  per rank respectively.
- Perks are player-wide and bounded, and their allocations persist by stable ID.
- Respec will exist, but its item, cost, and transaction are deferred.
- Item proficiency is shared by item type, is earned through gear use, and is never spent.
- Item proficiency unlocks rune sockets.
- Runes are removable per-copy customization.
- Enchantments are permanent per-copy stat improvements.
- Version-one enchanting uses XP without a second core currency.
- Version-one enchanting offers deterministic choices rather than random rolls.

## Open design decisions

- long-term tuning of the linear XP curve;
- future XP sources and reward values beyond the provisional ten XP per kill;
- milestone levels and their unlock table;
- perk-point behavior after every bounded perk rank has been purchased;
- respec item, cost, refund, and interface rules;
- concrete mobility and recovery behavior;
- final rarity names, tier count, base-stat budgets, and improvement capacities;
- item proficiency profiles for future gear;
- enchantment tiers, costs, effects, stacking, replacement, and removal;
- whether later enchantments require materials;
- rune rarity rules, unique abilities, duplicate limits, and acquisition sources;
- compatibility rules for future ranged and magic weapons;
- deterministic stacking order across every source of a stat.
