# Arena Brawler — Unity Remake Brief

> Paste everything below this line into a fresh Claude session to start the Unity project.

---

I'm remaking my arena brawler in **Unity**, using **Blender MCP** for custom 3D assets and buying **Unity Asset Store packs** where they save time. I already built and playtested a full prototype in Godot 4. This brief carries over everything that worked: the game's goal, every class and ability with tuned numbers, the shared combat systems, and the lessons learned. Treat the numbers as playtested starting values, not final balance.

## 1. Goal of the game

A **competitive, high-skill-ceiling PvP arena brawler**: short, intense team fights in a small arena, decided by aim, dodging, positioning, and cooldown trading rather than stats or items.

- **References:** **Battlerite** (the core feel: WASD movement, mouse-aimed skillshots, no auto-targeting, parry/counter mindgames, small arenas) and **League of Legends Arena** (small-team fights in a compact arena).
- **Modes:** **3v3 is the main mode**, and everything (map size, class roles, balance) should be designed around it first. **2v2** is the secondary mode. **1v1** is a practice mode only (learning a class, testing, fighting bots).
- **Perspective:** **3D**, like both references: fully 3D characters and arena, an angled top-down camera, and gameplay on a flat ground plane (all logic is 2D on the XZ plane).
- **Platform:** PC, mouse and keyboard. Steam is the eventual target.
- **Design pillars:**
  1. **Movement feels great.** Acceleration/friction movement, a snappy dash with momentum carry, and a dash that cancels ability recovery.
  2. **Every hit is earned.** Skillshots, no auto-aim, readable wind-ups, and projectiles that hit the first body they touch, so allies can body-block.
  3. **Risk/reward ability design.** Cast times lock you in, recovery windows punish whiffs, and a parry rewards reading your opponent.
  4. **Instant readability.** Every ability has a distinct visual signature, and team colors (blue = your team, red = enemy) are on everything.

## 2. Controls

| Input | Action |
|---|---|
| WASD | Move |
| Mouse | Aim (abilities fire toward the cursor) |
| LMB (hold) | Auto-attack, auto-repeats |
| E / Q / F | Ability 1 / 2 / 3 |
| Shift | Defensive/utility ability |
| R | Ultimate (charge-based) |
| RMB or G | Parry |
| Space | Dash in the movement direction (or facing if standing still) |

Ability presses are buffered for **150 ms**: a press made slightly too early (mid-cast, on cooldown, stunned) fires the moment it becomes possible instead of being dropped.

## 3. Shared combat systems (all classes)

Distances are in **meters** (Unity units). Speeds are m/s.

**Movement**
- Max speed **8.7 m/s**, acceleration **69 m/s²**, friction **33 m/s²**.
- Dash: **25.5 m/s for 0.13 s** (about 3.3 m). **70%** of dash velocity carries into normal movement afterward. **2 charges**, each regenerates in **4.0 s**. (Regen was raised from 2.5 s because kiting classes had near-permanent dash uptime.) Dashing cancels an ability's recovery.
- Character collision radius **0.68 m**.

