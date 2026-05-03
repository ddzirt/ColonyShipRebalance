-- ============================================================
-- Colony Ship Rebalance Mod(feats for now)
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
local LANG_PATH   = SCRIPT_PATH .. "localization/"
local LOG_PATH    = SCRIPT_PATH .. "RebalanceLog.txt"

do
    local f = io.open(LOG_PATH, "w")
    if f then f:close() end
end

local function Log(msg)
    local f = io.open(LOG_PATH, "a")
    if f then
        f:write(msg .. "\n")
        f:close()
    end
    print("[FeatRebalance] " .. msg .. "\n")
end

Log("[INFO] Mod initialized. Script path: " .. SCRIPT_PATH)

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
    local hpOk, cur = pcall(function() return char:GetPropertyValue("HP") end)
    local mhpOk, max = pcall(function() return char:GetPropertyValue("MaxHP") end)
    if not hpOk or not mhpOk or not cur or not max then return nil, nil, nil end
    local curVal = type(cur) == "number" and cur or nil
    local maxVal = type(max) == "number" and max or nil
    if not curVal or not maxVal or maxVal == 0 then return nil, nil, nil end
    return curVal, maxVal, curVal / maxVal
end

-- Read a numeric stat from a character, trying multiple property name candidates.
local function GetAttribute(char, statIndex)
    -- Crucial: Check if the character exists before calling functions
    if not char or not char:IsValid() then
        return nil
    end

    local status, val = pcall(function()
        return char:GetStatValue_Base(statIndex)
    end)

    return status and val or nil
end

local function trim(s)
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

-- ------------------------------------------------------------------------
-- CONFIG DEFAULTS
-- ------------------------------------------------------------------------
local DEFAULTS = {
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
    EDUCATED_SXP_BONUS      = 5,
    EDUCATED_INT_MIN        = 6,
    MASTERMIND_SXP_BONUS    = 5,
    GIFTED_SKILL_SXP        = 5,
    HF_REGEN_PER_LEVELS     = 3,
    FR_EVASION              = 6,
    GLADIATOR_MIN           = 1,
    GLADIATOR_MAX           = 1,
    HH_PER                  = 3,
    HH_CRIT_PER_STEP        = 1,
    TB_CON                  = 6,
    BIONIC_IMPLANTS         = 2,
    DEBUG                   = false,
}

local cfg = {}

local statMapping = {
    STR = 0,
    DEX = 1,
    CON = 2,
    PER = 3,
    INT = 4,
    CHA = 5,
}

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
        line = trim(line)
        if line ~= "" and not line:match("^[;#]") then
            local key, value = line:match("^([^=]+)%s*=%s*(.+)$")
            if key and value then
                key   = trim(key)
                value = trim(value)
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

local function loadConfig()
    local ini = ParseIni(CONFIG_PATH)
    for k, v in pairs(DEFAULTS) do
        cfg[k] = (ini[k] ~= nil) and ini[k] or v
    end
    Log("[INFO] Config loaded from " .. CONFIG_PATH)
end

-- ------------------------------------------------------------------------
-- Load descriptions
-- ------------------------------------------------------------------------
local function loadDescriptions()
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
        return {}
    end
    local ok, descFunc = pcall(loader)
    if not ok or type(descFunc) ~= "function" then
        Log("[ERROR] Failed to load descriptions: " .. tostring(descFunc))
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
    return descs or {}
end

