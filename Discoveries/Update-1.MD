# Colony Ship Rebalance Mod — Session Recap

## Project Context
Rebalance mod for Colony Ship RPG using UE4SS Lua modding framework (stable 3.0.1).
Goal: rebalance feats for solo/melee builds, force recalc on load, add steal interactions to NPCs.
Claude role: primary developer.

## Decisions Made This Session

### UE4SS Version
- Switched from dev build to stable 3.0.1
- Dev build had broken `ProcessEvent` on AActor-typed objects (nullptr crash regardless of approach)
- Stable 3.0.1 also cannot call Blueprint UFunctions directly from Lua via ProcessEvent or metamethod call
- Both versions: direct UFunction invocation on Blueprint actors is not reliably supported

### Hook Registration Timing Fix (Critical)
- Root cause of feat effects not applying on load: feat Blueprint classes were not instantiated until character screen was opened, so `NotifyOnNewObject` callbacks fired too late (17 seconds after load recalc)
- Discovery: feat CDOs are in memory from the start — `StaticFindObject` on `Default__FeatName_C` paths returns valid objects immediately
- Fix: moved all `RegisterHook` calls into a single `NotifyOnNewObject` for `HumanRpgCharacter_C`, which fires before the load recalc
- All 11 hooks now register at the same timestamp as `HumanRpgCharacter_C` loads, before reason=2 recalc runs
- The reason=2→3 upgrade hook was tested and found unnecessary once hooks register at correct time — removed

### Hook Architecture
- Replaced: individual `HookFeat()` + `NotifyOnNewObject` per feat class
- Replaced: separate `NotifyOnNewObject` for `FeatBase` and `ItsBpLib_C`
- Current: single `NotifyOnNewObject` for `HumanRpgCharacter_C` containing all `RegisterHook` calls via `TryHook` helper
- `ForEachUObject` used to cache `cachedCalcFn`, `cachedVCOStealFn`, `cachedPlotCDO` at startup (runs during `RunMod`)

### ForEachUObject Caching
- `StaticFindObject` with colon-separated function paths (e.g. `ClassName:FunctionName`) returns objects that pass `IsValid()` but crash on use — do not use
- `FindFunction` on `UBlueprintGeneratedClass` crashes in both stable and dev builds
- `ForEachUObject` matching by `GetFName():ToString()` is the only reliable way to cache UFunction references
- All three cached: `Calc Char Effects Feats` (on HumanRpgCharacter_C), `VCO_Steal`, `Default__PlotFuncs_C` CDO

### VCO_Steal Status
- NPC_Steal_1 through NPC_Steal_5: all confirmed in ThePit level
- `BasicOverheadWidgetComponent` (VCO): found via `npc:GetComponentByClass(BWClass)` — works
- `ItsVisibilityComponent_C`: found via `FindAllOf` + filter by `GetOuter():GetFName():ToString()` matching NPC name — works
- `VCO_Steal` UFunction signature confirmed from dump: `Steal Type` (byte), `Skill Level` (int), `Item` (InvItem struct), `Credits Bonus` (int), `VCO` (object), `Animated NPC` (object), `Visibility Set` (object), `__WorldContext` (object), `Specialist` (object)
- Direct call via ProcessEvent or UFunction metamethod: does not work in stable or dev
- Status: UNRESOLVED — steal task deferred to next session

### Player Character Identification
- `GetPlayerController().Pawn` returns `RpgCamera_C` (camera actor), not the player character
- `GameplayStatics:GetPlayerCharacter` returns nil
- `GetCharID()` returns different values between dev (1) and stable (1000+) builds
- Correct approach: `FindAllOf("HumanRpgCharacter_C")` + `IsPlayerControlled()` filter
- 39 HumanRpgCharacter_C instances exist in ThePit

## Confirmed Working Functions/Solutions
- `NotifyOnNewObject` on `HumanRpgCharacter_C` as master hook registration point
- `ForEachUObject` for UFunction caching
- `StaticFindObject` on `Default__ClassName_C` paths for CDO access
- `FindAllOf("ItsVisibilityComponent_C")` + outer name filter for component lookup
- `npc:GetComponentByClass(BWClass)` for BasicOverheadWidgetComponent
- `FindAllOf("HumanRpgCharacter_C")` for character enumeration
- `char:GetCharID()` works but returns different values per UE4SS version
- `char:IsPlayerControlled()` — untested but expected to work, use to identify player
- `reasonParam:set(3)` inside CalcFeatEffects hook — works (ultimately not needed)
- `RegisterHook` on Blueprint functions works when called after class is in memory

