-- ============================================================
-- Colony Ship Rebalance Mod(feats for now)
-- ============================================================

-- ------------------------------------------------------------------------
-- TODO: Find what is crashing the game randomly(causing a freeze)
-- ------------------------------------------------------------------------

-- ------------------------------------------------------------------------
-- Script Path & Logging
-- ------------------------------------------------------------------------
local function get_script_path()
    local path = debug.getinfo(1, "S").source:sub(2)
    return path:match("(.*[/\\])") or "./"
end

-- ------------------------------------------------------------------------
-- INITIAL CONFIG
-- ------------------------------------------------------------------------
local SCRIPT_PATH = get_script_path()
local CONFIG_PATH = SCRIPT_PATH .. "config.ini"
local LANG_PATH   = SCRIPT_PATH .. "localization/"
local LOG_PATH    = SCRIPT_PATH .. "RebalanceLog.txt"

-- ------------------------------------------------------------------------
-- GENERATE LOG FILE
-- TODO: Add config value to ommit this
-- ------------------------------------------------------------------------
do
    local f = io.open(LOG_PATH, "w")
    if f then f:close() end
end

-- ------------------------------------------------------------------------
-- UE4SS Helpers
-- I think I need to check what's there and incorporate some of it
-- ------------------------------------------------------------------------
local UEHelpers          = require("UEHelpers")

