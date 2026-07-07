# TODO / Roadmap

## New classes

- **Captain** (eventually) — melee healer/buffer. Distinct from Cleric
  (which is a ranged/kiting support): gets into melee range to protect and
  buff allies rather than sustaining from a distance.
- **Rogue** — burst damage, stealth. `Rogue.gltf` + dagger texture already
  exist in `godot_project/assets/RPG Characters - Nov 2020/glTF/`, so the
  3D model is ready; needs a kit designed and built following the
  Entity/PlayerController/BotController/View3D pattern the other classes use.

## Balance / kit work

- Add a healing-reduction effect (Grievous-Wounds style: hitting an enemy
  reduces healing they receive for a duration) to Duelist and Bruiser.
  ("Warrior" = Duelist — its 3D model is `Warrior.gltf`; there's no
  separate Warrior class in the roster.) Distinct from the global
  time-based anti-stall healing dampening added this session
  (`Entity.heal_dampen_mult()`) — this would be a combat-triggered ability/
  passive effect specific to these two classes' kits, not a match-clock
  mechanic.
