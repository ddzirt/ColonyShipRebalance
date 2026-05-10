# Colony Ship Feat Rebalance — Contributor Guide

## What This Mod Does

Rebalances feats (perks) in Colony Ship RPG via UE4SS Lua scripting. Goals:

- Support solo and solo-melee builds through most of the game without a full party
- Make single-save achievement runs viable by reducing forced multi-playthrough requirements
- Expose all numeric tuning via `config.ini` so changes don't require editing Lua

---

## Technical Foundation

| Item | Detail |
|---|---|
| Framework | UE4SS (Unreal Engine 4 Scripting System) — latest dev build or stable 3.0.1 |
| Language | Lua |
| Entry point | `main.lua`, loaded by UE4SS at game start |
| Config | `config.ini` — all tunable values, parsed at startup |
| Localization | `localization/descriptions-[lang].lua` — falls back to `en` |

---

## Architecture

### Startup Sequence

```
RegisterInitGameStatePostHook  (fires on every world load)
  └─ RunMod()
       ├─ InitLog()           opens RebalanceLog.txt in append mode
       ├─ LoadConfig()        reads config.ini, merges with DEFAULTS
       ├─ LoadDescriptions()  loads localization file
       └─ PatchCDOs()         writes Description/Requirement FText to feat CDOs
```

`NotifyOnNewObject` on `HumanRpgCharacter_C` fires once and registers all gameplay hooks.

### Two Hook Types

**`Get Effects`** — fires unconditionally every time the game recalculates a character's stat block. Used for bonuses that are always active (XP bonuses, flat damage, regen scaling). All handlers share a single `FeatBase:Get Effects` hook dispatched via the `FeatBaseHandlers` table.

**`Get Conditional Effects`** — fires only when the feat's condition is currently true. Used for bonuses that depend on a runtime state (solo condition, HP ratio). Each feat gets its own hook.

**`Is Available To Learn`** — fires when the feat selection UI queries availability. Used to gate feats behind stat minimums.

### Dispatch Table (`FeatBaseHandlers`)

The `FeatBase:Get Effects` hook extracts the feat class name from `self:GetFName()`, strips the `Default__` prefix and numeric instance suffix, then looks it up in `FeatBaseHandlers`. Adding a new `Get Effects` feat means adding one entry to this table — no other wiring needed.

```lua
["F_YourFeat_C"] = function(char, ref)
    Set(ref, F.SomeField, someValue)
end,
```

### Field Name Table (`F`)

`CsgCharEffects` is a Blueprint UserDefinedStruct. Its property names are GUID-mangled and cannot be guessed — they were extracted from a 230k-line UE4SS object dump. All confirmed field names live in the `F` constant table at the top of `main.lua`. Always use `F.FieldName` rather than the raw string.

Currently mapped fields:

| Key | Stat |
|---|---|
| `F.Evasion` | Evasion modifier |
| `F.Initiative` | Initiative modifier |
| `F.MaxAP` | Max AP modifier |
| `F.ArmorPenalty` | Armor Handling (same stat as ArmorPenaltyMod in-game) |
| `F.MeleeTHC` | Melee to-hit chance |
| `F.MeleeCSC` | Melee carve/crit strike chance |
| `F.MeleeMinDMG` | Melee minimum damage |
| `F.MeleeMaxDMG` | Melee maximum damage |
| `F.NaturalDR` | Natural damage reduction |
| `F.KnockdownChance` | Knockdown critical chance |
| `F.PenetrationPct` | Penetration percent |
| `F.AimedTHC` | Aimed (marksmanship) to-hit chance |
| `F.MaxHP` | Max HP modifier |
| `F.SkillXPGain` | Skill XP gain percent |
| `F.CSC` | Critical strike chance (global) |
| `F.HPRegen` | HP regeneration rate |

If you need a field not in this table, run a UE4SS object dump and search for the stat name in `CsgCharEffects`.

### Character Data Helpers

All return `nil` on failure — always guard before arithmetic.

