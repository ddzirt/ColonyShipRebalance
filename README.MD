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
2. Create a folder with name `FeatRebalance` and extract `Scripts` folder into it.
3. Move the mod(`FeatRebalance`) folder into the UE4SS mods directory:
   `Colony Ship/ColonyShip/Binaries/Win64/Mods/`

### 2. Configure UE4SS-settings.ini (Optional)

If you are using a custom mod location or need to verify loading:

1. Open `UE4SS-settings.ini` in the `Win64` folder.
2. Ensure `ModsFolderPath` is correctly targeting your `Mods` directory.
3. Open `mods.txt` within the `Mods` directory and add `FeatRebalance` to the list if it's not already there(Needs to look like this: `FeatRebalance : 1`).
4. (Optional) Set `ConsoleEnabled = 1` to open the console on launch to verify the script initializes.

## Usage

* Launch the game as normal.
* The mod will be automatically initialized by the UE4SS loader. If not, review step 2.
* If using the `UE4SS GUI`(`UE4SS-settings.ini` requires `GuiConsoleEnabled = 1` and `GuiConsoleVisible = 1`), you can check the "Mods" tab to ensure the mod is toggled to "Enabled."

## Feat Rebalance - Balance Changes Summary

Most changes are exposed in config.ini and can be tuned.

### Current Status:

- Certain feats: Bionic, Gifted. Are working but with limitations: Gifted still needs to grant +1 to stats, Bionic is limited to player character instead of all party members. Skill Monkey was attempted but under current limitations and my lack of experience with particular UE4SS and Unreal Engine 4 modding tools it was not successful and was deffered to need of using C++ instead of Lua.

### Changes to feats:

### Lone Wolf

* `Evasion` increased from +12 to +16.
* `Initiative` increased from +16 to +20.
* Added +4 `Armor Handling`.

### Warrior

* Additionally grants `Armor Handling` equal to (Melee Skill Level(blunt + bladed) × 1).

### Berserker

* `HP` above 60%: no bonus.
* `HP` ≤ 60%: +1 min and max `melee damage`.
* `HP` ≤ 30%: +2 min and max `melee damage`.
* At 13 HP or below, +2 bonus(no additional mod bonus).

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

* Now provides a flat +1 min and +1 max `melee damage`.

### Heavy Hitter

* Additionally grants +1% `Critical Strike Chance` per 3 points of `Perception`.

### Bionic

* Now grants +2 `Implants`
* Configurable via `BIONIC_IMPLANTS` but hard cap at 7(Game maximum)

### Tough Bastard

* Requires `Constitution` ≥ 6 to be available.

### Educated

* Now grants +15% `Skill XP` gain
* Requires `Intelligence` ≥ 6 to be available.

### MasterTrader

* Requires `Charisma` ≥ 6 to be available.

### Mastermind (Heroic)

* Additionally grants +25% `Skill XP` gain.

### Gifted (Heroic)

* Additionally grants +15% `Skill XP` gain.

### Healing Factor (Heroic)

* HP regeneration per turn is now `HF_BASE_REGEN + floor(level / HF_REGEN_PER_LEVELS)`, defaulting to `3 + floor(level / 3)`.

### Juggernaut (Heroic)

* `HP` above 60%: +1 `DR`. (Natural)
* `HP` ≤ 60%: +2 `DR`.
* `HP` ≤ 30%: +3 `DR`.
* At 13 `HP` or below, +4 `DR`.

## License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

---

### Disclaimer

This is an unofficial mod. It is not affiliated with Iron Tower Studio. Always back up your save files before installing scripts that modify game logic.
