# Stable Foundations

## Removing the mod from a save

While Stable Foundations is still enabled, run this command in the game chat:

```text
/stable-foundations-prepare-removal
```

Then save the game, disable or remove Stable Foundations, and load that saved game.
In multiplayer, an administrator or the server console must run the command.

The command removes Foundation tooltip fields, including duplicate and untracked
fields, from entities on every surface. It also removes hidden foundation bonus
beacons and this mod's render objects, restores the original destructibility of
entities whose invulnerability override is still tracked, and clears saved
reinforcement state. It preserves other mods' tooltip fields and render objects,
player buildings, flooring, inventories, and unowned invulnerability flags.

Reinforcement stays suspended in this save, including after saving, loading, or
changing other mods, so bonuses cannot be recreated before removal. Running the
command again is harmless. If you change your mind, reload a save made before
running the command.

## Why cleanup must happen before removal

Factorio calls configuration-change handlers only for active mods. A disabled or
deleted mod cannot run its cleanup code. Runtime entity tooltip fields and the
`destructible` flag are saved on the entity, rather than automatically removed
with the mod. Missing translation keys such as `sf-mod.foundation-label` are
leftover tooltip fields whose translations disappeared with Stable Foundations.

The mod's hidden beacon and module prototypes disappear when the mod is removed,
so their speed, productivity, and efficiency bonuses disappear automatically.
Prototype changes are rebuilt from the remaining enabled mods as well. Damage
reduction stops when Stable Foundations' event handlers are removed. Persistent
tooltips and invulnerability overrides need the preparation command above.

## Saves already affected by removal

Adding version 1.6.2 or newer to an affected save removes orphaned Foundation
tooltip fields when the save loads and applies current reinforcement to eligible
buildings already on supported flooring. Updating an existing installation also
deduplicates tracked Foundation fields and refreshes their values. The preparation
command then clears any remaining fields without relying on saved tooltip IDs.

If the game was saved without Stable Foundations, Factorio may have discarded
the mod's ownership records. Reinstalling cannot reliably recover the original
destructibility of previously protected entities. Use a save made with Stable
Foundations still enabled and run the preparation command there to restore those
flags. The cleanup deliberately avoids making unrelated indestructible entities
destructible.

## Damage handling

Ordinary hits use the entity's live health, preserving repairs and other mods'
health changes. Damage reduction also applies when an unreduced hit would be
fatal: a full-health 5,000 HP building taking 10,000 damage with 75% reduction and
no flat reduction survives with 2,500 HP. The building dies only if the reduced
damage consumes its remaining health.

Factorio clamps health to zero before notifying mods of an overkill hit, hiding
the exact health before that hit. For these hits Stable Foundations uses the last
observed health, assuming full health when no damaged-health record exists.
Damage events, reinforcement updates, player repairs, and the bounded health
refresh keep this fallback current. Robot repairs or direct script changes can
leave it stale until the next observation; this can overestimate or underestimate
remaining health on an overkill hit. Other mods changing health directly should
call `sync_entity_health` immediately afterward. Ordinary hits always use live
health. Safe foundation overrides make their eligible entities indestructible.

Tile placement/removal events update reinforcement immediately. Other mods should
raise `script_raised_set_tiles` and `script_raised_teleported` when changing tiles
or moving entities. For silent floor changes, damaged buildings also check their
whole footprint at most once per second. This avoids a periodic scan of every
building in the factory.

## Remote interface

Other mods can invoke the same cleanup with:

```lua
local result = remote.call("stable-foundations", "prepare_for_removal")
-- result.tooltip_fields: number of Foundation tooltip fields removed
-- result.bonus_beacons: number of hidden bonus beacons destroyed
-- result.invulnerability_overrides: number of owned flags restored
```

Call this from a runtime event with game access, rather than `on_load`.

After changing a reinforced entity's health directly, refresh the overkill fallback:

```lua
entity.health = new_health
local tracked = remote.call("stable-foundations", "sync_entity_health", entity)
-- true: current health recorded (or full-health tracking cleared)
-- false: entity is untracked, invalid, at zero health, or removal is prepared
```

## Validation