```lua
GetAttribute(char, statMapping.INT)                  -- base stat value
GetSkillLevel(char, skillsMapping.Bladed, true)      -- skill level; tagged=true includes tag bonus
GetHP(char)                                          -- returns curHP, maxHP, ratio (0.0–1.0)
GetCharLevel(char)                                   -- character level, returns 0 on failure
```

Stat indices (`statMapping`): `STR=0, DEX=1, CON=2, PER=3, INT=4, CHA=5`

Skill indices (`skillsMapping`): `Bladed=0, Blunt=1, Pistol=2, Shotgun=3, Rifle=4, SMG=5, CriticalStrike=8, Evasion=9, Armor=10, Biotech=11, Computers=12, Electronics=13, Persuasion=14, Streetwise=15, Impersonate=16, Lockpick=17, Steal=18, Sneak=19`

---

## Adding a New Feat

### Case 1: Always-active bonus (`Get Effects`)

1. Add an entry to `FeatBaseHandlers`:

```lua
["F_YourFeat_C"] = function(char, ref)
    local val = GetAttribute(char, statMapping.INT) or 0
    if val > 0 then
        Set(ref, F.SkillXPGain, val * cfg.YOUR_CONFIG_KEY)
    end
end,
```

2. Add the config key to `DEFAULTS` and `config.ini`.
3. Add description text to `localization/descriptions-en.lua`.

No hook registration needed — the dispatch table handles it automatically.

### Case 2: Condition-dependent bonus (`Get Conditional Effects`)

1. Define a handler function:

```lua
function YourFeatHandler(self, OwnerCharacter, Effects, IsValid)
    if not IsConditionMet(IsValid) then return end
    local ref = GetEffects(Effects)
    if not ref then return end
    local char = GetChar(OwnerCharacter)
    if not char or not char:IsValid() then return end
    Set(ref, F.SomeField, cfg.YOUR_VALUE)
end
```

2. Register it inside the `NotifyOnNewObject` block:

```lua
TryHook("/Game/Gameplay/Feats/F_YourFeat.F_YourFeat_C:Get Conditional Effects", YourFeatHandler)
```

### Case 3: Stat gate (`Is Available To Learn`)

```lua
function YourFeatHandler(self, OwnerCharacter, Yes)
    local char = GetChar(OwnerCharacter)
    if not char or not char:IsValid() then return end
    local val = GetAttribute(char, statMapping.STR)
    if val and val < cfg.YOUR_MIN then
        Yes:set(false)
    end
end
```

Register with `:Is Available To Learn` instead of `:Get Conditional Effects`.

---

## Localization

Description files live in `localization/`. The active file is selected by `LANGUAGE` in `config.ini` (default: `en`).

Each file returns a function that receives a config accessor and returns a key→text table:

```lua
return function(get)
    return {
        ["/Game/Gameplay/Feats/F_YourFeat.F_YourFeat_C"] = "Your description here.",
        ["/Game/Gameplay/Feats/F_YourFeat.F_YourFeat_C:req"] = "Requires something.",
    }
end
```

The `:req` suffix targets the `Requirement` field. The base key targets `Description`. Both are written as `FText` to the feat CDO via `PatchCDOs`.

**Current limitation:** the system replaces all feat text wholesale. A revised approach (see WIP section) will extract existing CDO text at runtime and apply only targeted changes, making translation files smaller and safer.

---

## Known UE4SS API Constraints

Confirmed non-functional in this UE4SS build — do not attempt:

| API | Status |
|---|---|
| `LogAlways` | Not available |
| `RegisterCustomEvent OnPostLoadMap` | Not available |
| `LoopAsync` / `AsyncSleep` | Not available |
| Blueprint function calls from Lua | Generally not usable — blocker for Skill Monkey and Gifted stat grant |
| Blueprint UserDefinedStruct fields | GUID-mangled names only; no readable property names |

`NotifyOnNewObject` must be called before `RegisterHook` for any Blueprint class not yet loaded into memory at script start.