-- ------------------------------------------------------------------------
-- Field constants (CsgCharEffects mangled property names)
-- ------------------------------------------------------------------------
local F                = {
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
-- State trackers
-- ------------------------------------------------------------------------
local AppliedModifiers = {}
local FeatBaseHooked   = false

-- -- ------------------------------------------------------------------------
-- -- Feat class references for Has Feat checks
-- -- ------------------------------------------------------------------------
local FeatClasses      = {
    Educated      = "/Game/Gameplay/Feats/F_Educated.F_Educated_C",
    Mastermind    = "/Game/Gameplay/Feats/F_H_Mastermind.F_H_Mastermind_C",
    Gifted        = "/Game/Gameplay/Feats/F_Gifted.F_Gifted_C",
    FastRunner    = "/Game/Gameplay/Feats/F_H_FastRunner.F_H_FastRunner_C",
    HealingFactor = "/Game/Gameplay/Feats/F_H_HealingFactor.F_H_HealingFactor_C",
    ToughBastard  = "/Game/Gameplay/Feats/F_ToughBastard.F_ToughBastard_C",
}

-- ------------------------------------------------------------------------
-- Hook helper
-- ------------------------------------------------------------------------
local function HookFeat(classPath, fnName, callback)
    local registered = false
    NotifyOnNewObject(classPath, function()
        if registered then return end
        registered = true
        local ok, err = pcall(function()
            RegisterHook(classPath .. ":" .. fnName, callback)
        end)
        if ok then
            Log("[INFO] Hook registered: " .. classPath .. ":" .. fnName)
        else
            Log("[WARN] Hook FAILED: " .. classPath .. ":" .. fnName .. " | " .. tostring(err))
        end
    end)
end

-- ------------------------------------------------------------------------
-- LONE WOLF
-- Vanilla (solo): +12 Evasion, +16 Initiative
-- Rebalanced:     +LW_EVASION, +LW_INITIATIVE, +LW_ARMOR_PENALTY
-- STATUS: Works
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_LoneWolf.F_LoneWolf_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        if not IsConditionMet(IsValid) then return end
        local ref = GetEffects(Effects)
        if not ref then return end

        Set(ref, F.Evasion, cfg.LW_EVASION)
        Set(ref, F.Initiative, cfg.LW_INITIATIVE)
        Set(ref, F.ArmorPenalty, cfg.LW_ARMOR_PENALTY)

        local char           = GetChar(OwnerCharacter)
        local id             = char and tostring(char) or "?"
        AppliedModifiers[id] = AppliedModifiers[id] or {}
        if not AppliedModifiers[id].LoneWolf then
            Log("[INFO] LoneWolf: applied")
            AppliedModifiers[id].LoneWolf = true
        end
    end
)

-- ------------------------------------------------------------------------
-- WARRIOR
-- Addition: +ArmorHandling per melee skill level
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_Warrior.F_Warrior_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        if not IsConditionMet(IsValid) then return end
        local ref = GetEffects(Effects)
        if not ref then return end

        local char = GetChar(OwnerCharacter)
        -- local skillLevel = (char and GetStat(char, { "MeleeSkill", "MeleeSkills", "Melee", "MeleeLevel", "SkillMelee" })) or
        --     1
        -- local bonus      = math.max(1, skillLevel) * cfg.WARRIOR_ARMOR_PER_LEVEL

        -- Set(ref, F.ArmorPenalty, bonus)

        -- local id = char and tostring(char) or "?"
        -- AppliedModifiers[id] = AppliedModifiers[id] or {}
        -- if not AppliedModifiers[id].Warrior then
        --     Log("[INFO] Warrior: ArmorHandling +" .. bonus)
        --     AppliedModifiers[id].Warrior = true
        -- end
    end
)

-- ------------------------------------------------------------------------
-- BERSERKER
-- Vanilla: +2 MeleeDMG at <=13 HP
-- Rebalanced: tiered above vanilla threshold
--   >50% HP  : nothing extra
--   <=50% HP : +1 min/max
--   <=25% HP : +2 min/max
--   <=13 HP  : vanilla handles, we exit
-- IsConditionMet NOT used — vanilla IsValid is false above 13 HP.
-- STATUS: Did not work, needs testing
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_Berserker.F_Berserker_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local char = GetChar(OwnerCharacter)
        if not char then return end

        local curHP, _, ratio = GetHP(char)
        if not curHP or curHP <= 0 then return end
        if curHP <= 13 then return end

        local ref = GetEffects(Effects)
        if not ref then return end

        if ratio <= cfg.BERSERK_LOW_HP_PCT then
            Set(ref, F.MeleeMinDMG, 2)
            Set(ref, F.MeleeMaxDMG, 2)
            Log("[INFO] Berserker: tier 2 (" .. math.floor(ratio * 100) .. "%)")
        elseif ratio <= cfg.BERSERK_MID_HP_PCT then
            Set(ref, F.MeleeMinDMG, 1)
            Set(ref, F.MeleeMaxDMG, 1)
            Log("[INFO] Berserker: tier 1 (" .. math.floor(ratio * 100) .. "%)")
        end
    end
)