## Confirmed Non-Working / Invalid APIs (Stable 3.0.1)
- `ProcessEvent` on AActor-typed Blueprint instances — nullptr crash
- Direct UFunction call via `obj["FuncName"](obj, params)` — returns function object, does not execute
- `FindFunction` on UBlueprintGeneratedClass — crashes
- `StaticFindObject("Path:FunctionName")` — returns fake-valid object, crashes on use
- `GetTypedOuter` — not available
- `ForEachComponent` — not available
- `GetClass()` on Blueprint instances — returns invalid wrapper

## Key Object Paths Confirmed
- Player character class: `/Game/Gameplay/Characters/Core/HumanRpgCharacter.HumanRpgCharacter_C`
- Feat base: `/Game/Gameplay/Feats/BaseTypes/FeatBase.FeatBase_C`
- PlotFuncs CDO: `/Game/Gameplay/Plot/PlotFuncs.Default__PlotFuncs_C`
- PlotFuncs class: `/Game/Gameplay/Plot/PlotFuncs.PlotFuncs_C`
- VCO component class: `/Game/Gameplay/System/BasicOverheadWidgetComponent.BasicOverheadWidgetComponent_C`
- Visibility component class: `/Game/MapObjects/ItsVisibilityComponent.ItsVisibilityComponent_C`
- NPC_Steal actors: `/Game/Maps/ThePit.ThePit:PersistentLevel.NPC_Steal_1` through `NPC_Steal_5`
- NPC_Steal actor class: `AnimatedProp_C`
- VCO_Steal UFunction: found via `ForEachUObject` matching name `"VCO_Steal"`

## VCO_Steal UFunction Signature (from dump)
- Steal Type     — ByteProperty  [o: 0]
- Skill Level    — IntProperty   [o: 4]
- Item           — StructProperty InvItem [o: 8] size 28 bytes
- Credits Bonus  — IntProperty   [o: 28]
- VCO            — ObjectProperty BasicOverheadWidgetComponent [o: 30]
- Animated NPC   — ObjectProperty AnimatedProp_C [o: 38]
- Visibility Set — ObjectProperty ItsVisibilityComponent_C [o: 40]
- __WorldContext — ObjectProperty [o: 48]
- Specialist     — ObjectProperty RpgCharacter_C [o: 50]

## Calc Char Effects Feats Signature (from dump)
- Reason         — ByteProperty [o: 0]  (known values: 0=init, 2=load, 3=gameplay, 4=UI update)
- Is Updated     — BoolProperty [o: 1]  (out)
- Effects to Sum — ArrayProperty [o: 8]
- Default Objects — ArrayProperty [o: 20]
- Recalc Required — BoolProperty [o: 18] (out)

## What Still Needs Discovery / Resolution

### VCO_Steal — Main Task for Next Session
- Goal: add steal interaction to NPCs that don't have it (beyond NPC_Steal_1..5)
- Need: working method to call `VCO_Steal` on a PlotFuncs CDO with correct params
- Blocker: ProcessEvent does not work on stable for Blueprint functions
- Possible approaches to investigate:
  - Hook an existing game function that runs in a context where ProcessEvent works
  - Find a native C++ wrapper that calls VCO_Steal internally
  - Find if there is a level Blueprint function or event that can be triggered
  - Investigate whether `RegisterHook` post-hook return value modification can inject new steal setups
  - Check if `AnimatedProp_C` has any property that enables steal behavior directly without VCO_Steal call

### Player Character Identification
- Confirm `IsPlayerControlled()` works on `HumanRpgCharacter_C` instances to identify player
- Confirm stable build charID for player character

### InvItem Struct
- Full field layout unknown — needed if VCO_Steal must pass a real item
- Path: `/Game/Gameplay/Items/BaseTypes/InvItem.InvItem` size 28 bytes

## Mod Current State
- Feat hooks: all working, firing on load correctly
- CDO text patching (descriptions): working
- Config system: working
- Localization: working
- Berserker, Juggernaut, LoneWolf, Warrior, Gladiator, Basher, Butcher, HeavyHitter, Educated, MasterTrader, ToughBastard, Mastermind, Gifted, FastRunner, HealingFactor: all working
- Bionic/GetMaxImplants: partially working, needs testing
- VCO_Steal / AddSteal: not working, deferred
