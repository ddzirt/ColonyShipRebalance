# --- CONFIGURATION ---
$GitRepoDir = "D:\Work\GameDev\ColonyShip\Rebalance"
$GameModDir = "D:\SteamLibrary\steamapps\common\Colony Ship RPG\ColonyShipGame\Binaries\Win64\Mods\Rebalance"

# List of files/folders to sync (relative to RepoDir)
$SyncItems = @(
    "Scripts\main.lua",
    "Scripts\config.ini",
    "Scripts\localization\descriptions-en.lua",
    "enabled.txt"
)

# --- LOGIC ---
param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("link", "deploy", "clean")]
    $Mode = "link"
)

# --- Logic ---
param (
    [ValidateSet("link", "deploy")]
    $Mode = "link"
)

foreach ($Item in $SyncItems)
{
    $Source = Join-Path $GitRepoDir $Item
    $Target = Join-Path $GameModDir $Item
    $Parent = Split-Path $Target -Parent

    if (!(Test-Path $Source))
    { Write-Error "Source missing: $Source"; continue
    }
    if (!(Test-Path $Parent))
    { New-Item -ItemType Directory -Path $Parent -Force
    }

    # Clean up existing target to avoid conflicts
    if (Test-Path $Target)
    {
        $Attributes = (Get-Item $Target).Attributes
        if ($Attributes -match "ReparsePoint")
        {
            # Remove existing symlink
            Remove-Item $Target -Force
        } else
        {
            # Remove existing physical file
            Remove-Item $Target -Recurse -Force
        }
    }

    if ($Mode -eq "link")
    {
        # Create Symlink: Changes in Git are instantly live in Game
        New-Item -ItemType SymbolicLink -Path $Target -Value $Source
        Write-Host "Linked: $Item" -ForegroundColor Cyan
    } else
    {
        # Deploy: Hard copy files to Game folder
        Copy-Item -Path $Source -Destination $Target -Recurse -Force
        Write-Host "Deployed: $Item" -ForegroundColor Green
    }
}