-- ------------------------------------------------------------------------
-- BASHER (blunt weapons)
-- Vanilla: penetration bonus — replaced
-- Rebalanced: +THC, +knockdown, +aimed THC per melee skill level
-- STATUS: Did not work, needs testing
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_Basher.F_Basher_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        if not IsConditionMet(IsValid) then return end
        local ref = GetEffects(Effects)
        if not ref then return end

        local char = GetChar(OwnerCharacter)
        -- local skillLevel = (char and GetStat(char, { "MeleeSkill", "MeleeSkills", "Melee", "MeleeLevel", "SkillMelee" })) or
        --     1

        -- Set(ref, F.PenetrationPct, 0)
        -- Set(ref, F.MeleeTHC, cfg.BASHER_THC)
        -- Set(ref, F.KnockdownChance, cfg.BASHER_KNOCKDOWN)
        -- Set(ref, F.AimedTHC, math.max(1, skillLevel) * cfg.BASHER_AIMED_PER_LEVEL)
        -- Log("[INFO] Basher: applied (melee skill=" .. skillLevel .. ")")
    end
)

-- ------------------------------------------------------------------------
-- BUTCHER (bladed weapons)
-- Vanilla: aimed bonus — replaced
-- Rebalanced: +THC, +crit, +penetration per melee skill level
-- STATUS: Did not work, needs testing
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_Butcher.F_Butcher_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        if not IsConditionMet(IsValid) then return end
        local ref = GetEffects(Effects)
        if not ref then return end

        local char = GetChar(OwnerCharacter)
        -- local skillLevel = (char and GetStat(char, { "MeleeSkill", "MeleeSkills", "Melee", "MeleeLevel", "SkillMelee" })) or
        --     1

        -- Set(ref, F.AimedTHC, 0)
        -- Set(ref, F.MeleeTHC, cfg.BUTCHER_THC)
        -- Set(ref, F.CSC, cfg.BUTCHER_CSC)
        -- Set(ref, F.PenetrationPct, math.max(1, skillLevel) * cfg.BUTCHER_PEN_PER_LEVEL)
        -- Log("[INFO] Butcher: applied (melee skill=" .. skillLevel .. ")")
    end
)

-- ------------------------------------------------------------------------
-- JUGGERNAUT (Heroic)
-- Vanilla: +1 DR always, +4 DR at <=13 HP
-- Rebalanced: tiered above vanilla threshold
--   >50% HP  : +1 DR
--   <=50% HP : +2 DR
--   <=25% HP : +3 DR
--   <=13 HP  : vanilla handles +4, we exit
-- IsConditionMet NOT used — same reason as Berserker.
-- STATUS: Did not work, needs testing
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_H_Juggernaut.F_H_Juggernaut_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local char = GetChar(OwnerCharacter)
        if not char then return end

        local curHP, _, ratio = GetHP(char)
        if not curHP or curHP <= 0 then return end
        if curHP <= 13 then return end

        local ref = GetEffects(Effects)
        if not ref then return end

        if ratio <= cfg.JUGG_LOW_HP_PCT then
            Set(ref, F.NaturalDR, 3)
            Log("[INFO] Juggernaut: tier 3 (" .. math.floor(ratio * 100) .. "%)")
        elseif ratio <= cfg.JUGG_MID_HP_PCT then
            Set(ref, F.NaturalDR, 2)
            Log("[INFO] Juggernaut: tier 2 (" .. math.floor(ratio * 100) .. "%)")
        else
            Set(ref, F.NaturalDR, 1)
        end
    end
)

