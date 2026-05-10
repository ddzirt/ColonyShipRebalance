# Colony Ship RPG Rebalance Mod — Session Recap

## Project Context

Developing a Lua rebalance mod for Colony Ship RPG using UE4SS stable 3.0.1.
Goal of this session: add new steal interactions to NPCs in ThePit that lack them.

---

## Architecture (Established Prior Sessions)

- All `RegisterHook` calls consolidated inside a single `NotifyOnNewObject` for `HumanRpgCharacter_C`
- `ForEachUObject` caches `cachedVCOStealFn`, `cachedPlotCDO` (Default__PlotFuncs_C), `cachedCalcFn` at startup
- Feat hooks and steal hooks register when `HumanRpgCharacter_C` loads

---

## Session Goal

Add steal VCO interactions to new NPC targets in ThePit beyond the existing NPC_Steal_1..5.
Specifically: 2-3 money steals and 1 item steal per level, starting with ThePit as proof of concept.
Design rationale: no steal at skill level 2 exists, despite lockpick 2, computer 2, etc. being present.

---

## Decisions Made

- Steal credit amount modification via `Amount:set()` in `ChangeCredits` hook: **retired**. Set succeeds in Lua but engine ignores the modified value.
- NPC substitution (writing `pit["NPC_Steal_1"] = saloonTarget`): **retired**. Hard crash on ObjectProperty write to level BP instance.
- Delegate binding to `OnInteraction` on arbitrary actors: **not exposed** in UE4SS Lua stable 3.0.1.
- Direct `VCO_Steal` invocation via CDO metamethod: **returns function object**, does not execute.
- New steal targets via Lua: **not achievable** on this build. Requires C++ API.
- Session retired. Recommendation documented for future C++ mod.

---

## New Offsets and Structures Discovered

### ThePit_C Level Blueprint
- Live instance name: `ThePit_C_0`, findable via `FindAllOf("ThePit_C")`
- `NPC_Steal_1` through `NPC_Steal_5` are readable `ObjectProperty` fields on the `ThePit_C` instance
- `NPC_Steal_1_ExecuteUbergraph_ThePit_RefProperty` is a separate internal ubergraph ref field
- `Specialist` is a readable `ObjectProperty` on `ThePit_C` instance
- All 5 steal NPCs have individual `BndEvt` handlers in `ThePit_C`:
  - `BndEvt__ThePit_NPC_Steal_1_K2Node_ActorBoundEvent_94_OnInteraction__DelegateSignature`
  - `BndEvt__ThePit_NPC_Steal_2_K2Node_ActorBoundEvent_118_OnInteraction__DelegateSignature`
  - `BndEvt__ThePit_NPC_Steal_3_K2Node_ActorBoundEvent_119_OnInteraction__DelegateSignature`
  - `BndEvt__ThePit_NPC_Steal_4_K2Node_ActorBoundEvent_120_OnInteraction__DelegateSignature`
  - `BndEvt__ThePit_NPC_Steal_5_K2Node_ActorBoundEvent_121_OnInteraction__DelegateSignature`
- Item steal bound events also present:
  - `BndEvt__ThePit_G_Steal_HitKill_Grenade_VCO_K2Node_ActorBoundEvent_144_OnInteraction__DelegateSignature`
  - `BndEvt__ThePit_G_Steal_Meds_Medic_VCO_K2Node_ActorBoundEvent_139_OnInteraction__DelegateSignature`
  - `BndEvt__ThePit_G_Steal_Stims_Medic_VCO_K2Node_ActorBoundEvent_137_OnInteraction__DelegateSignature`

### Execution Order (confirmed)
1. Player interacts with NPC
2. `VCO_Steal` executes on `PlotFuncs_C` CDO (credits awarded here)
3. `Add Item` fires (credits item added to inventory)
4. `ChangeCredits` fires on `InventoryComponent_C`
5. `BndEvt__ThePit_NPC_Steal_N` fires (post-completion notification, not pre-)