-- ------------------------------------------------------------------------
-- Local variables and caching
-- ------------------------------------------------------------------------
local AppliedModifiers   = {} -- redundant, maybe I'll find a way
local FeatNameCache      = {}
local allHooksRegistered = false
local logFile            = nil
local logBufferEnabled   = true -- set false to flush after every write
local descriptions       = nil
local descriptionsCache  = nil  -- Cache for loaded descriptions(probably not needed but we'll see) TODO: Review this
local configLoaded       = false
local BionicCharIDs      = {}   -- set of charIDs that have Bionic feat
local ItsBpLibHooked     = false
local isFunctionsCached  = false
local cachedPlotCDO      = nil
local cachedVCOStealFn   = nil
local cachedCalcFn       = nil
local cachedPlayerChar   = nil

-- ------------------------------------------------------------------------
-- Field constants (CsgCharEffects mangled property names)
-- ------------------------------------------------------------------------
local F                  = {
    Evasion         = "EvasionMod_76_5A03A1C64111532DC77320909200AA8C",
    Initiative      = "InitiativeMod_140_36D637CF4AF656392EE046A05B615F11",
    MaxAP           = "MaxAPMod_83_04CD14B24ACBF706E9CC78BAB1296612",
    ArmorPenalty    = "ArmorPenaltyMod_82_40D594EA4C29457956FCF582A15792C2",
    MeleeTHC        = "MeleeTHCMod_68_E0C338BB45331F54E7D9F886B676B652",
    MeleeCSC        = "MeleeCSCMod_69_894119434B15B7D76F8BC58A0C3B60DF",
    MeleeMinDMG     = "MeleeMinDMGMod_92_94EA5AF74C9ED716E05B908931335051",
    MeleeMaxDMG     = "MeleeMaxDMGMod_137_C4191C38408183538BE5049AB7D545E1",
    NaturalDR       = "NaturalDRMod_105_0D15FF214A7CB826380DFFA3CBE5B518",
    KnockdownChance = "KnockdownChanceMod_107_FDDD792C49AC81324BCA7BB7C8BE559A",
    PenetrationPct  = "PenetrationPercentMod_111_1177A0254CB2DF505A72B8A6C9451C02",
    AimedTHC        = "MarksmanshipAimedTHCMod_120_0434BD96457EA01836B0159A3D930E6C",
    MaxHP           = "MaxHPMod_84_435ACAD04EFCD7C7108DE3AFCB43BD4D",
    SkillXPGain     = "SkillXPGainMod_224_A0747CE04E2A3303C8681C9398E3577E",
    CSC             = "CSCMod_16_167EDCF94FF53F08D293809DB72CAF5A",
    HPRegen         = "HPRegenerationRateMod_57_F3F3ACE741EDD3E2CE40168C00C5D1D8",
}

-- ------------------------------------------------------------------------
-- Feat class references for Has Feat checks
-- ------------------------------------------------------------------------
local FeatClasses        = {
    FeatBase      = "/Game/Gameplay/Feats/BaseTypes/FeatBase.FeatBase_C",
    -- USUAL
    Educated      = "/Game/Gameplay/Feats/F_Educated.F_Educated_C",
    ToughBastard  = "/Game/Gameplay/Feats/F_ToughBastard.F_ToughBastard_C",
    LoneWolf      = "/Game/Gameplay/Feats/F_LoneWolf.F_LoneWolf_C",
    Warrior       = "/Game/Gameplay/Feats/F_Warrior.F_Warrior_C",
    Gladiator     = "/Game/Gameplay/Feats/F_Gladiator.F_Gladiator_C",
    HeavyHitter   = "/Game/Gameplay/Feats/F_HeavyHitter.F_HeavyHitter_C",
    Butcher       = "/Game/Gameplay/Feats/F_Butcher.F_Butcher_C",
    Basher        = "/Game/Gameplay/Feats/F_Basher.F_Basher_C",
    Berserker     = "/Game/Gameplay/Feats/F_Berserker.F_Berserker_C",
    Bionic        = "/Game/Gameplay/Feats/F_Bionic.F_Bionic_C",
    SkillMonkey   = "/Game/Gameplay/Feats/F_SkillMonkey_C",
    MasterTrader  = "/Game/Gameplay/Feats/F_MasterTrader.F_MasterTrader_C",
    -- HEROIC
    Mastermind    = "/Game/Gameplay/Feats/F_H_Mastermind.F_H_Mastermind_C",
    Juggernaut    = "/Game/Gameplay/Feats/F_H_Juggernaut.F_H_Juggernaut_C",
    FastRunner    = "/Game/Gameplay/Feats/F_H_FastRunner.F_H_FastRunner_C",
    HealingFactor = "/Game/Gameplay/Feats/F_H_HealingFactor.F_H_HealingFactor_C",
    Gifted        = "/Game/Gameplay/Feats/F_Gifted.F_Gifted_C", -- the only heroic without H
}

-- ------------------------------------------------------------------------
-- DEFAULTS or REVERSE ENGINEERED VALUES
-- ------------------------------------------------------------------------
local DEFAULTS           = {
    LANGUAGE                = "en",
    LW_EVASION              = 16,
    LW_INITIATIVE           = 20,
    LW_ARMOR_PENALTY        = 4,
    WARRIOR_ARMOR_PER_LEVEL = 1,
    BERSERK_MID_HP_PCT      = 0.50,
    BERSERK_LOW_HP_PCT      = 0.25,
    BASHER_THC              = 8,
    BASHER_KNOCKDOWN        = 20,
    BASHER_AIMED_PER_LEVEL  = 2,
    BUTCHER_THC             = 8,
    BUTCHER_CSC             = 20,
    BUTCHER_PEN_PER_LEVEL   = 2,
    JUGG_MID_HP_PCT         = 0.50,
    JUGG_LOW_HP_PCT         = 0.25,
    EDUCATED_SXP_BONUS      = 15,
    EDUCATED_INT_MIN        = 6,
    MASTERMIND_SXP_BONUS    = 25,
    GIFTED_SKILL_SXP        = 15,
    HF_REGEN_PER_LEVELS     = 3,
    FR_EVASION              = 6,
    GLADIATOR_MIN           = 1,
    GLADIATOR_MAX           = 1,
    HH_PER                  = 3,
    HH_CRIT_PER_STEP        = 1,
    TB_CON                  = 6,
    BIONIC_IMPLANTS         = 2,
    MASTER_TRADER_CHA       = 6,
    DEBUG                   = false,
}
local cfg                = {}
local statMapping        = {
    STR = 0,
    DEX = 1,
    CON = 2,
    PER = 3,
    INT = 4,
    CHA = 5,
}
local skillsMapping      = {
    Bladed = 0,
    Blunt = 1,
    Pistol = 2,
    Shotgun = 3,
    Rifle = 4,
    SMG = 5,
    CriticalStrike = 8,
    Evasion = 9,
    Armor = 10,
    Biotech = 11,
    Computers = 12,
    Electronics = 13,
    Persuasion = 14,
    Streetwise = 15,
    Impersonate = 16,
    Lockpick = 17,
    Steal = 18,
    Sneak = 19
}

-- ------------------------------------------------------------------------
-- LOGGIN FUNCTIONS
-- ------------------------------------------------------------------------

-- Call once, e.g., from a mod initialisation function
local function InitLog()
    -- Use "a" to append across game sessions, "w" to start fresh each time
    if not logFile then
        logFile = io.open(LOG_PATH, "a")
        if not logFile then
            print("[Rebalance] WARNING: Could not open log file " .. LOG_PATH)
        end
    end
end

local function Log(msg, useOnlyPrint)
    if not cfg.DEBUG then return end

    local onlyPrint = cfg.DEBUG_ONLY_CONSOLE or useOnlyPrint
    local fullMsg = "[Rebalance] " .. msg .. "\n"
    print(fullMsg)

    if not onlyPrint then
        local lf = logFile
        if lf then
            local ok, err = pcall(lf.write, lf, fullMsg .. "\n")
            if not ok then
                print("[Rebalance] Log write error: " .. tostring(err))
            elseif not logBufferEnabled then
                lf:flush()
            end
        end
    end
end

-- ------------------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------------------
local function Set(ref, field, value)
    local ok, err = pcall(function() ref[field] = value end)
    if not ok then Log("[WARN] SET FAILED [" .. field .. "]: " .. tostring(err)) end
end

local function GetEffects(Effects)
    local ok, ref = pcall(function() return Effects:get() end)
    return ok and ref or nil
end

local function GetChar(OwnerCharacter)
    local ok, char = pcall(function() return OwnerCharacter:get() end)
    return ok and char or nil
end

local function IsConditionMet(IsValid)
    local ok, val = pcall(function() return IsValid:get() end)
    return ok and val == true
end

local function GetCharLevel(char)
    local ok, lv = pcall(function() return char:GetCharLevel() end)
    return ok and lv or 0
end

function CharHasFeat(char, featName)
    if char and char.HasFeat then
        return char:HasFeat(featName)
    end
    return false
end

local function GetHP(char)
    if not char or not char:IsValid() then return nil, nil, nil end

    -- Initialize tables to hold the out parameters
    local hpOutput = {}
    local maxHpOutput = {}

    -- Call GetHP: The first argument is the 'Gather Tooltip' bool (false),
    -- the second is the table to receive the out parameters.
    local hpStatus, hpErr = pcall(function() char:GetHP(false, hpOutput) end)

    -- If the signature is simpler (no bool), it might just be char:GetHP(hpOutput)
    if not hpStatus or hpOutput.HP == nil then
        pcall(function() char:GetHP(hpOutput) end)
    end

    -- Call GetMaxHP: Provide the bool and the table
    local mhpStatus, mhpErr = pcall(function() char:GetMaxHP(false, maxHpOutput) end)

    -- Extract values from the tables using the names from your dump
    local curVal = hpOutput.HP
    local maxVal = maxHpOutput.MaxHP

    if type(curVal) ~= "number" or type(maxVal) ~= "number" or maxVal <= 0 then
        return nil, nil, nil
    end

    return curVal, maxVal, curVal / maxVal
end

-- Read a numeric stat from a character
local function GetAttribute(char, statIndex)
    if not char or not char:IsValid() then
        return nil
    end

    local status, val = pcall(function()
        return char:GetStatValue_Base(statIndex)
    end)

    return status and val or nil
end

-- Read a numeric skill level from a character
-- tagged:boolean - whether to include tagged skills in the calculation
local function GetSkillLevel(char, statIndex, tagged)
    if not char or not char:IsValid() then
        return nil
    end

    local status, val = pcall(function()
        return char:GetSkillLevel(statIndex, tagged)
    end)

    return status and val or nil
end

local function Trim(s)
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

local function GetPlayerCharacter()
    local chars = FindAllOf("HumanRpgCharacter_C")
    if not chars then return nil end
    for _, c in ipairs(chars) do
        if c:IsValid() then
            -- Log what GetCharID returns raw
            local ok, id = pcall(function() return c:GetCharID() end)
            Log("[GetPC] IsValid=true GetCharID ok=" .. tostring(ok) .. " id=" .. tostring(id), true)
            return c -- return first valid regardless
        end
    end
    return nil
end

-- ------------------------------------------------------------------------
-- INI Parser
-- ------------------------------------------------------------------------
local function ParseIni(filePath)
    local f = io.open(filePath, "r")
    if not f then return {} end
    local content = f:read("*a")
    f:close()

    -- Remove UTF-8 BOM if present
    content = content:gsub("^\xEF\xBB\xBF", "")

    local result = {}
    for line in content:gmatch("[^\r\n]+") do
        line = Trim(line)
        if line ~= "" and not line:match("^[;#]") then
            local key, value = line:match("^([^=]+)%s*=%s*(.+)$")
            if key and value then
                key   = Trim(key)
                value = Trim(value)
                if value == "true" then
                    result[key] = true
                elseif value == "false" then
                    result[key] = false
                else
                    result[key] = tonumber(value) or value
                end
            end
        end
    end
    return result
end

local function LoadConfig()
    if configLoaded then return end
    local ini = ParseIni(CONFIG_PATH)
    for k, v in pairs(DEFAULTS) do
        cfg[k] = (ini[k] ~= nil) and ini[k] or v
    end
    Log("[INFO] Config loaded from " .. CONFIG_PATH)
    configLoaded = true
end

-- ------------------------------------------------------------------------
-- FUNCTION CACHE TO USE FOR RECALC AND VCO STEAL
-- ------------------------------------------------------------------------
local function CacheFunctions()
    ForEachUObject(function(obj, chunkIdx, objIdx)
        if not obj:IsValid() then return end
        local ok, name = pcall(function() return obj:GetFName():ToString() end)
        if not ok then return end

        if name == "Calc Char Effects Feats" and not cachedCalcFn then
            local ok2, fullName = pcall(function() return obj:GetFullName() end)
            if ok2 and fullName:find("HumanRpgCharacter") then
                cachedCalcFn = obj
                Log("[Cache] CalcFn: " .. fullName, true)
            end
        end

        if name == "VCO_Steal" and not cachedVCOStealFn then
            cachedVCOStealFn = obj
            local ok2, fullName = pcall(function() return obj:GetFullName() end)
            if ok2 then Log("[Cache] VCOSteal: " .. fullName, true) end
        end

        if name == "Default__PlotFuncs_C" and not cachedPlotCDO then
            cachedPlotCDO = obj
            local ok2, fullName = pcall(function() return obj:GetFullName() end)
            if ok2 then Log("[Cache] PlotCDO: " .. fullName, true) end
        end
    end)
end

local function CachePlayerChar()
    ForEachUObject(function(obj, chunkIdx, objIdx)
        if cachedPlayerChar then return end
        if not obj:IsValid() then return end
        local ok, name = pcall(function() return obj:GetFName():ToString() end)
        if not ok then return end
        -- Match the known instance name
        if name:find("HumanRpgCharacter_C_") then
            local ok2, id = pcall(function() return obj:GetCharID() end)
            if ok2 and id == 1 then
                cachedPlayerChar = obj
                local fn = pcall(function()
                    Log("[Cache] PlayerChar: " .. obj:GetFullName() .. " type: " .. tostring(obj), true)
                end)
            end
        end
    end)
end

-- ------------------------------------------------------------------------
-- Load descriptions
-- ------------------------------------------------------------------------
local function LoadDescriptions()
    -- Return cached result if already loaded
    if descriptionsCache ~= nil then
        return descriptionsCache
    end

    local lang     = cfg.LANGUAGE or "en"
    local descFile = LANG_PATH .. "descriptions-" .. lang .. ".lua"
    Log("[INFO] Loading descriptions from " .. descFile)
    local loader = loadfile(descFile)
    if not loader then
        Log("[WARN] Language file not found: " .. descFile .. " — falling back to en")
        loader = loadfile(LANG_PATH .. "descriptions-en.lua")
    end
    if not loader then
        Log("[ERROR] No descriptions file found!")
        descriptionsCache = {} -- Cache empty result to avoid retries
        return {}
    end

    local ok, descFunc = pcall(loader)
    if not ok or type(descFunc) ~= "function" then
        Log("[ERROR] Failed to load descriptions: " .. tostring(descFunc))
        descriptionsCache = {}
        return {}
    end

    local descs = descFunc(function(key, default) return cfg[key] or default end)
    local count = 0
    for _ in pairs(descs or {}) do count = count + 1 end
    if count == 0 then
        Log("[WARN] Descriptions table is empty")
    else
        Log("[INFO] Loaded " .. count .. " description entries")
    end

    descriptionsCache = descs or {}
    return descriptionsCache
end

-- ------------------------------------------------------------------------
-- Hook helper
-- ------------------------------------------------------------------------
local function TryHook(path, fn)
    local ok, err = pcall(RegisterHook, path, fn)
    if ok then
        Log("[INFO] Hook registered: " .. path:match("[^/]+$"), true)
    else
        Log("[WARN] Hook FAILED: FeatBase:Get Effects | " .. tostring(err), true)
    end
end

-- ------------------------------------------------------------------------
-- Base Feat handlers for optimized lookup
-- ------------------------------------------------------------------------
local FeatBaseHandlers = {
    -- ------------------------------------------------------------------------
    -- Educated
    -- Addition: EDUCATED_SXP_BONUS
    -- STATUS: Works
    -- ------------------------------------------------------------------------
    ["F_Educated_C"] = function(char, ref)
        -- local id = FeatClasses.Educated
        -- AppliedModifiers[id] = AppliedModifiers[id] or {}
        -- local charId = tostring(char)
        -- if not AppliedModifiers[id][charId] then
        --     AppliedModifiers[id][charId] = true
        local int = char and GetAttribute(char, statMapping.INT) or 4
        if int >= cfg.EDUCATED_INT_MIN then
            Set(ref, F.SkillXPGain, cfg.EDUCATED_SXP_BONUS)
            -- Log("[INFO] Educated: +" .. cfg.EDUCATED_SXP_BONUS .. "% SkillXP", true)
        end

        -- local ok, err = pcall(function()
        --     -- Calling the instance method from your dump
        --     self["Is Recalc Required"](self, char, 0) --
        -- end)

        -- if ok then
        --     Log("[INFO] Injected Recalc during 'Get Effects' call.", true)
        -- else
        --     Log("[WARN] Injected Recalc failed: " .. tostring(err), true)
        -- end
        -- end
    end,

    -- ------------------------------------------------------------------------
    -- Skill Monkey
    -- Addition:
    -- STATUS: Experimental WIP
    -- ------------------------------------------------------------------------
    ["F_SkillMonkey_C"] = function(char, ref)
        -- local id = FeatClasses.SkillMonkey
        -- AppliedModifiers[id] = AppliedModifiers[id] or {}
        -- local charId = tostring(char)
        -- if not AppliedModifiers[id][charId] then
        --     AppliedModifiers[id][charId] = true
        -- local int = char and GetAttribute(char, statMapping.INT) or 4
        -- if int >= cfg.EDUCATED_INT_MIN then
        --     Set(ref, F.SkillXPGain, cfg.EDUCATED_SXP_BONUS)
        --     -- Log("[INFO] Educated: +" .. cfg.EDUCATED_SXP_BONUS .. "% SkillXP", true)
        -- end
        -- end

        Log("[INFO] Skill Monkey triggered")

        -- local objects = FindAllOf("SkillMonkey") -- may return a table, not an object
        -- if type(objects) == "table" then
        --     for _, v in ipairs(objects) do
        --         Log(v:GetFullName())
        --     end
        -- end
    end,

    -- ------------------------------------------------------------------------
    -- Bionic
    -- Addition: +BIONIC_IMPLANTS
    -- STATUS: Works
    -- Is used for caching characters it is applied to, do we even need it?
    -- ------------------------------------------------------------------------
    ["F_Bionic_C"] = function(char, ref)
        local id = char:GetCharID()
        -- only for MC(extend to party members only)
        -- not working or working incorrectly
        if id == 1 then
            BionicCharIDs[id] = true
        end
    end,

    -- ------------------------------------------------------------------------
    -- BERSERKER
    -- Vanilla: +2 MeleeDMG at <=13 HP
    -- Rebalanced: tiered vanilla threshold
    --   >60% HP  : nothing extra
    --   <=60% HP : +1 min/max
    --   <=30% HP : +2 min/max
    --   <=13 HP  : vanilla handles, we exit
    -- STATUS: Works
    -- ------------------------------------------------------------------------
    ["F_Berserker_C"] = function(char, ref)
        local curHP, _, ratio = GetHP(char)
        if not curHP or curHP <= 0 then return end
        -- Log("[INFO] Berserker: curHP: " .. curHP, true)
        -- let Vanilla handle this case
        -- seems to kill the logic
        -- or not but something is not right, math is wrong.
        -- Actually lest just handle vanilla ourselves.
        -- if curHP <= 13 then
        --     Log("[INFO] Berserker: return to vanilla", true)
        --     return
        -- end

        -- local id = FeatClasses.Berserker
        -- AppliedModifiers[id] = AppliedModifiers[id] or {}
        -- local charId = tostring(char)
        -- if not AppliedModifiers[id][charId] then
        --     AppliedModifiers[id][charId] = true

        if curHP <= 13 then
            Set(ref, F.MeleeMinDMG, 2)
            Set(ref, F.MeleeMaxDMG, 2)
            Log("[INFO] Berserker: tier 3", true)
        elseif ratio <= cfg.BERSERK_LOW_HP_PCT then
            Set(ref, F.MeleeMinDMG, 2)
            Set(ref, F.MeleeMaxDMG, 2)
            Log("[INFO] Berserker: tier 2 (" .. math.floor(ratio * 100) .. "%)", true)
        elseif ratio <= cfg.BERSERK_MID_HP_PCT then
            Set(ref, F.MeleeMinDMG, 1)
            Set(ref, F.MeleeMaxDMG, 1)
            Log("[INFO] Berserker: tier 1 (" .. math.floor(ratio * 100) .. "%)", true)
        end
        -- end
    end,

    -- HEROIC SECTION ---------------------------------------------------------

    -- ------------------------------------------------------------------------
    -- Mastermind
    -- Addition: +MASTERMIND_SXP_BONUS
    -- STATUS: Works
    -- ------------------------------------------------------------------------
    ["F_H_Mastermind_C"] = function(char, ref)
        -- local id = FeatClasses.Mastermind
        -- AppliedModifiers[id] = AppliedModifiers[id] or {}
        -- local charId = tostring(char)
        -- if not AppliedModifiers[id][charId] then
        --     AppliedModifiers[id][charId] = true
        Set(ref, F.SkillXPGain, cfg.MASTERMIND_SXP_BONUS)
        -- Log("[INFO] Mastermind: +" .. cfg.MASTERMIND_SXP_BONUS .. "% SkillXP", true)
        -- end
    end,

    -- ------------------------------------------------------------------------
    -- Gifted
    -- Addition: +GIFTED_SKILL_SXP
    -- STATUS: Works, no +1 to unspent stat point though
    -- ------------------------------------------------------------------------
    ["F_Gifted_C"] = function(char, ref)
        -- local id = FeatClasses.Gifted
        -- AppliedModifiers[id] = AppliedModifiers[id] or {}
        -- local charId = tostring(char)
        -- if not AppliedModifiers[id][charId] then
        --     AppliedModifiers[id][charId] = true
        Set(ref, F.SkillXPGain, cfg.GIFTED_SKILL_SXP)
        -- Log("[INFO] Gifted: +" .. cfg.GIFTED_SKILL_SXP .. "% SkillXP")
        -- end
    end,

    -- ------------------------------------------------------------------------
    -- Fast Runner
    -- Addition: +FR_EVASION
    -- STATUS: Works
    -- ------------------------------------------------------------------------
    ["F_H_FastRunner_C"] = function(char, ref)
        -- local id = FeatClasses.FastRunner
        -- AppliedModifiers[id] = AppliedModifiers[id] or {}
        -- local charId = tostring(char)
        -- if not AppliedModifiers[id][charId] then
        --     AppliedModifiers[id][charId] = true
        Set(ref, F.Evasion, cfg.FR_EVASION)
        -- Log("[INFO] FastRunner: +" .. cfg.FR_EVASION .. " Evasion", true)
        -- end
    end,

    -- ------------------------------------------------------------------------
    -- Healing Factor
    -- Addition: +HF_REGEN_PER_LEVELS
    -- STATUS: Works
    -- ------------------------------------------------------------------------
    ["F_H_HealingFactor_C"] = function(char, ref)
        -- local id = FeatClasses.HealingFactor
        -- AppliedModifiers[id] = AppliedModifiers[id] or {}
        -- local charId = tostring(char)
        -- if not AppliedModifiers[id][charId] then
        --     AppliedModifiers[id][charId] = true

        local level = char and GetCharLevel(char) or 0
        local bonus = math.floor(level / cfg.HF_REGEN_PER_LEVELS)
        local base = 3 -- default
        -- Log("[INFO] HealingFactor: HP Bonus: " .. tostring(bonus), true)
        if bonus > 0 then
            Set(ref, F.HPRegen, base + bonus)
            -- Log("[INFO] HealingFactor: level=" .. level .. " +HPRegen=" .. bonus, true)
        end
        -- end
    end,

    -- ------------------------------------------------------------------------
    -- JUGGERNAUT (Heroic)
    -- Rebalanced: tiered vanilla threshold
    --   >60% HP  : +1 DR
    --   <=60% HP : +2 DR
    --   <=30% HP : +3 DR
    --   <=13 HP  : vanilla handles +4, we exit
    -- STATUS: Works
    -- ------------------------------------------------------------------------
    ["F_H_Juggernaut_C"] = function(char, ref)
        if not char then return end
        if not char:IsValid() then return end

        local curHP, _, ratio = GetHP(char)
        if not curHP or curHP <= 0 then return end
        -- letting Vanilla handle this case
        -- seems to kill the logic
        -- or not but something is not right, math is wrong
        -- if curHP <= 13 then
        --     -- Log("[INFO] Juggernaut: return to vanilla", true)
        --     return
        -- end

        -- Log("[INFO] Juggernaut: curHP: " .. tostring(curHP), true)
        if curHP <= 13 then
            Set(ref, F.NaturalDR, 4)
            -- Log("[INFO] Juggernaut: tier 4", true)
        elseif ratio <= cfg.JUGG_LOW_HP_PCT then
            Set(ref, F.NaturalDR, 3)
            -- Log("[INFO] Juggernaut: tier 3 (" .. math.floor(ratio * 100) .. "%)", true)
        elseif ratio <= cfg.JUGG_MID_HP_PCT then
            Set(ref, F.NaturalDR, 2)
            -- Log("[INFO] Juggernaut: tier 2 (" .. math.floor(ratio * 100) .. "%)", true)
        else
            Set(ref, F.NaturalDR, 1)
        end
    end

    -- Add feats following the same pattern
}

-- ------------------------------------------------------------------------
-- LONE WOLF HANDLER
-- Vanilla (solo): +12 Evasion, +16 Initiative
-- Rebalanced:     +LW_EVASION, +LW_INITIATIVE, +LW_ARMOR_PENALTY
-- STATUS: Works
-- ------------------------------------------------------------------------
function LoneWolfHandler(self, OwnerCharacter, Effects, IsValid)
    if not IsConditionMet(IsValid) then return end

    local ref = GetEffects(Effects)
    if not ref then return end

    local char = GetChar(OwnerCharacter)
    if not char then return end
    if not char:IsValid() then return end

    -- this AppliedModifiers seems to do the throttling but
    -- it also prevents the effect from being applied later
    -- for character and might be potential source of crash
    -- need to incorporate character ID somehow
    -- and reapply when triggered again for same ID if need be
    -- but how?
    -- local id = FeatClasses.LoneWolf
    -- AppliedModifiers[id] = AppliedModifiers[id] or {}
    -- local charId = tostring(char)
    -- if not AppliedModifiers[id][charId] then
    --     AppliedModifiers[id][charId] = true
    Set(ref, F.Evasion, cfg.LW_EVASION)
    Set(ref, F.Initiative, cfg.LW_INITIATIVE)
    Set(ref, F.ArmorPenalty, cfg.LW_ARMOR_PENALTY)
    -- Log("[INFO] LoneWolf: applied")
    -- end
end

-- ------------------------------------------------------------------------
-- WARRIOR
-- Addition: +ArmorHandling per melee skill level
-- Rebalanced: +WARRIOR_ARMOR_PER_LEVEL
-- STATUS: Works
-- ------------------------------------------------------------------------
function WarriorHandler(self, OwnerCharacter, Effects, IsValid)
    if not IsConditionMet(IsValid) then return end

    local ref = GetEffects(Effects)
    if not ref then return end

    local char = GetChar(OwnerCharacter)
    if not char then return end
    if not char:IsValid() then return end

    -- local id             = FeatClasses.Warrior
    -- AppliedModifiers[id] = AppliedModifiers[id] or {}
    -- -- Use GetName() to ensure the ID is persistent across calls
    -- local charId         = char:GetName() -- this is BS and does not exist
    -- Log("[DEBUG] Checking ID: " .. charId .. " | Status: " .. tostring(AppliedModifiers[id][charId]), true)
    -- if not AppliedModifiers[id][charId] then
    --     AppliedModifiers[id][charId] = true
    local skillLevelBladed = GetSkillLevel(char, skillsMapping.Bladed, true)
    local skillLevelBlunt  = GetSkillLevel(char, skillsMapping.Blunt, true)
    local skillLevel       = skillLevelBladed + skillLevelBlunt
    local bonus            = math.max(1, skillLevel) * cfg.WARRIOR_ARMOR_PER_LEVEL
    Set(ref, F.ArmorPenalty, bonus)
    -- Log("[INFO] Warrior: ArmorHandling +" .. bonus, true)
    -- end
end

-- ------------------------------------------------------------------------
-- GLADIATOR
-- Addition: flat +min/max melee damage
-- STATUS: Works
-- ------------------------------------------------------------------------
function GladiatorHandler(self, OwnerCharacter, Effects, IsValid)
    if not IsConditionMet(IsValid) then return end

    local ref = GetEffects(Effects)
    if not ref then return end

    local char = GetChar(OwnerCharacter)
    if not char then return end
    if not char:IsValid() then return end

    -- local id             = FeatClasses.Warrior
    -- AppliedModifiers[id] = AppliedModifiers[id] or {}
    -- -- Use GetName() to ensure the ID is persistent across calls
    -- local charId         = char:GetName() -- this is BS and does not exist
    -- Log("[DEBUG] Checking ID: " .. charId .. " | Status: " .. tostring(AppliedModifiers[id][charId]), true)
    -- if not AppliedModifiers[id][charId] then
    --     AppliedModifiers[id][charId] = true
    Set(ref, F.MeleeMinDMG, cfg.GLADIATOR_MIN)
    Set(ref, F.MeleeMaxDMG, cfg.GLADIATOR_MAX)
    -- Log("[INFO] Gladiator: +" .. cfg.GLADIATOR_MIN .. "/" .. cfg.GLADIATOR_MAX .. " min/max dmg", true)
    -- Log("[INFO] Warrior: ArmorHandling +" .. bonus, true)
    -- end
end

-- ------------------------------------------------------------------------
-- BASHER (blunt weapons)
-- Vanilla: penetration bonus — replaced
-- Rebalanced: +THC, +knockdown, +aimed THC per melee skill level
-- STATUS: Works
-- ------------------------------------------------------------------------
function BasherHandler(self, OwnerCharacter, Effects, IsValid)
    if not IsConditionMet(IsValid) then return end

    local ref = GetEffects(Effects)
    if not ref then return end

    local char = GetChar(OwnerCharacter)
    if not char then return end
    if not char:IsValid() then return end

    -- local id             = FeatClasses.Basher
    -- AppliedModifiers[id] = AppliedModifiers[id] or {}
    -- local charId         = tostring(char)
    -- if not AppliedModifiers[id][charId] then
    --     AppliedModifiers[id][charId] = true
    local skillLevelBladed = GetSkillLevel(char, skillsMapping.Bladed, true)
    local skillLevelBlunt  = GetSkillLevel(char, skillsMapping.Blunt, true)
    local skillLevel       = skillLevelBladed + skillLevelBlunt
    Set(ref, F.PenetrationPct, 0)
    Set(ref, F.MeleeTHC, cfg.BASHER_THC)
    Set(ref, F.KnockdownChance, cfg.BASHER_KNOCKDOWN)
    Set(ref, F.AimedTHC, math.max(1, skillLevel) * cfg.BASHER_AIMED_PER_LEVEL)
    -- Log("[INFO] Basher: applied (melee skill=" .. skillLevel .. ")")
    -- end
end

-- ------------------------------------------------------------------------
-- BUTCHER (bladed weapons)
-- Vanilla: aimed bonus — replaced
-- Rebalanced: +THC, +crit, +penetration per melee skill level
-- STATUS: Works
-- ------------------------------------------------------------------------
function ButcherHandler(self, OwnerCharacter, Effects, IsValid)
    if not IsConditionMet(IsValid) then return end

    local ref = GetEffects(Effects)
    if not ref then return end

    local char = GetChar(OwnerCharacter)
    if not char then return end
    if not char:IsValid() then return end

    -- local id             = FeatClasses.Butcher
    -- AppliedModifiers[id] = AppliedModifiers[id] or {}
    -- local charId         = tostring(char)
    -- if not AppliedModifiers[id][charId] then
    --     AppliedModifiers[id][charId] = true
    local skillLevelBladed = GetSkillLevel(char, skillsMapping.Bladed, true)
    local skillLevelBlunt  = GetSkillLevel(char, skillsMapping.Blunt, true)
    local skillLevel       = skillLevelBladed + skillLevelBlunt
    Set(ref, F.AimedTHC, 0)
    Set(ref, F.MeleeTHC, cfg.BUTCHER_THC)
    Set(ref, F.CSC, cfg.BUTCHER_CSC)
    Set(ref, F.PenetrationPct, math.max(1, skillLevel) * cfg.BUTCHER_PEN_PER_LEVEL)
    -- Log("[INFO] Butcher: applied (melee skill=" .. skillLevel .. ")")
    -- end
end

-- ------------------------------------------------------------------------
-- HEAVY HITTER
-- Addition: +CSC per N points of Perception
-- STATUS: Works
-- ------------------------------------------------------------------------
function HeavyHitterHandler(self, OwnerCharacter, Effects, IsValid)
    if not IsConditionMet(IsValid) then return end

    local ref = GetEffects(Effects)
    if not ref then return end

    local char = GetChar(OwnerCharacter)
    if not char then return end
    if not char:IsValid() then return end

    -- local id             = FeatClasses.HeavyHitter
    -- AppliedModifiers[id] = AppliedModifiers[id] or {}
    -- local charId         = tostring(char)
    -- if not AppliedModifiers[id][charId] then
    --     AppliedModifiers[id][charId] = true
    local per       = GetAttribute(char, statMapping.PER)
    local critBonus = math.floor(per / cfg.HH_PER) * cfg.HH_CRIT_PER_STEP
    if critBonus > 0 then
        Set(ref, F.CSC, critBonus)
        -- Log("[INFO] HeavyHitter: +" .. critBonus .. "% CSC (Per=" .. per .. ")")
    end
    -- end
end

-- ------------------------------------------------------------------------
-- EDUCATED — Is Available To Learn
-- Gates feat selection on INT >= EDUCATED_INT_MIN.
-- Signature (dump L82223): (OwnerCharacter) -> Yes (BoolProperty)
-- STATUS: Works
-- ------------------------------------------------------------------------
function EducatedHandler(self, OwnerCharacter, Yes)
    local char = GetChar(OwnerCharacter)
    if not char then return end
    if not char:IsValid() then return end

    -- local id             = FeatClasses.Educated
    -- AppliedModifiers[id] = AppliedModifiers[id] or {}
    -- local charId         = tostring(char)
    -- if not AppliedModifiers[id][charId] then
    --     AppliedModifiers[id][charId] = true

    local int = GetAttribute(char, statMapping.INT)
    if int and int < cfg.EDUCATED_INT_MIN then
        -- Log("[INFO] Educated: blocked (INT=" .. int .. " < " .. cfg.EDUCATED_INT_MIN .. ")")
        Yes:set(false)
    end
    -- end
end

-- ------------------------------------------------------------------------
-- TOUGH BASTARD — Is Available To Learn
-- Gates feat selection on CON >= TB_CON.
-- STATUS: Works
-- ------------------------------------------------------------------------
function MasterTraderHandler(self, OwnerCharacter, Yes)
    local char = GetChar(OwnerCharacter)
    if not char then return end
    if not char:IsValid() then return end

    -- local id             = FeatClasses.ToughBastard
    -- AppliedModifiers[id] = AppliedModifiers[id] or {}
    -- local charId         = tostring(char)
    -- if not AppliedModifiers[id][charId] then
    --     AppliedModifiers[id][charId] = true

    local con = GetAttribute(char, statMapping.CON)
    if con and con < cfg.TB_CON then
        -- Log("[INFO] ToughBastard: blocked (CON=" .. con .. " < " .. cfg.TB_CON .. ")")
        Yes:set(false)
    end
    -- end
end

-- ------------------------------------------------------------------------
-- MASTER TRADER — Is Available To Learn
-- Gates feat selection on CHA >= MASTER_TRADER_CHA.
-- STATUS: Works
-- ------------------------------------------------------------------------
function ToughBastardHandler(self, OwnerCharacter, Yes)
    local char = GetChar(OwnerCharacter)
    if not char then return end
    if not char:IsValid() then return end

    -- local id             = FeatClasses.ToughBastard
    -- AppliedModifiers[id] = AppliedModifiers[id] or {}
    -- local charId         = tostring(char)
    -- if not AppliedModifiers[id][charId] then
    --     AppliedModifiers[id][charId] = true

    local cha = GetAttribute(char, statMapping.CHA)
    if cha and cha < cfg.MASTER_TRADER_CHA then
        -- Log("[INFO] MasterTrader: blocked (CHA=" .. cha .. " < " .. cfg.MASTER_TRADER_CHA .. ")")
        Yes:set(false)
    elseif cha and cha >= cfg.MASTER_TRADER_CHA then
        Yes:set(true)
        -- Log("[INFO] MasterTrader: allowed (CHA=" .. cha .. " < " .. cfg.MASTER_TRADER_CHA .. ")")
    end
end

-- ------------------------------------------------------------------------
-- ItsBpLib_C
-- ItsBpLib_C:GetMaxImplants
-- This is required to make Bionic work
-- at least partically now
-- ------------------------------------------------------------------------
function ImplantHandler(self, characterParam, gatherParam, worldParam, resParam)
    local char = GetChar(characterParam)
    if not char or not char:IsValid() then return end
    local id = char:GetCharID()
    if char and BionicCharIDs[id] then
        local con = GetAttribute(char, statMapping.CON)
        local baseImplants = math.floor(con / 2)
        local totalMax = 7
        local newVal = math.min(baseImplants + cfg.BIONIC_IMPLANTS, totalMax)
        resParam:set(newVal)
        gatherParam:set(true)
    end
end

-- ------------------------------------------------------------------------
-- Hook mod logic
-- ------------------------------------------------------------------------
NotifyOnNewObject("/Game/Gameplay/Characters/Core/HumanRpgCharacter.HumanRpgCharacter_C", function()
    if allHooksRegistered then return end
    allHooksRegistered = true
    Log("[INFO] HumanRpgCharacter loaded — registering all hooks", true)

    -- FeatBase Get Effects
    TryHook("/Game/Gameplay/Feats/BaseTypes/FeatBase.FeatBase_C:Get Effects",
        function(self, OwnerCharacter, UpgradeBits, Effects)
            local featName = ""
            local nameOk = pcall(function() featName = self:get():GetFName():ToString() end)
            if not nameOk or featName == "" then return end

            local ref = GetEffects(Effects)
            if not ref then return end

            local char = GetChar(OwnerCharacter)
            if not char then return end
            if not char:IsValid() then return end

            -- Memoization: Check if we already stripped this specific instance name
            local baseName = FeatNameCache[featName]
            if not baseName then
                -- 1. Strip the "Default__" prefix (if present)
                local strippedName = featName:gsub("^Default__", "")
                -- 2. Extract the core class name (e.g., "F_Educated_C" from "F_Educated_C_123")
                baseName = strippedName:match("(.-_C)") or strippedName
                FeatNameCache[featName] = baseName
                -- Log("[INFO] handler strippedName: " .. strippedName, true)
            end

            -- Execute handler if it exists in the dispatch table
            local handler = FeatBaseHandlers[baseName]
            if handler then
                -- Log("[INFO] handler baseName: " .. baseName, true)
                handler(char, ref)
            end
        end
    )

    -- Individual feat hooks
    TryHook("/Game/Gameplay/Feats/F_LoneWolf.F_LoneWolf_C:Get Conditional Effects", LoneWolfHandler)
    TryHook("/Game/Gameplay/Feats/F_Warrior.F_Warrior_C:Get Conditional Effects", WarriorHandler)
    TryHook("/Game/Gameplay/Feats/F_Gladiator.F_Gladiator_C:Get Conditional Effects", GladiatorHandler)
    TryHook("/Game/Gameplay/Feats/F_Basher.F_Basher_C:Get Conditional Effects", BasherHandler)
    TryHook("/Game/Gameplay/Feats/F_Butcher.F_Butcher_C:Get Conditional Effects", ButcherHandler)
    TryHook("/Game/Gameplay/Feats/F_HeavyHitter.F_HeavyHitter_C:Get Conditional Effects", HeavyHitterHandler)
    TryHook("/Game/Gameplay/Feats/F_Educated.F_Educated_C:Is Available To Learn", EducatedHandler)
    TryHook("/Game/Gameplay/Feats/F_MasterTrader.F_MasterTrader_C:Is Available To Learn", MasterTraderHandler)
    TryHook("/Game/Gameplay/Feats/F_ToughBastard.F_ToughBastard_C:Is Available To Learn", ToughBastardHandler)
    TryHook("/Game/Scripts/ItsBpLib.ItsBpLib_C:GetMaxImplants", ImplantHandler)
end)

-- ------------------------------------------------------------------------
-- CDO text patching: Description + Requirement
-- Status: Works
-- ------------------------------------------------------------------------
local function PatchCDOs(descriptionsParam)
    -- Localize globals for speed
    local pairs, match            = pairs, string.match
    local FText, StaticFindObject = FText, StaticFindObject
    -- Use the global trim if it exists, otherwise a fallback
    local _trim                   = Trim or function(s) return s:match("^%s*(.-)%s*$") end

    -- Predefine patterns (faster than compiling on the fly)
    local SUFFIX_PATTERN          = "^(.+):req$"
    local SPLIT_PATTERN           = "^(.-)%s*:req%s*(.+)$"
    local CLASS_PATTERN           = "^(.-)%.([^%.]+)$"

    local updated, failed         = 0, 0
    local seen                    = {}

    for key, fullText in pairs(descriptionsParam) do
        local base = match(key, SUFFIX_PATTERN) or key

        if not seen[base] then
            seen[base] = true

            local packagePath, className = match(base, CLASS_PATTERN)
            if not packagePath or not className then
                Log("[WARN] Could not parse classPath: " .. base)
                failed = failed + 1
            else
                local cdoPath = packagePath .. ".Default__" .. className
                local cdo = StaticFindObject(cdoPath)

                if cdo and cdo:IsValid() then
                    -- Logic fix: use 'fullText' from the iterator directly
                    local descPart, reqPart = match(fullText, SPLIT_PATTERN)
                    descPart = descPart or fullText

                    cdo:SetPropertyValue("Description", FText(_trim(descPart)))
                    if reqPart then
                        cdo:SetPropertyValue("Requirement", FText(_trim(reqPart)))
                    end

                    updated = updated + 1
                else
                    Log("[WARN] CDO not found: " .. cdoPath)
                    failed = failed + 1
                end
            end
        end
    end

    -- Log(string.format("[INFO] CDO patch: %d patched, %d failed", updated, failed), true)
    return updated > 0
end

-- ------------------------------------------------------------------------
-- Main
-- Status: Works
-- ------------------------------------------------------------------------
local function RunMod()
    InitLog()    -- should run only once
    LoadConfig() -- should run only once

    if not isFunctionsCached then
        CacheFunctions()
        isFunctionsCached = true
    end

    if not descriptions then
        descriptions = LoadDescriptions()
    end

    if not descriptions or next(descriptions) == nil then
        Log("[ERROR] No descriptions loaded", true)
        return false
    end
    return PatchCDOs(descriptions)
end

-- ------------------------------------------------------------------------
-- Trigger: InitGameState fires on every world load.
-- Status: Works
-- ------------------------------------------------------------------------
RegisterInitGameStatePostHook(function()
    ExecuteInGameThread(function()
        local ok = RunMod()
        if not ok then
            Log("[INFO] Patch returned false — check log for details", true)
        end
    end)
end)

-- Testing
local function FindVisComponentForNpc(npcName)
    local all = FindAllOf("ItsVisibilityComponent_C")
    if not all then return nil end
    for _, v in ipairs(all) do
        if v:IsValid() then
            -- GetOuter() returns the owning actor
            local outer = v:GetOuter()
            if outer and outer:IsValid() then
                local outerFName = outer:GetFName():ToString()
                if outerFName == npcName then
                    return v
                end
            end
        end
    end
    return nil
end

local function CalcCharEffectsFeats(char)
    if not cachedCalcFn or not cachedCalcFn:IsValid() then return false end
    -- Re-validate char is still alive
    local stillValid = pcall(function()
        local _ = char:GetCharID()
    end)
    if not stillValid then
        Log("[DEBUG] char went stale", true)
        return false
    end
    local ok, err = pcall(function()
        char:ProcessEvent(cachedCalcFn, {
            Reason              = 0,
            ["Is Updated"]      = false,
            ["Effects to Sum"]  = {},
            ["Default Objects"] = {},
            ["Recalc Required"] = false,
        })
    end)
    if not ok then Log("[DEBUG] ProcessEvent error: " .. tostring(err), true) end
    return ok
end

local function GetVCOStealFn()
    local cdo = StaticFindObject("/Game/Gameplay/Plot/PlotFuncs.Default__PlotFuncs_C")
    if not cdo or not cdo:IsValid() then
        Log("[AddSteal] PlotFuncs CDO not found", true)
        return nil, nil
    end
    local fn = StaticFindObject("/Game/Gameplay/Plot/PlotFuncs.PlotFuncs_C:VCO_Steal")
    if not fn or not fn:IsValid() then
        Log("[AddSteal] VCO_Steal UFunction not found via StaticFindObject", true)
        return nil, nil
    end
    return cdo, fn
end

local function GetAsUObject(actor)
    local fullPath = actor:GetFullName()
    -- GetFullName returns "ClassName /Path/To/Instance"
    -- Extract just the path part
    local path = fullPath:match("^%S+ (.+)$")
    if not path then return nil end
    local obj = StaticFindObject(path)
    if obj and obj:IsValid() then
        print("[DEBUG] UObject type: " .. tostring(obj))
        return obj
    end
    return nil
end

local function AddSteal()
    local world = UEHelpers.GetWorld()
    if not world or not world:IsValid() then
        Log("[AddSteal] No world", true)
        return
    end

    local plotCDO, fn = GetVCOStealFn()
    if not plotCDO or not fn then return end

    local BWClass = StaticFindObject("/Game/Gameplay/System/BasicOverheadWidgetComponent.BasicOverheadWidgetComponent_C")
    if not BWClass or not BWClass:IsValid() then
        BWClass = FindFirstOf("BasicOverheadWidgetComponent_C")
    end
    if not BWClass or not BWClass:IsValid() then
        Log("[AddSteal] BWClass not found", true)
        return
    end

    for i = 1, 5 do
        local npcName = "NPC_Steal_" .. i
        local npc = StaticFindObject("/Game/Maps/ThePit.ThePit:PersistentLevel." .. npcName)
        if not npc or not npc:IsValid() then
            Log("[AddSteal] " .. npcName .. " not found", true)
        else
            local vco = npc:GetComponentByClass(BWClass)
            local vis = FindVisComponentForNpc(npcName)

            if vco and vco:IsValid() and vis then
                local ok, err = pcall(function()
                    plotCDO:ProcessEvent(fn, {
                        __WorldContext     = world,
                        ["Steal Type"]     = 0,
                        ["Skill Level"]    = 0,
                        Item               = {},
                        ["Credits Bonus"]  = 5000,
                        VCO                = vco,
                        ["Animated NPC"]   = npc,
                        ["Visibility Set"] = vis,
                        Specialist         = nil,
                    })
                end)
                Log("[AddSteal] " .. npcName .. ": " .. (ok and "OK" or tostring(err)), true)
            else
                Log("[AddSteal] " .. npcName .. " missing components vco=" ..
                    tostring(vco and vco:IsValid()) .. " vis=" .. tostring(vis ~= nil), true)
            end
        end
    end
end

-- ------------------------------------------------------------------------
-- F8: manual re-apply
-- Status: Does nothing
-- ------------------------------------------------------------------------
-- RegisterKeyBind(Key.F8, function()
--     descriptions = nil
--     ExecuteInGameThread(function()
--         local ok = RunMod()
--         print("[Rebalance] F8 re-apply: " .. (ok and "OK" or "FAILED — check log"), true)
--     end)
-- end)

-- RegisterKeyBind(Key.F5, function()
--     ExecuteInGameThread(function()
--         CacheFunctions()
--         if cachedCalcFn then
--             Log("[F4] CalcFn address: " .. tostring(cachedCalcFn), true)
--             local ok, fn = pcall(function() return cachedCalcFn:GetFullName() end)
--             Log("[F4] CalcFn fullname: " .. tostring(ok and fn or "ERR"), true)
--         end
--         if cachedPlotCDO then
--             Log("[F4] PlotCDO address: " .. tostring(cachedPlotCDO))
--             local ok, fn = pcall(function() return cachedPlotCDO:GetFullName() end)
--             Log("[F4] PlotCDO fullname: " .. tostring(ok and fn or "ERR"), true)
--         end
--         if cachedVCOStealFn then
--             Log("[F4] VCOSteal address: " .. tostring(cachedVCOStealFn))
--             local ok, fn = pcall(function() return cachedVCOStealFn:GetFullName() end)
--             Log("[F4] VCOSteal fullname: " .. tostring(ok and fn or "ERR"), true)
--         end

--         -- Test: call ProcessEvent with a no-op native function to isolate whether
--         -- the issue is the UFunction or the char object
--         local char = GetPlayerCharacter()
--         if char and char:IsValid() then
--             Log("[F4] char address: " .. tostring(char), true)
--             -- Try calling a known-working native function via direct call syntax
--             local ok2, id = pcall(function() return char:GetCharID() end)
--             Log("[F4] GetCharID via direct call: " .. tostring(ok2 and id or "ERR"), true)
--         end
--     end)
-- end)

-- RegisterKeyBind(Key.F4, function()
--     ExecuteInGameThread(function()
--         -- Hook the function to observe when the game calls it naturally
--         -- and capture the self object type at that moment
--         local hooked = false
--         local ok, err = pcall(function()
--             RegisterHook("/Game/Gameplay/Characters/Core/HumanRpgCharacter.HumanRpgCharacter_C:Calc Char Effects Feats",
--                 function(selfParam, reasonParam, isUpdatedParam, effectsParam, defaultObjParam, recalcParam)
--                     if hooked then return end
--                     hooked = true
--                     local self = selfParam:Get()
--                     print("[Hook] CalcFeatEffects fired!")
--                     print("[Hook] self type: " .. tostring(self))
--                     print("[Hook] self valid: " .. tostring(self and self:IsValid()))
--                     local ok2, id = pcall(function() return self:GetCharID() end)
--                     print("[Hook] charID: " .. tostring(ok2 and id or "ERR"))
--                     local ok3, reason = pcall(function() return reasonParam:get() end)
--                     print("[Hook] Reason value: " .. tostring(ok3 and reason or "ERR"))
--                 end
--             )
--         end)
--         print("[F4] Hook registered: " .. (ok and "OK" or tostring(err)))
--     end)
-- end)

-- RegisterKeyBind(Key.F7, function()
--     ExecuteInGameThread(function()
--         local char = GetPlayerCharacter()
--         if not char then
--             Log("[F7] no char", true)
--             return
--         end

--         local uobj = GetAsUObject(char)
--         if not uobj then
--             Log("[F7] GetAsUObject failed", true)
--             return
--         end
--         Log("[F7] uobj type: " .. tostring(uobj), true)

--         local ok, err = pcall(function()
--             uobj:ProcessEvent(cachedCalcFn, {
--                 Reason              = 0,
--                 ["Is Updated"]      = false,
--                 ["Effects to Sum"]  = {},
--                 ["Default Objects"] = {},
--                 ["Recalc Required"] = false,
--             })
--         end)
--         Log("[F7] ProcessEvent: " .. (ok and "OK" or tostring(err)), true)
--     end)
-- end)

-- RegisterKeyBind(Key.F6, function()
--     ExecuteInGameThread(AddSteal)
-- end)

-- RegisterKeyBind(Key.F7, function()
--     ExecuteInGameThread(function()
--         CachePlayerChar()
--         if not cachedPlayerChar then
--             Log("[F7] no cached char", true)
--             return
--         end
--         Log("[F7] cached char type: " .. tostring(cachedPlayerChar), true)

--         -- Test ProcessEvent with UObject-typed reference
--         local ok, err = pcall(function()
--             cachedPlayerChar:ProcessEvent(cachedCalcFn, {
--                 Reason              = 0,
--                 ["Is Updated"]      = false,
--                 ["Effects to Sum"]  = {},
--                 ["Default Objects"] = {},
--                 ["Recalc Required"] = false,
--             })
--         end)
--         Log("[F7] ProcessEvent result: " .. (ok and "OK" or tostring(err)), true)

--         -- Also test UFunction direct call with UObject ref
--         local ok2, err2 = pcall(function()
--             cachedCalcFn(cachedPlayerChar, {
--                 Reason              = 0,
--                 ["Is Updated"]      = false,
--                 ["Effects to Sum"]  = {},
--                 ["Default Objects"] = {},
--                 ["Recalc Required"] = false,
--             })
--         end)
--         Log("[F7] UFunction direct call result: " .. (ok2 and "OK" or tostring(err2)), true)
--     end)
-- end)

RegisterKeyBind(Key.F7, function()
    ExecuteInGameThread(function()
        local char = GetPlayerCharacter()
        if not char or not char:IsValid() then
            Log("[F7] no char", true)
            return
        end

        local ok1, id = pcall(function() return char:GetCharID() end)
        Log("[F7] char id=" .. tostring(ok and id or "ERR"), true)

        -- Attempt 1: method syntax
        local ok2, err1 = pcall(function()
            char["Calc Char Effects Feats"](char, { Reason = 0 })
        end)
        Log("[F7] method syntax: " .. (ok2 and "OK" or tostring(err1)), true)

        -- -- Attempt 3: cached fn with only Reason
        -- local ok3, err3 = pcall(function()
        --     cachedCalcFn(char, { Reason = 0 })
        -- end)
        -- Log("[F7] cachedFn Reason only: " .. (ok3 and "OK" or tostring(err3)), true)

        -- -- Attempt 4: no params at all
        -- local ok4, err4 = pcall(function()
        --     cachedCalcFn(char, {})
        -- end)
        -- Log("[F7] cachedFn empty params: " .. (ok4 and "OK" or tostring(err4)), true)
    end)
end)

RegisterKeyBind(Key.F8, function()
    ExecuteInGameThread(function()
        CacheFunctions()
        Log("[F4] cachedCalcFn valid: " .. tostring(cachedCalcFn and cachedCalcFn:IsValid()), true)
        Log("[F4] cachedVCOStealFn valid: " .. tostring(cachedVCOStealFn and cachedVCOStealFn:IsValid()), true)
    end)
end)

-- RegisterKeyBind(Key.F8, function()
--     ExecuteInGameThread(function()
--         local paths = {
--             "/Game/Gameplay/Characters/Core/HumanRpgCharacter.HumanRpgCharacter_C",
--             "/Game/Gameplay/Characters/Core/RpgCharacter.RpgCharacter_C",
--             "/Game/Gameplay/Plot/PlotFuncs.PlotFuncs_C",
--             "/Game/Gameplay/Plot/PlotFuncs.Default__PlotFuncs_C",
--         }
--         for _, p in ipairs(paths) do
--             local obj = StaticFindObject(p)
--             print("[F4] " .. p .. " => " .. tostring(obj and obj:IsValid()))
--         end

--         -- Try getting UClass from a live instance instead
--         local chars = FindAllOf("HumanRpgCharacter_C")
--         if chars and chars[1] and chars[1]:IsValid() then
--             local c = chars[1]
--             print("[F4] Instance full name: " .. c:GetFullName())
--             -- Attempt FindFunction directly on instance (some UE4SS builds support this)
--             local ok, fn = pcall(function()
--                 return c:FindFunction("Calc Char Effects Feats")
--             end)
--             print("[F4] FindFunction on instance: ok=" .. tostring(ok) .. " fn=" .. tostring(ok and fn and fn:IsValid()))
--         end
--     end)
-- end)