-- ------------------------------------------------------------------------
-- GLADIATOR
-- Addition: flat +min/max melee damage
-- STATUS: Did not work, needs testing
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_Gladiator.F_Gladiator_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        if not IsConditionMet(IsValid) then return end
        local ref = GetEffects(Effects)
        if not ref then return end

        Set(ref, F.MeleeMinDMG, cfg.GLADIATOR_MIN)
        Set(ref, F.MeleeMaxDMG, cfg.GLADIATOR_MAX)
        Log("[INFO] Gladiator: +" .. cfg.GLADIATOR_MIN .. "/" .. cfg.GLADIATOR_MAX .. " min/max dmg")
    end
)

-- ------------------------------------------------------------------------
-- HEAVY HITTER
-- Addition: +CSC per N points of Perception
-- STATUS: Did not work, needs testing
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_HeavyHitter.F_HeavyHitter_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        if not IsConditionMet(IsValid) then return end
        local ref = GetEffects(Effects)
        if not ref then return end

        local char = GetChar(OwnerCharacter)
        if not char then return end

        local per = GetAttribute(char, statMapping.PER)
        local critBonus = math.floor(per / cfg.HH_PER) * cfg.HH_CRIT_PER_STEP
        if critBonus > 0 then
            Set(ref, F.CSC, critBonus)
            Log("[INFO] HeavyHitter: +" .. critBonus .. "% CSC (Per=" .. per .. ")")
        end
    end
)

-- -- ------------------------------------------------------------------------
-- -- FEATBASE HOOK
-- -- Handles feats that have no Get Conditional Effects override of their own:
-- -- Educated, Mastermind, Gifted, ToughBastard, FastRunner, HealingFactor.
-- --
-- -- Class identification via self is unreliable (GetClass() returns nullptr
-- -- on many invocations). Instead we use Has Feat on the OwnerCharacter —
-- -- calling the game's own function with pre-loaded UClass references.
-- --
-- -- Has Feat signature (dump L103162):
-- --   RpgCharacter_C:Has Feat(Feat: TSubclassOf<FeatBase>) -> Yes (bool)
-- -- The Feat parameter is a UClass reference, which StaticFindObject returns
-- -- when given the class path (not the CDO path).
-- --
-- -- ------------------------------------------------------------------------
-- NotifyOnNewObject("/Game/Gameplay/Feats/BaseTypes/FeatBase.FeatBase_C",
--     function()
--         if FeatBaseHooked then return end
--         FeatBaseHooked = true

--         local ok, err = pcall(function()
--             RegisterHook(
--                 "/Game/Gameplay/Feats/BaseTypes/FeatBase.FeatBase_C:Get Conditional Effects",
--                 function(self, OwnerCharacter, Effects, IsValid)
--                     -- Safely get the feat instance and its class path
--                     local path = ""
--                     pcall(function()
--                         local featObj = self:get()
--                         if featObj and featObj:IsValid() then
--                             local cls = featObj:GetClass()
--                             if cls and cls:IsValid() then
--                                 path = cls:GetPathName() -- e.g. "/Game/Gameplay/Feats/F_Educated.F_Educated_C"
--                             end
--                         end
--                     end)
--                     Log("[INFO] FeatBase class path: " .. path)

--                     -- local path = ""
--                     -- pcall(function() path = self:get():GetPathName() end)
--                     -- Log("[INFO] FeatBase self path: " .. path)

--                     -- local char = GetChar(OwnerCharacter)
--                     -- if not char then return end

--                     -- local ref = GetEffects(Effects)
--                     -- if not ref then return end

--                     -- -- EDUCATED: +SkillXP if INT meets threshold
--                     -- -- Log("[INFO] HasFeat Educated: " .. tostring(HasFeat(char, FeatClasses.Educated)) .. ".")
--                     -- local educatedClass = GetFeatClass("/Game/Gameplay/Feats/F_Educated.F_Educated_C")
--                     -- Log("[INFO] educatedClass: " .. tostring(educatedClass) .. ".")
--                     -- Log("[INFO] HasFeat: " .. tostring(HasFeat(char, educatedClass)) .. ".")
--                     -- if educatedClass and HasFeat(char, educatedClass) then
--                     --     local intel   = GetStat(char, { "Intelligence", "Int", "INTEL" })
--                     --     local applies = (not intel) or (intel >= cfg.EDUCATED_INT_MIN)
--                     --     if applies then
--                     --         Set(ref, F.SkillXPGain, cfg.EDUCATED_SXP_BONUS)
--                     --         Log("[INFO] Educated: +" .. cfg.EDUCATED_SXP_BONUS .. "% SkillXP")
--                     --     else
--                     --         Log("[INFO] Educated: INT<" .. cfg.EDUCATED_INT_MIN .. ", suppressed")
--                     --     end

--                     --     -- MASTERMIND: +SkillXP always
--                     -- elseif FeatClasses.Mastermind and HasFeat(char, FeatClasses.Mastermind) then
--                     --     Set(ref, F.SkillXPGain, cfg.MASTERMIND_SXP_BONUS)
--                     --     Log("[INFO] Mastermind: +" .. cfg.MASTERMIND_SXP_BONUS .. "% SkillXP")

--                     --     -- GIFTED: +SkillXP always
--                     -- elseif FeatClasses.Gifted and HasFeat(char, FeatClasses.Gifted) then
--                     --     Set(ref, F.SkillXPGain, cfg.GIFTED_SKILL_SXP)
--                     --     Log("[INFO] Gifted: +" .. cfg.GIFTED_SKILL_SXP .. "% SkillXP")

--                     --     -- FAST RUNNER: +Evasion
--                     --     -- Same hook writes to Effects — same mechanism as LoneWolf's Evasion
--                     -- elseif FeatClasses.FastRunner and HasFeat(char, FeatClasses.FastRunner) then
--                     --     Set(ref, F.Evasion, cfg.FR_EVASION)
--                     --     Log("[INFO] FastRunner: +" .. cfg.FR_EVASION .. " Evasion")

--                     --     -- HEALING FACTOR: +HPRegen scaled by character level
--                     -- elseif FeatClasses.HealingFactor and HasFeat(char, FeatClasses.HealingFactor) then
--                     --     local level = GetCharLevel(char)
--                     --     local bonus = math.floor(level / cfg.HF_REGEN_PER_LEVELS)
--                     --     if bonus > 0 then
--                     --         Set(ref, F.HPRegen, bonus)
--                     --         Log("[INFO] HealingFactor: level=" .. level .. " HPRegen+" .. bonus)
--                     --     end
--                 end
--             )
--         end)
--         if ok then
--             Log("[INFO] Hook registered: FeatBase:Get Conditional Effects")
--         else
--             Log("[WARN] Hook FAILED: FeatBase:Get Conditional Effects | " .. tostring(err))
--         end
--     end
-- )