`tests/removal-smoke.lua` is the control script for a separate development mod
named `SFRemovalSmoke`, with `base >= 2.1.0` and `? StableFoundations` dependencies.
Install `tests/settings-updates.lua` as that test mod's `settings-updates.lua`,
using a fresh test mod directory so its invulnerability defaults take effect.
These files are not loaded by Stable Foundations itself.

Create a map with version 1.6.1 and the test mod to reproduce the leftovers when
loading that map with Stable Foundations disabled. Load the original map with
version 1.6.2 to verify update recovery and cleanup. Create a map with 1.6.2 to
verify cleanup, then load it both with the mod enabled and disabled for at least
65 ticks to verify the prepared state survives save/load and removal.

The checks cover copied and duplicate fields, untracked fields and beacons on a
second surface, preserved foreign fields and render objects, owned and unowned
invulnerability flags, repeated cleanup, and suspended build/damage handlers.

Additional review fixtures in `tests/` run as separate development mods:

- `review-smoke.lua`, `review-data.lua`, `review-settings.lua`, and
  `review-settings-updates.lua` form `SFReview`. Copy `scripts/tooltip.lua` into
  that fixture's `scripts/` directory as well. Use optional dependencies on
  StableFoundations and space-exploration. The separate `review-se-stub.lua`
  supplies only the tested SE remote contract in an isolated test directory;
  it does not replace the real mod. The checks exercise live health, fatal
  damage, characters/vehicles, cloned flags, silently destroyed entities,
  replacement entities, native tooltips/render objects, and reload behavior.
- `settings-smoke.lua` forms `SFSettingsReview`, depending on StableFoundations.
  Create its save with the previous source, then load the updated source with
  a fresh startup default of 35 for `sf-refined-reduction-percent` to check the
  native tooltip, damage formula, and preservation of an unrelated false flag.
- `zero-bonus-smoke.lua` and `zero-bonus-settings-updates.lua` form `SFZero`,
  depending on StableFoundations, to check zero production bonuses without
  creating a hidden beacon. Damage protection must still work.
- `platform-smoke.lua` forms `SFPlatformReview`, depending on StableFoundations
  and ConcreteInSpace, to check real platform reinforcement and cover removal.
- `early-init-smoke.lua` forms `AAASFInit`, depending only on base, to raise
  tile/build events and prepare removal before Stable Foundations initializes.
- `lethal-smoke.lua`, `lethal-data.lua`, and `lethal-settings-updates.lua` form
  `SFLethalReview`, depending on StableFoundations. Create and reload separate
  75%, 0%, and 100% profiles to check overkill survival, repeated hits, partial
  health, repairs, direct-health synchronization, removal, and mobile protection.
  `lethal-healing-stub.lua` forms the base-only `AAASFLethalHealing` test mod to
  verify health changes from a damage handler that runs before Stable Foundations.

- `event-lifecycle.lua` is a standalone Lua regression. Pass the path to
  `control.lua` as its first argument to compare event subscriptions before and
  after save/load and multiplayer joins, with and without Space Exploration,
  with removal prepared, and with matching or distinct nth-tick intervals. It
  also checks tile placement/removal on a surface different from the actor's.
- `damage-indicator-load.lua` is a standalone Lua regression. Pass the path to
  `scripts/damage.lua` to check notification parity between a running server
  and a freshly loaded client receiving damage before its first tick, both
  with and without the Damage Indicator interface.
- `multiplayer-smoke.lua` forms `SFMultiplayerReview`, depending on
  StableFoundations. Define the startup bool setting
  `wret-overload-disable-overloaded` with default `true` in the fixture's
  `settings.lua`. Its simulated Beacon Rebalance and Damage Indicator interfaces
  check local whitelist restoration, reduced damage, notifications, and the
  absence of beacon resets during reloads and joins. Run a private local server
  without Space Exploration, wait for runtime ticks, and connect a client using
  the same mods to exercise Factorio's saved-event subscription check.

Keep these fixtures and their changed defaults out of normal game mod directories.
Full Space Exploration/Beacon Rebalance gameplay still needs separate integration
smoke tests; the fixtures validate those mods' API contracts and persisted state.

API references: [Factorio data lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html),
[runtime tooltip fields](https://lua-api.factorio.com/latest/classes/LuaEntity.html#set_tooltip_field).