### VCO_Steal Hook Param Alignment (confirmed via RegisterHook)
- `stealType` param reads as byte but offset is misaligned in hook — reads wrong value (4 instead of expected type)
- `skillLevel` reads correctly (4 = player's steal skill level in test)
- `creditsBonus` reads as wrong value (-38 instead of 82) — misalignment confirmed
- `animNPC:get():GetFullName()` works correctly — returns `AnimatedProp_C /Game/Maps/ThePit.ThePit:PersistentLevel.NPC_Steal_1`
- `vco:get()` fails — `BasicOverheadWidgetComponent` ref does not resolve via RemoteUnrealParam on this build
- Param misalignment likely caused by UE4SS mapping ubergraph local frame variables into param slots

### AnimatedProp_C Properties
- `IsInteractive`: `BoolProperty` at offset `0x???` — readable/writable in principle
- `InteractionText`: `TextProperty`
- `InteractionCursor`: `ByteProperty`
- `OnInteraction`: `MulticastInlineDelegate` at offset `0x328`, `CPF_BlueprintAssignable`
  - Not exposed as a bindable object in UE4SS Lua — reads as function object (metamethod trap)
  - `OnInteraction__DelegateSignature` UFunction path: `/Game/MapObjects/AnimatedProp.AnimatedProp_C:OnInteraction__DelegateSignature`
  - Hookable via `RegisterHook` but never fires — it is a delegate signature stub, not a callable dispatch path

### NPC_Steal Actor Structure (from Habitat_Top dump, applies to ThePit)
Each NPC_Steal_N actor has:
- `BasicOverheadWidgetComponent` (VCO widget)
- `SceneComponent` (Scene)
- `SkeletalMeshComponent` (MainSkeletalMesh)
- `SkeletalMeshComponent` (NODE_AddSkeletalMeshComponent-2)
- `StaticMeshComponent` (NavBlockerMesh)
- `ItsVisibilityComponent_C` (visibility component)
- NPC_Steal_1..4: `ABP_Prop_HumanSitStoolDrink_C` animation (sitting at stool drinking)
- NPC_Steal_5: `ABP_Prop_HumanSleep_C` animation (sleeping) — behind stealth 4 check

### InventoryComponent_C
- `ChangeCredits` function: hookable, `Amount:get()` works, `Amount:set()` silently ignored by engine
- `Add Item` function: hookable, Item param is `UScriptStruct`, Stack is bool

### ThePit_C Hook Registration
- `NotifyOnNewObject` on `ThePit_C` does not fire when loading a save directly into ThePit
- `FindAllOf("ThePit_C")` also returns empty when called at startup before map loads
- Working solution: register ThePit hooks inside the `HumanRpgCharacter_C` NotifyOnNewObject callback using `pcall` guard

---

## What Still Needs Discovery

- Exact world positions of `PropChar_BLD_Saloon_*` actors relative to `NPC_Steal_*` actors
- Which `PropChar_BLD_Saloon_*` actors are visually/spatially appropriate steal targets
- Full `BndEvt` function paths for other maps that have steal (Habitat_Top confirmed to have NPC_Steal_1)
- Whether `IsInteractive = true` write on a `PropChar` actually shows an interaction prompt in-game (untested, not pursued)
- VCO_Steal param layout ground truth — the byte/int params are misaligned in the hook, exact frame offsets unknown

---

## Confirmed Non-Working on UE4SS Stable 3.0.1

- `ProcessEvent` on AActor-typed Blueprint instances — nullptr crash
- Direct UFunction call via metamethod on any BP object — returns function object
- `FindFunction` on UBlueprintGeneratedClass — crashes
- `StaticFindObject("Path:FunctionName")` — fake-valid, crashes on use
- `GetTypedOuter`, `ForEachComponent` — not available
- `Amount:set()` / param mutation in hooks — Lua-side only, engine ignores
- ObjectProperty write to level BP instance (`pit["NPC_Steal_1"] = actor`) — hard crash
- Delegate binding via Lua — not exposed
- `FindAllOf("ThePit_C")` at startup — returns empty (class not yet loaded)
- `NotifyOnNewObject` on `ThePit_C` when save-loading into map — callback missed

---

## C++ Recommendation for Future Mod

To achieve new steal interactions on arbitrary NPCs, a separate C++ UE4SS plugin is required.
The Lua mod cannot accomplish this. The C++ mod should:

### Goal
Bind new `OnInteraction` delegate handlers to selected `AnimatedProp_C` actors at map load,
and invoke `VCO_Steal` on `PlotFuncs_C` CDO with appropriate parameters when those handlers fire.

### Approach

1. **Use `BIND_UFUNCTION` or equivalent from UE4SS C++ BP macros**
   - Reference: https://docs.ue4ss.com/cpp-api/bp-macros.html
   - Bind a C++ lambda or UFUNCTION to the `OnInteraction` multicast delegate on target actors

2. **Actor selection at map load**
   - Hook `PostLoadMap` or `BeginPlay` on the level BP (`ThePit_C`)
   - Use `FindAllOf` equivalent in C++ to locate target `AnimatedProp_C` actors by name
   - Filter by name prefix (`PropChar_BLD_Saloon_*`) and spatial proximity to existing `NPC_Steal_*` actors
   - Set `IsInteractive = true` and `InteractionText` on selected targets

3. **VCO_Steal invocation**
   - Obtain `PlotFuncs_C` CDO via `StaticFindObject` or CDO lookup
   - Call `VCO_Steal` via `ProcessEvent` with a properly constructed params struct
   - Params struct layout (from dump, all offsets relative to function frame):
     - `Steal Type` (byte, offset 0x0)
     - `Skill Level` (int, offset 0x4)
     - `Item` (InvItem struct, 28 bytes, offset 0x8)
     - `Credits Bonus` (int, offset 0x28)
     - `VCO` (BasicOverheadWidgetComponent ref, offset 0x30)
     - `Animated NPC` (AnimatedProp_C ref, offset 0x38)
     - `Visibility Set` (ItsVisibilityComponent_C ref, offset 0x40)
     - `__WorldContext` (object ref, offset 0x48)
     - `Specialist` (object ref, nullable, offset 0x50)
   - `VCO` and `Visibility Set` must be read from the target actor's components at bind time
   - `__WorldContext` can be the target actor itself

4. **Steal type and skill level values**
   - `Steal Type` byte value semantics unknown — observed value 4 from existing steal NPCs (misaligned read, not confirmed)
   - `Skill Level` should be read from player character's steal skill at interaction time, not hardcoded
   - Need to confirm `Steal Type` enum values from game source or further C++ inspection

5. **Per-map configuration**
   - ThePit target candidates: `PropChar_BLD_Saloon_*` actors near existing `NPC_Steal_*` positions
   - Habitat_Top: has at least NPC_Steal_1, same pattern applies
   - Other maps: need survey

6. **Item steal targets**
   - Requires constructing a valid `InvItem` struct with correct item ID
   - Item IDs need discovery via `GetDataTableRowFromName` or similar at C++ level
   - One implant steal target desired in ThePit (specific implant TBD)

---

## Prompt for New Chat

I am developing a rebalance mod for Colony Ship RPG. I have two components:
1. A working Lua mod using UE4SS stable 3.0.1 that handles feat rebalancing (LoneWolf, Warrior, Berserker, etc.)
2. A planned C++ UE4SS plugin to add new steal interactions to NPCs

You are acting as primary developer. Operate with concise technical output. No narrative padding. Never guess game values. Never rewrite full files — targeted edits only. Never reintroduce resolved issues.

**C++ plugin goal:**
Add new VCO steal interactions to AnimatedProp_C actors in ThePit (and eventually other maps) that don't currently have steal. The game uses VCO_Steal on PlotFuncs_C CDO, triggered via OnInteraction multicast delegate bound in the level BP (ThePit_C). Lua cannot do this — requires C++ delegate binding and ProcessEvent.

**Key confirmed facts:**
- `OnInteraction` is a MulticastInlineDelegate on AnimatedProp_C at offset 0x328, CPF_BlueprintAssignable
- VCO_Steal is on PlotFuncs_C CDO at /Game/Gameplay/Plot/PlotFuncs.Default__PlotFuncs_C
- VCO_Steal param layout: StealType(byte,0x0), SkillLevel(int,0x4), Item(InvItem 28 bytes,0x8), CreditsBonus(int,0x28), VCO(0x30), AnimatedNPC(0x38), VisibilitySet(0x40), WorldContext(0x48), Specialist(nullable,0x50)
- Target actors: AnimatedProp_C instances named PropChar_BLD_Saloon_* in ThePit
- Each NPC_Steal actor has BasicOverheadWidgetComponent and ItsVisibilityComponent_C attached — new targets need these or equivalent
- StealType byte enum values are unconfirmed (observed 4 from hook but param alignment was off)
- Execution order: VCO_Steal → Add Item → ChangeCredits → BndEvt (BndEvt is post-completion)
- FindAllOf("ThePit_C") returns the live level BP instance as ThePit_C_0
- UE4SS C++ BP macros reference: https://docs.ue4ss.com/cpp-api/bp-macros.html

**What needs discovery in C++:**
- StealType enum values
- Valid InvItem struct construction for item steals
- Item IDs for implant steal target in ThePit
- Spatial positions of PropChar_BLD_Saloon_* relative to NPC_Steal_* to select appropriate targets
- Whether new actors need BasicOverheadWidgetComponent/ItsVisibilityComponent_C added or can reference existing ones

**Constraints:**
- Never guess game stat or item values — ask or check dumps
- Never produce full file rewrites — targeted edits only
- Corrections are permanent — do not reintroduce resolved issues