-- ------------------------------------------------------------------------
-- EDUCATED — Is Available To Learn
-- Gates feat selection on INT >= EDUCATED_INT_MIN.
-- Signature (dump L82223): (OwnerCharacter) -> Yes (BoolProperty)
-- STATUS: Works
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_Educated.F_Educated_C",
    "Is Available To Learn",
    function(self, OwnerCharacter, Yes)
        local char = GetChar(OwnerCharacter)
        if not char then return end

        local int = GetAttribute(char, statMapping.INT)
        if int and int < cfg.EDUCATED_INT_MIN then
            Log("[INFO] Educated: blocked (INT=" .. int .. " < " .. cfg.EDUCATED_INT_MIN .. ")")
            Yes:set(false)
        end
    end
)

-- ------------------------------------------------------------------------
-- TOUGH BASTARD — Is Available To Learn
-- Gates feat selection on CON >= TB_CON.
-- STATUS: Works
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_ToughBastard.F_ToughBastard_C",
    "Is Available To Learn",
    function(self, OwnerCharacter, Yes)
        local char = GetChar(OwnerCharacter)
        if not char then return end

        local con = GetAttribute(char, statMapping.CON)
        if con and con < cfg.TB_CON then
            Log("[INFO] ToughBastard: blocked (CON=" .. con .. " < " .. cfg.TB_CON .. ")")
            Yes:set(false)
        end
    end
)

