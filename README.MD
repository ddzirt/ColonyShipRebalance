# Colony Ship Mod

A custom script mod for Colony Ship utilizing the UE4SS framework.

## Prerequisites

This mod requires **UE4SS** (Unreal Engine 4 Scripting System) to function.

1. Download the latest release of **UE4SS** (v3.0.0 or higher recommended).
2. Extract the contents into the game's binary folder:
   `Colony Ship/ColonyShip/Binaries/Win64/`
3. Verify that `UE4SS.dll` and `UE4SS-settings.ini` are located in that folder.

## Installation

### 1. Install Mod Files

1. Download and extract this via `CODE` button.
2. Create a folder with name Rebalance and extract Scripts folder into it.
3. Move the mod(Rebalance) folder into the UE4SS mods directory:
   `Colony Ship/ColonyShip/Binaries/Win64/Mods/`

### 2. Configure UE4SS-settings.ini (Optional)

If you are using a custom mod location or need to verify loading:

1. Open `UE4SS-settings.ini` in the `Win64` folder.
2. Ensure `ModsFolderPath` is correctly targeting your `Mods` directory.
3. (Optional) Set `GuiConsoleEnabled = 1` to open the console on launch to verify the script initializes.

## Usage

* Launch the game as normal.
* The mod will be automatically initialized by the UE4SS loader.
* If using the UE4SS GUI, you can check the "Mods" tab to ensure the mod is toggled to "Enabled."

## Feat Rebalance - Balance Changes Summary

Most changes are exposed in config.ini and can be tuned.

### Current Status:

- Certain feats are not fully working(ones with custom HP logic)
- Increasing implant count does not work
- Healing Factor and increasing regeneration does not work

### Lone Wolf(Works)

* `Evasion` increased from +12 to +16.
* `Initiative` increased from +16 to +20.
* Added +4 `Armor Handling`.

### Warrior(Works)

* Additionally grants `Armor Handling` equal to (Melee Skill Level × 1), defaulting to +1 per level.

### Berserker(Works partially)

* `HP` above 50%: no bonus.
* `HP` ≤ 50%: +1 min and max melee damage.
* `HP` ≤ 25%: +2 min and max melee damage.
* At 13 HP or below, the vanilla +2 bonus applies (no additional mod bonus). Might add +1 here.

### Basher (blunt weapons)(Works but needs testings)

* Removed vanilla penetration bonus.
* Added +8% Melee `THC`.
* Added +20% `Knockdown Critical Chance`.
* Added +2% `Aimed THC` per Melee Skill Level.

### Butcher (bladed weapons)(Works but needs testings)

* Removed vanilla aimed attack bonus.
* Added +8% Melee `THC`.
* Added +20% `Carve Critical Chance`.
* Added +2% `Penetration` per Melee Skill Level.

### Fast Runner(Works)

* Additionally grants +6 `Evasion`.

### Gladiator(Works)

* Now provides a flat +1 min and +1 max melee damage.

### Heavy Hitter(Works but needs testings)

* Additionally grants +1% `Critical Strike Chance` per 3 points of `Perception`.

### Tough Bastard(Works)

* Requires `Constitution` ≥ 6 to be available.

### Bionic(Does not work)

* Now grants +2 Implants

### Educated(Works)

* Now grants +5% Skill XP gain
* Requires `Intelligence` ≥ 6 to be available.

### Mastermind (Heroic)(Works)

* Additionally grants +5% Skill XP gain.

### Gifted (Heroic)(Works partically, +1 to stats is yet to work)

* Grants +4 to stats(+1 to original)
* Additionally grants +5% Skill XP gain.

### Healing Factor (Heroic)(Does not work)

* HP regeneration per turn is now `floor(character level / 3)` (default; configurable).

### Juggernaut (Heroic)(Works partially)

* `HP` above 50%: +1 Natural DR.
* `HP` ≤ 50%: +2 Natural DR.
* `HP` ≤ 25%: +3 Natural DR.
* At 13 HP or below, vanilla handles its own +4 DR (no extra).

## License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

---

### Disclaimer

This is an unofficial mod. It is not affiliated with Iron Tower Studio. Always back up your save files before installing scripts that modify game logic.
