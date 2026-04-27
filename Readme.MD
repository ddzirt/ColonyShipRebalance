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

1. Download and extract this mod archive.
2. Move the mod folder into the UE4SS mods directory:
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

## License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

---

### Disclaimer

This is an unofficial mod. It is not affiliated with Iron Tower Studio. Always back up your save files before installing scripts that modify game logic.