-- ------------------------------------------------------------------------
-- Calculation patching for multiple feats
-- STATUS: Works partially(tested for Educated, FastRunner)
-- TODO: Test HealingFactor, Mastermind, Gifted and combo of MM+Educated and Gifted+Educated
-- ------------------------------------------------------------------------
NotifyOnNewObject("/Game/Gameplay/Feats/BaseTypes/FeatBase.FeatBase_C",
    function()
        if FeatBaseHooked then return end
        FeatBaseHooked = true
        local ok, err = pcall(function()
            RegisterHook(
                "/Game/Gameplay/Feats/BaseTypes/FeatBase.FeatBase_C:Get Effects",
                function(self, OwnerCharacter, UpgradeBits, Effects)
                    local featName = ""
                    pcall(function() featName = self:get():GetFName():ToString() end)
                    if featName == "" then return end

                    local ref = GetEffects(Effects)
                    if not ref then return end

                    if featName:find("F_Educated_C", 1, true) then
                        local char = GetChar(OwnerCharacter)
                        local int  = char and char:GetStatValue_Base(4) or 99
                        if int >= cfg.EDUCATED_INT_MIN then
                            Set(ref, F.SkillXPGain, cfg.EDUCATED_SXP_BONUS)
                            Log("[INFO] Educated: +" .. cfg.EDUCATED_SXP_BONUS .. "% SkillXP (INT=" .. int .. ")")
                        end
                    elseif featName:find("F_H_Mastermind_C", 1, true) then
                        Set(ref, F.SkillXPGain, cfg.MASTERMIND_SXP_BONUS)
                        Log("[INFO] Mastermind: +" .. cfg.MASTERMIND_SXP_BONUS .. "% SkillXP")
                    elseif featName:find("F_Gifted_C", 1, true) then
                        Set(ref, F.SkillXPGain, cfg.GIFTED_SKILL_SXP)
                        Log("[INFO] Gifted: +" .. cfg.GIFTED_SKILL_SXP .. "% SkillXP")
                    elseif featName:find("F_H_FastRunner_C", 1, true) then
                        Set(ref, F.Evasion, cfg.FR_EVASION)
                        Log("[INFO] FastRunner: +" .. cfg.FR_EVASION .. " Evasion")
                    elseif featName:find("F_H_HealingFactor_C", 1, true) then
                        local char  = GetChar(OwnerCharacter)
                        local level = char and GetCharLevel(char) or 0
                        local bonus = math.floor(level / cfg.HF_REGEN_PER_LEVELS)
                        if bonus > 0 then
                            Set(ref, F.HPRegen, bonus)
                            Log("[INFO] HealingFactor: level=" .. level .. " +HPRegen=" .. bonus)
                        end
                    end
                end
            )
        end)
        if ok then
            Log("[INFO] Hook registered: FeatBase:Get Effects")
        else
            Log("[WARN] Hook FAILED: FeatBase:Get Effects | " .. tostring(err))
        end

        -- Does not work as of yet
        ok, err = pcall(function()
            RegisterPreHook("/Game/Scripts/ItsBpLib.ItsBpLib_C:GetMaxImplants",
                function(self, Character, GatherTooltipInfo) -- 1. Manually execute the original function logic
                    -- In a Blueprint Library, 'self' is the Class Default Object (CDO)
                    local results = self:GetMaxImplants(Character, GatherTooltipInfo)

                    -- 2. Modify the result in the clean Lua table
                    -- 'results' will contain 'res', 'Feat Bonus', and 'Stat Value'
                    if results and results.res then
                        local originalMax = results.res
                        Log("[INFO] GetMaxImplants, originalMax: " .. tostring(originalMax))
                        results.res = originalMax + 2 -- Your rebalance value

                        -- Optional: Log the change using your existing format
                        Log(string.format("[INFO] GetMaxImplants Patched | %d -> %d", originalMax, results.res))
                    end

                    -- 3. Return the table to 'short-circuit' the engine call.
                    -- The game will use your modified table instead of running the original BP code.
                    return results
                    -- Log("[INFO] GetMaxImplants, mapping is failing entirely")
                end)
        end)
        if ok then
            Log("[INFO] Hook registered: ItsBpLib_C:GetMaxImplants")
        else
            Log("[WARN] Hook FAILED: ItsBpLib_C:GetMaxImplants | " .. tostring(err))
        end
    end
)


