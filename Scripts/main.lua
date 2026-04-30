-- ============================================================
-- Colony Ship Feat Description Mod
-- UE4SS standard patterns (no global 'UE4' dependency)
-- ============================================================

-- ------------------------------------------------------------------------
-- Script Path & Logging
-- ------------------------------------------------------------------------
local function get_script_path()
    local path = debug.getinfo(1, "S").source:sub(2)
    return path:match("(.*[/\\])") or "./"
end

local SCRIPT_PATH = get_script_path()
local CONFIG_PATH = SCRIPT_PATH .. "config.ini"
local LANG_PATH = SCRIPT_PATH .. "localization/"

local logPath = SCRIPT_PATH .. "RebalanceLog.txt"
local function Log(msg)
    local f = io.open(logPath, "a")
    if f then
        f:write(msg .. "\n")
        f:close()
    end
    print("[FeatRebalance] " .. msg .. "\n")
end

Log("[INFO] Mod initialized. Script path: " .. SCRIPT_PATH)

-- ------------------------------------------------------------------------
-- INI Parser (plain Lua)
-- ------------------------------------------------------------------------
local function ParseIni(filePath)
    local f = io.open(filePath, "r")
    if not f then return {} end
    local content = f:read("*a")
    f:close()
    local result = {}
    for line in content:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^[;#]") then
            local key, value = line:match("^(%w+)%s*=%s*(.+)$")
            if key and value then
                local num = tonumber(value)
                result[key] = num or value
            end
        end
    end
    return result
end

-- Default values (can be overridden in config.ini)
local DEFAULTS = {
    LANGUAGE = "en",
    LW_EVASION = 16,
    LW_INITIATIVE = 20,
    LW_ARMOR_PENALTY = 4,
    WARRIOR_ARMOR_PER_LEVEL = 1,
    BERSERK_MID_HP_PCT = 0.50,
    BERSERK_LOW_HP_PCT = 0.25,
    BASHER_THC = 8,
    BASHER_KNOCKDOWN = 20,
    BASHER_AIMED_PER_LEVEL = 2,
    BUTCHER_THC = 8,
    BUTCHER_CSC = 20,
    BUTCHER_PEN_PER_LEVEL = 2,
    JUGG_MID_HP_PCT = 0.50,
    JUGG_LOW_HP_PCT = 0.25,
    EDUCATED_SXP_BONUS = 5,
    EDUCATED_INT_MIN = 6,
    MASTERMIND_SXP_BONUS = 5,
    GIFTED_SKILL_SXP = 5,
    HF_REGEN_PER_LEVELS = 3,
    FR_EVASION = 6,
    GLADIATOR_MIN = 1,
    GLADIATOR_MAX = 1,
    HH_PER = 3,
    HH_CRIT_PER_STEP = 1,
    TB_CON = 6,
}

local cfg = {}

local function loadConfig()
    local iniData = ParseIni(CONFIG_PATH)
    for k, v in pairs(DEFAULTS) do
        cfg[k] = (iniData[k] ~= nil) and iniData[k] or v
    end
    Log("[INFO] Config loaded from " .. CONFIG_PATH)
end

-- ------------------------------------------------------------------------
-- Load descriptions from external Lua file (returns a function cfg → table)
-- ------------------------------------------------------------------------
local function loadDescriptions()
    local lang = cfg.LANGUAGE or "en"
    local descFile = LANG_PATH .. "descriptions-" .. lang .. ".lua"
    Log("[INFO] Loading descriptions from " .. descFile)
    local loader = loadfile(descFile)
    if not loader then
        Log("[WARN] Language file not found: " .. descFile .. " – falling back to en")
        loader = loadfile(LANG_PATH .. "descriptions-en.lua")
    end
    if not loader then
        Log("[ERROR] No descriptions file found!")
        return {}
    end
    local ok, descFunc = pcall(loader)
    if not ok or type(descFunc) ~= "function" then
        Log("[ERROR] Failed to load descriptions: " .. tostring(descFunc))
        return {}
    end
    local descriptions = descFunc(function(key, default)
        return cfg[key] or default
    end)

    -- FIX 1: #descriptions returns 0 for hash tables (string keys).
    -- Count entries correctly with pairs().
    local count = 0
    for _ in pairs(descriptions or {}) do count = count + 1 end

    if count == 0 then
        Log("[WARN] Descriptions table is empty")
    else
        Log("[INFO] Loaded " .. count .. " description entries")
    end
    return descriptions or {}
end

-- ------------------------------------------------------------------------
-- Patch feat descriptions
-- ------------------------------------------------------------------------
local function PatchFeatDescriptions(descriptions)
    Log("[INFO] Patching feat descriptions...")

    local updated = 0
    local failed  = 0

    for classPath, descText in pairs(descriptions) do
        -- Derive CDO path from class path.
        -- Input:  /Game/Gameplay/Feats/F_LoneWolf.F_LoneWolf_C
        -- Output: /Game/Gameplay/Feats/F_LoneWolf.Default__F_LoneWolf_C
        local packagePath, className = classPath:match("^(.+)%.(.+)$")
        if not packagePath or not className then
            Log("[WARN] Could not parse classPath: " .. classPath)
            failed = failed + 1
        else
            local cdoPath = packagePath .. ".Default__" .. className
            local cdo = StaticFindObject(cdoPath)
            if cdo and cdo:IsValid() then
                cdo:SetPropertyValue("Description", FText(descText))
                updated = updated + 1
                Log("[INFO] Patched: " .. cdoPath)
            else
                Log("[WARN] CDO not found: " .. cdoPath)
                failed = failed + 1
            end
        end
    end

    Log("[INFO] Patched " .. updated .. " / " .. (updated + failed) .. " feat descriptions")
    return updated > 0
end

-- ------------------------------------------------------------------------
-- Main mod logic
-- ------------------------------------------------------------------------
local descriptions = nil

local function RunMod()
    loadConfig()
    if not descriptions then
        descriptions = loadDescriptions()
    end
    if not descriptions or next(descriptions) == nil then
        Log("[ERROR] No descriptions loaded")
        return false
    end
    return PatchFeatDescriptions(descriptions)
end

-- ------------------------------------------------------------------------
-- Trigger: RegisterInitGameStatePostHook fires after the game state is
-- fully initialized — GameInstance and all its data (including Feats DB)
-- are guaranteed to be populated at this point.
-- This replaces all polling: one clean hook, fires at the right moment.
-- ------------------------------------------------------------------------
RegisterInitGameStatePostHook(function()
    Log("[INFO] InitGameState fired — applying feat descriptions")
    ExecuteInGameThread(function()
        local ok = RunMod()
        if not ok then
            Log("[WARN] PatchFeatDescriptions returned false after InitGameState")
        end
    end)
end)

-- ------------------------------------------------------------------------
-- F8 manual re-trigger (useful after loading a save mid-session)
-- ------------------------------------------------------------------------
RegisterKeyBind(Key.F8, function()
    descriptions = nil
    ExecuteInGameThread(function()
        local ok = RunMod()
        print("[FeatRebalance] F8 re-apply: " .. (ok and "OK" or "FAILED — check log"))
    end)
end)

Log("[INFO] Mod loaded. Waiting for InitGameState. Press F8 to manually re-apply.")