**Ability flow**
- Most abilities have **cast time** (locked in, can't move) → effect → **recovery** (can be dash-cancelled). Some are instant.
- After any non-auto ability, a **0.135 s commitment window** blocks starting another ability. This prevents frame-perfect ability stacking.
- **Interrupts:** damaging an enemy mid-cast cancels the cast and stuns them **0.5 s**.

**Parry** (RMB/G)
- **0.22 s** window, **5 s** cooldown. A parried hit is fully negated.
- The attacker is stunned **0.65 s**, but only if they're within **4 m**. Melee gets punished; a ranged attacker across the map doesn't get stunned by a parry they couldn't react to.
- Duelist gets a bonus on a successful parry (see Duelist).

**Ultimate charge**
- Fills passively in **30 s**, or in **20 s** while "engaged" (you dealt damage or healing in the last 3 s).

**Hit rules**
- **Directional melee:** stationary swings hit whoever is in front of you within a **50° half-angle cone**, not the nearest enemy. Aim picks the target in team fights.
- **Body-blocking:** damage projectiles hit the **first enemy body they touch**, not their intended target. Heal projectiles stay locked on their intended ally.
- **Hitstop:** **0.025 s** on the attacker and **0.042 s** on the defender for every landed hit.
- All damage and healing **round to whole numbers**, so a lethal hit lands HP exactly on 0.

**Anti-stall:** after **120 s** of match time, all healing loses **1% effectiveness per second**, reaching zero at 220 s. Show a HUD indicator ("−X% HEALING").

**Crowd control and status:** stun, freeze (a stun with an ice visual), root (can't move, can still act), slow (% move speed), knockup (airborne, still damageable), healing reduction (Grievous Wounds style), CC immunity, damage reduction, absorb shields, heal-over-time, invisibility.

**Map:** the prototype's base layout is a **37.2 × 20.4 m** rectangle with **6 low obstacles** for cover (symmetric), scaled **×1.6 for 3v3** (about 59.5 × 32.6 m) and **×1.3 for 2v2** so team modes have room to flank. 1v1 practice uses the base size. Since 3v3 is now the main mode, the remake should design its arena at 3v3 scale first and derive the smaller ones from it. **2 health packs** in the center lane heal **25**, respawn after **15 s**, pickup radius **0.88 m**.

## 4. Classes

Five playable classes. "× combo" means the value is multiplied by the class's combo multiplier.

### Duelist — melee glass cannon
**HP 203** · standard speed · 2 dash charges

**Passive (combo stacks):** landing hits builds stacks: **+16% damage per stack, max 3** (+48%), decaying after **2.9 s** without a hit.
**Passive (Blood-lust):** a successful parry grants **+10% attack speed and move speed for 1.5 s**.

| Key | Ability | Details |
|---|---|---|
| LMB | **Auto** | 7.5 dmg, 0.55 s CD, 3.0 m range, 70° swing |
| E | **Strike** | 0.09 s cast. 17.25 dmg × combo, 2.9 m range, 110° swing. Slows 30% for 2 s and applies **−25% healing received for 3 s**. 2.5 s CD |
| Q | **Lunge** | 0.14 s cast. Dashes up to 5.4 m (0.13 s), strikes for 29.3 dmg × combo, **stuns 0.75 s**. Landing it grants **+30% attack speed for 2 s**. Whiffing has a longer recovery (0.45 s vs 0.22 s). 6.5 s CD |
| F | **Sword Throw** | 0.12 s cast. Skillshot, 28 m/s, 0.5 m hit radius. 9.5 dmg, plus up to +12.65 based on the target's missing HP, all × combo. Slows 30% for 2 s. 4 s CD |
| Shift | **Iron Resolve** | Needs ≥1 combo stack. Consumes all stacks for **10% damage reduction per stack** (max 30%) for 3 s. 9 s CD |
| R | **Bladestorm** | Spin for **1.5 s**, hitting everyone within 3.4 m every 0.3 s for 17.1 (up to 5 hits = 85.5). Full move speed and **slow-immune** while spinning. Visual: large **red sword silhouettes** flung outward in an even 360°, red glow, **no screen shake** |

**Feel:** all-in assassin. Builds stacks with autos and Strike, closes with Lunge, cashes in. Fragile if the Lunge whiffs. The best duelist players parry-bait.

### Mage — ranged burst
**HP 162** (lowest) · standard speed

**Passive (Overcharge):** every **2 consecutive landed Bolt or Arcane Fan hits** shaves **0.3 s** off Bolt's and Burst's cooldowns. A miss resets the streak. Rewards accuracy.

| Key | Ability | Details |
|---|---|---|
| LMB | **Auto Shot** | 6.75 dmg projectile, 27.2 m/s, 0.56 m radius, 0.75 s CD |
| E | **Bolt** | 0.25 s cast. 22 dmg skillshot, 36 m/s, 0.4 m radius. Slows 25% for 1.5 s. 3.5 s CD |
| Q | **Burst (Nova)** | 0.2 s cast. AoE around self, 3.8 m radius: 20 dmg + **1 s freeze**. 4.5 s CD. The self-peel tool |
| F | **Arcane Fan** | Three bolts in a 26° spread, 12 dmg each (36 if all land), 30 m/s. 5 s CD. Best up close |
| Shift | **Barrier** | 35 HP absorb shield for 1.5 s. 7 s CD |
| R | **Void Collapse** | 0.35 s cast. Opens a rift on the target that **pulls them toward its center for 1.5 s** (they can fight the pull), then detonates: **45–92 dmg** scaled by how close they are (zero bonus beyond 6.4 m), plus a **1 s stun if within 1.8 m** |

**Feel:** kite, land skillshots, punish divers with Burst. Highest burst at range; dies fast if caught.

### Bruiser — tank / CC brawler
**HP 223** (highest) · **7.4 m/s** (slowest) · accel 56, friction 28 · **only 1 dash charge**

**Passive (Steady Footing):** incoming stuns and freezes are **15% shorter**, and ability recovery doesn't slow movement.
Builds combo stacks like the Duelist.

| Key | Ability | Details |
|---|---|---|
| LMB | **Smash** | 2.7 dmg × combo, 0.7 s CD, 3.34 m range, 80° swing. Low damage; mostly builds stacks |
| E | **Shatter** | **Instant.** Shield slam: 19.8 dmg × combo, **stun 0.7 s**, 3.0 m range, 100° swing. 5.5 s CD |
| Q | **Tremor** | **Instant.** Ground stomp, 3.6 m radius: 16.2 dmg × combo + **50% slow for 2 s** to every enemy in range. 8 s CD |
| F | **Warcry** | You take **15% less damage** and enemies within 4.2 m deal **10% less damage**, for 4 s. 8 s CD |
| Shift | **Unbreakable** | **Usable while stunned.** Cleanses all CC, then **CC immunity + 25% damage reduction + 30% move speed** for 2.5 s. 8.5 s CD |
| R | **Seismic Slam** | Auto-targets the opponent. Lunges up to 5.6 m and slams for **49.5 dmg**, **knocking up for 1 s** (target is airborne and still damageable). 3.96 m range |

**Feel:** walk in, chain CC (Shatter stun → Tremor slow → Seismic knockup), survive with Unbreakable and Warcry. Wins long fights; kited by good rangeds. Visual: carries a sword and a round shield.

### Ranger — mobile kiter / trapper
**HP 176** · **8.9 m/s** (fastest base speed)

**Passive (Momentum):** each consecutive landed Quick Shot grants **+4% move speed, max 5 stacks** (+20%). Resets on a miss or after 2.5 s without landing one. No combo system.

| Key | Ability | Details |
|---|---|---|
| LMB | **Quick Shot** | 7.5 dmg arrow, 30 m/s, 0.36 m radius, 0.5 s CD. Builds Momentum |
| E | **Piercing Shot** | 0.18 s cast. 22.4 dmg, **passes through** every enemy in its path, 34 m/s. Slows 20% for 1 s. 4 s CD |
| Q | **Snare Trap** | Placed 2.2 m ahead. **1.5 m radius**, arms after **0.5 s** (can't be dropped on someone for an instant root), lasts 8 s. Roots the first enemy to step on it for **1.2 s**. **Invisible to the enemy team**; reveals itself when it fires. 7 s CD |
| F | **Disengage** | Fires a 15 dmg shot forward and **recoils you backward** about 3.9 m (forced 28 m/s for 0.14 s, ignores input). 6 s CD |
| Shift | **Camouflage** | **True invisibility to the enemy team for 3 s** (no model, no HP bar). Allies see a translucent ghost. **Any attack breaks it** (swings, projectiles, traps, Rain). 10 s CD |
| R | **Rain of Arrows** | 0.3 s cast. Zone dropped on the target enemy's position, 2.6 m radius, 2 s: **13.1 dmg every 0.4 s** (5 ticks = 65.5). Consider making it cursor-placed in the remake for more skill expression |

**Feel:** never stand still. Chip with autos, pierce lined-up targets, trap escape routes, Disengage away from divers. Bots played it poorly, but in human hands it was the hardest class to pin down. Watch its kiting power.

### Cleric — support / healer anchor
**HP 176** · standard speed. Every ally-targeted ability falls back to **self** when no ally is in range, so it still works in 1v1 practice.

**Passive (Devotion):** healing, shielding, or cleansing an **ally** (not self) grants **15% damage reduction for 4 s**. Rewards actually supporting.
**Combo stacks** (built by landing Smite) boost **healing by +10% per stack** instead of damage.

| Key | Ability | Details |
|---|---|---|
| LMB | **Smite** | 6 dmg holy bolt, 30 m/s, 0.6 s CD. Builds stacks |
| E | **Mending Light** | 0.2 s cast. Skillshot heal toward the **lowest-HP ally within 8 m**: **32.4 heal** (+10%/stack). An **enemy** it flies through takes **12 dmg + 30% slow for 1 s** instead (body-blocking a heal has a cost). 3 s CD |
| Q | **Consecrate** | **Placed at the cursor**, up to 7 m away. Zone 4.5 m radius, 3 s: every 1 s, **8 dmg to enemies** and **10.8 heal to allies** inside. 8 s CD |
| F | **Purify** | Rectangle cast forward, **6 m × 3.6 m** (wide enough for two allies). **Cleanses all CC/debuffs** from allies hit (including self), plus a **HoT of 8.1/s for 4 s**, plus an instant **12 heal to self**. 10 s CD |
| Shift | **Guardian Ward** | Shield on the lowest-HP ally within 8 m: **25 + 7.5 per combo stack** (stacks are **not** consumed), 3 s. 9 s CD |
| R | **Guardian's Bond** | **Usable while stunned.** Links you and the lowest-HP ally in range for **4 s**: damage either takes is **split 50/50**, both get **20% damage reduction + HoT 6.75/s**. No ally in range: self-only (still gets the reduction and HoT) |

**Feel:** the team's anchor. Keeps the team alive through burst, cleanses CC chains, and still pokes. Bots focus healers, so the Cleric's survival is a real skill test.

## 5. Class interactions and general feel

- **Pace:** fast, lethal, small arena. Burst windows matter more than sustained DPS. (For reference, prototype 1v1 bot matches lasted 20–60 s; 3v3 fights should stay short and decisive.)
- **3v3 team roles:** the roster maps naturally onto a 3-person team: a frontline (Bruiser), a damage dealer (Duelist, Mage, or Ranger), and a support (Cleric). Ally-targeted abilities (Ward, Bond, Mending, Purify's two-ally width) were designed with more than one ally in mind.
- **Natural counters:**
  - Duelist and Bruiser dive and chain CC. Mage's Burst freeze and Ranger's Disengage/traps are the answers.
  - Mage and Ranger out-range everyone. Bruiser's Unbreakable (CC-immune, +30% speed) and Duelist's Lunge are the gap-closers.
  - Cleric's healing is countered by Duelist's Strike (−25% healing) and the global anti-stall dampening.
  - Parry punishes predictable melee; ranged players don't get stunned by parries from far away.
- **Team play:** projectiles body-block, so positioning protects your healer. Bots focus-fire the enemy healer and occasionally swap to a low-HP kill target.
- **Skill expression:** leading skillshots, dodging telegraphed wind-ups (wind-ups show particles gathering on the caster), dash-cancelling recovery, parry reads, trap placement, timing Unbreakable/Bond while stunned.
- **Known balance learnings:**
  - Bot win rates were unreliable for kiting and support classes. The bots played Ranger and Cleric badly, while the classes were strong in human hands. Don't balance off bot sims alone.
  - Melee classes dominated bot sims (Duelist ~80%, Bruiser ~85–95% vs other classes).
  - HP totals were raised 35% across the board to soften team-fight burst; damage was left unchanged.

## 6. Visual direction (what worked in the prototype)

- **Team colors on everything:** ground ring, HP bars, slash arcs, trails, hit sparks. Blue = your side, red = enemy. Class is read from the model, team from the color.
- **Per-class FX language:**
  - **Cleric (holy):** thin streaks of gold light rising across zones, a slowly spinning sun-wheel sigil on the ground. Keep it subtle; tall pillars and sky-beams felt too busy.
  - **Mage (arcane):** purple. Expanding rings with counter-rotating rune dashes and radial glint detonations. **No** tall center column (also too busy).
  - **Mage ult (void):** dark core in a glowing shell with particles **spiraling inward** to match the pull.
  - **Bruiser (quake):** rock debris that arcs under gravity, and dark ground cracks radiating from impacts.
  - **Ranger:** arrows (shaft, head, fletching). Rain of Arrows has streaks falling into the zone. The Snare is a mechanical jaw trap: teeth splayed while arming, spring upright when live, snap shut on trigger.
  - **Purify:** a bright light wave sweeping the rectangle away from the caster, with light streaks rising.
- **Combat feedback:** melee slash arcs drawn over the swing's actual hit arc, white hit-flash on the model, death burst plus dissolve, projectile trails with a small dynamic light and an impact pop, motion trails on dashes and lunges, a 3D parry ring, knocked-up fighters visibly launched into the air, and a translucent ghost for allied Camouflage.
- **Lighting:** warm dusk key light with a cool rim light, ACES tonemapping, subtle bloom, soft shadows, slight vignette. FX don't cast shadows.
- **Arena dressing:** stone coliseum, crenellated back wall with a gate and corner towers, torches and braziers with flickering light, swaying red and blue banners, drifting dust motes, low cover obstacles.
- **HUD:** team HP panels in the top corners, a centered ability bar (keycap labels, cooldown fill, ready pulse), overhead HP and cast bars, combo pips, a win banner over a dimmed screen, and a char-select with per-slot class picks for team modes.

## 7. Technical direction for the Unity build

Suggestions; confirm or push back before building:

- **Unity 6 LTS + URP** (good post-processing, VFX Graph, and the stylized look above), with the **new Input System**.
- **Keep the simulation separate from the presentation.** This was the best architecture decision in the prototype. Gameplay ran on plain 2D data (position, velocity, timers, HP) with no knowledge of models or FX. A view layer watched that state and drew everything. That made a **headless balance simulator** possible (thousands of bot-vs-bot matches across every matchup), and it will make networking much easier.
- **Data-driven abilities:** ScriptableObjects for class stats and ability definitions (damage, cast, recovery, cooldown, range, shape, CC), so tuning doesn't need code changes.
- **Decide networking early.** Battlerite and League are online games, and that choice (e.g. Netcode for GameObjects, Fish-Net, or Photon Fusion; server-authoritative vs. rollback) shapes the whole architecture. Local play vs bots can come first, but the sim should be written to support it.
- **Camera:** fixed-angle 3D camera on the flat play plane, like the references. The prototype used a fixed ~45° orthographic camera framing the whole arena (no hidden zones). A Battlerite-style perspective camera with a slight lean toward the cursor is an option.
- **Bots:** keep a simple decision-loop AI (dodge telegraphs, use abilities on cooldown, strafe, focus healers with a dwell timer). Needed for solo testing and the balance sim.

**Assets:**
- **Characters and animation:** the prototype used free Quaternius "RPG Characters" models (Warrior, Wizard, Monk, Ranger, Cleric, Rogue). For a polished look, consider Synty POLYGON fantasy packs or similar stylized character packs, plus animation packs (Mixamo for free, or Kevin Iglesias packs on the Asset Store) for melee, casting, bow, and hit/death sets.
- **VFX:** Asset Store VFX packs (e.g. Hovl Studio, Gabriel Aguiar) for spell bases, recolored per class to match the FX language above.
- **Environment:** a modular stylized castle or coliseum kit (the prototype used Kenney's free Castle Kit).
- **Blender MCP:** use it for bespoke props that packs won't have: the Bruiser's round shield, Bladestorm sword silhouettes, the snare's jaw teeth, Duelist's throwing sword, banners, arena centerpiece emblem, weapon variants. Leave rigged characters to purchased packs.

## 8. Roadmap ideas carried over

- **Rogue** (planned): burst damage and stealth. A model already existed.
- **Captain** (planned): melee healer/buffer that protects allies up close, distinct from the ranged Cleric.
- Grievous-Wounds healing reduction on more classes (only Duelist's Strike has it now).
- Ranger's long-term balance: it was bot-weak but human-strong. Its true invisibility and hidden traps are recent buffs, so watch them in playtests.

## 9. How I like to work

- I'm the playtester and I'll report how things feel; you implement. Make reasonable calls without asking about every detail.
- Verify your own work before telling me it's done (compile checks, automated or headless tests, temporary test scenes you delete afterward).
- Git: all work on a `dev` branch; `main` only updates via PR from `dev` when I ask. Clear commit messages that explain *why*.
- When I give balance numbers, apply them exactly and update the in-game tooltips to match.
- Don't control my computer to look at visuals. Tell me what to check and I'll look myself.

**First step:** propose the Unity project structure and core architecture (sim/view split, ability data model, networking choice), then build movement, dash, and the Duelist in a test arena so I can validate the feel before anything else.