-- ------------------------------------------------------------------------
-- Hooking GetMaxImplants
-- Use the shortened class:function format to avoid path resolution errors
-- STATUS: Unverified
-- ------------------------------------------------------------------------
-- RegisterHook("/Game/Scripts/ItsBpLib.ItsBpLib_C:GetMaxImplants", function(self, params)
--     -- UE4SS usually maps the primary output to 'res' if named so in the dump.
--     -- If 'res' is nil, we check 'ReturnValue' as a fallback.
--     local res = params.res or params.ReturnValue

--     -- Parameters with spaces must be accessed via string keys
--     local featBonus = params["Feat Bonus"] or 0
--     local statValue = params["Stat Value"] or 0

--     -- Safety check to prevent the 'compare number with nil' error
--     if res == nil then
--         print("[UE4SS] GetMaxImplants: 'res' is nil. Dumping available keys:")
--         for key, _ in pairs(params) do
--             print("Found Key: " .. tostring(key))
--         end
--         return
--     end

--     -- Perform your logic (example: +1 to max implants)
--     -- Note: Writing back to the params object updates the game value
--     params.res = res + 1

--     print(string.format("[UE4SS] GetMaxImplants Modified | Old: %d | New: %d", res, params.res))
-- end)

-- ------------------------------------------------------------------------
-- CDO text patching: Description + Requirement
-- ------------------------------------------------------------------------
local function PatchCDOs(descriptions)
    Log("[INFO] Patching feat CDO text properties...")

    local updated    = 0
    local failed     = 0

    local classPaths = {}
    for key in pairs(descriptions) do
        local base = key:match("^(.+):req$") or key
        classPaths[base] = true
    end

    for classPath in pairs(classPaths) do
        local packagePath, className = classPath:match("^(.+)%.(.+)$")
        if not packagePath or not className then
            Log("[WARN] Could not parse classPath: " .. classPath)
            failed = failed + 1
        else
            local cdoPath = packagePath .. ".Default__" .. className
            local cdo = StaticFindObject(cdoPath)
            if cdo and cdo:IsValid() then
                local descText = descriptions[classPath]
                if descText then
                    cdo:SetPropertyValue("Description", FText(descText))
                    Log("[INFO] Description patched: " .. cdoPath)
                end
                local reqText = descriptions[classPath .. ":req"]
                if reqText then
                    cdo:SetPropertyValue("Requirement", FText(reqText))
                    Log("[INFO] Requirement patched: " .. cdoPath)
                end
                updated = updated + 1
            else
                Log("[WARN] CDO not found: " .. cdoPath)
                failed = failed + 1
            end
        end
    end

    Log("[INFO] CDO patch: " .. updated .. " patched, " .. failed .. " failed")
    return updated > 0
end

-- ------------------------------------------------------------------------
-- Main
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
    return PatchCDOs(descriptions)
end

-- ------------------------------------------------------------------------
-- Trigger: InitGameState fires on every world load.
-- ------------------------------------------------------------------------
RegisterInitGameStatePostHook(function()
    Log("[INFO] InitGameState — patching CDO text properties")
    ExecuteInGameThread(function()
        local ok = RunMod()
        if not ok then
            Log("[INFO] Patch returned false — check log for details")
        end
    end)
end)

-- ------------------------------------------------------------------------
-- F8: manual re-apply
-- ------------------------------------------------------------------------
RegisterKeyBind(Key.F8, function()
    descriptions = nil
    ExecuteInGameThread(function()
        local ok = RunMod()
        print("[FeatRebalance] F8 re-apply: " .. (ok and "OK" or "FAILED — check log"))
    end)
end)

Log("[INFO] Mod loaded. Hooks registered. Waiting for InitGameState.")
