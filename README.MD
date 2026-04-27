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

### Lone Wolf

* `Evasion` increased from +12 to +16.
* `Initiative` increased from +16 to +20.
* Added +4 `Armor Handling`.

### Warrior

* Additionally grants `Armor Handling` equal to (Melee Skill Level × 1), defaulting to +1 per level.

### Berserker

* `HP` above 50%: no bonus.
* `HP` ≤ 50%: +1 min and max melee damage.
* `HP` ≤ 25%: +2 min and max melee damage.
* At 13 HP or below, the vanilla +2 bonus applies (no additional mod bonus). Might add +1 here.

### Juggernaut (Heroic)

* `HP` above 50%: +1 Natural DR.
* `HP` ≤ 50%: +2 Natural DR.
* `HP` ≤ 25%: +3 Natural DR.
* At 13 HP or below, vanilla handles its own +4 DR (no extra).

### Basher (blunt weapons)

* Removed vanilla penetration bonus.
* Added +8% Melee `THC`.
* Added +20% `Knockdown Critical Chance`.
* Added +2% `Aimed THC` per Melee Skill Level.

### Butcher (bladed weapons)

* Removed vanilla aimed attack bonus.
* Added +8% Melee `THC`.
* Added +20% `Carve Critical Chance`.
* Added +2% `Penetration` per Melee Skill Level.

### Fast Runner

* Additionally grants +6 `Evasion`.

### Gladiator

* Now provides a flat +1 min and +1 max melee damage.

### Heavy Hitter

* Additionally grants +1% `Critical Strike Chance` per 3 points of `Perception`.

### Tough Bastard

* Requires `Constitution` ≥ 6 to gain any bonuses.
* If CON < 6, all benefits (DR, HP bonus) are suppressed.
* We'll see if I can remove feat from selection list instead.
* Or split DR and HP bonus to this condition.

### Educated

* Now grants +5% Skill XP gain, but only if `Intelligence` ≥ 6.

### Mastermind (Heroic)

* Additionally grants +5% Skill XP gain.

### Gifted (Heroic)

* Additionally grants +5% Skill XP gain.

### Healing Factor (Heroic)

* HP regeneration per turn is now `floor(character level / 3)` (default; configurable).

## License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

---

### Disclaimer

This is an unofficial mod. It is not affiliated with Iron Tower Studio. Always back up your save files before installing scripts that modify game logic.