---

## Configuration Reference

All keys in `config.ini` map directly to entries in the `DEFAULTS` table. Missing keys fall back to defaults. Booleans: `true`/`false`. Numbers parsed automatically.

| Key | Default | Used By |
|---|---|---|
| `LANGUAGE` | `en` | Localization file selection |
| `LW_EVASION` | 16 | LoneWolf |
| `LW_INITIATIVE` | 20 | LoneWolf |
| `LW_ARMOR_PENALTY` | 4 | LoneWolf |
| `WARRIOR_ARMOR_PER_LEVEL` | 1 | Warrior |
| `BERSERK_MID_HP_PCT` | 0.50 | Berserker tier 1 threshold |
| `BERSERK_LOW_HP_PCT` | 0.25 | Berserker tier 2 threshold |
| `BASHER_THC` | 8 | Basher |
| `BASHER_KNOCKDOWN` | 20 | Basher |
| `BASHER_AIMED_PER_LEVEL` | 2 | Basher |
| `BUTCHER_THC` | 8 | Butcher |
| `BUTCHER_CSC` | 20 | Butcher |
| `BUTCHER_PEN_PER_LEVEL` | 2 | Butcher |
| `JUGG_MID_HP_PCT` | 0.50 | Juggernaut tier 2 threshold |
| `JUGG_LOW_HP_PCT` | 0.25 | Juggernaut tier 3 threshold |
| `EDUCATED_SXP_BONUS` | 15 | Educated |
| `EDUCATED_INT_MIN` | 6 | Educated gate |
| `MASTERMIND_SXP_BONUS` | 25 | Mastermind |
| `GIFTED_SKILL_SXP` | 15 | Gifted |
| `HF_REGEN_PER_LEVELS` | 3 | HealingFactor |
| `HF_BASE_REGEN` | 3 | HealingFactor base value |
| `FR_EVASION` | 6 | FastRunner |
| `GLADIATOR_MIN` | 1 | Gladiator |
| `GLADIATOR_MAX` | 1 | Gladiator |
| `HH_PER` | 3 | HeavyHitter |
| `HH_CRIT_PER_STEP` | 1 | HeavyHitter |
| `TB_CON` | 6 | ToughBastard gate |
| `BIONIC_IMPLANTS` | 2 | Bionic |
| `MASTER_TRADER_CHA` | 6 | MasterTrader gate |
| `DEBUG` | false | Enable all logging |
| `DEBUG_ONLY_CONSOLE` | false | Log to console only, skip file |

---

## WIP / Post-1.0

The following are in scope for the mod but blocked or incomplete. Not part of the 1.0 release.

**Gifted — stat point grant**
The SkillXP bonus (+15%) works. The intended +1 unspent stat point grant has no confirmed Lua-accessible API. Blueprint functions required to award stat points are not callable from Lua in this UE4SS build. Potentially could be worked around by hooking into text block showing available stat points but this is not tested yet and may not work as expected. C++ may be required to implement this.

**Bionic — party member support**
Currently applies to the player character only (charID 1 or 1000 depending on UE4SS build). Extending to party members requires a reliable way to identify which party characters have the Bionic feat without triggering on every character in the world — not yet solved.

**Skill Monkey — full implementation**
Vanilla: +35% skill XP gain on Science and Stealth skills. Intended change: raise to +50%. Blocked because Skill Monkey uses Blueprint functions internally to apply its per-skill bonus, and those functions are not accessible via the Lua API. The feat either has no effect or behaves incorrectly under the current hook approach. Needs further investigation of the object dump for an alternative path. There is a potential solution to this issue using `SkillXpGainCoef`.

**Revised language support**
The current system requires a complete description file that replaces all feat text unconditionally. The planned approach is to extract existing localized text from CDOs at runtime and apply only targeted changes — specifically numeric values that differ from vanilla. This makes description files much smaller, eliminates risk of accidentally overwriting text for unmodified feats, and makes the mod more robust across game patches.
