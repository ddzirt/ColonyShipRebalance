-- ============================================================
-- Colony Ship Feat Rebalance Mod
-- Merges: description patching (CDO via StaticFindObject)
--         effect hooks (Get Conditional Effects per feat)
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

-- Truncate log on each session start
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
-- INI Parser
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
    DEBUG                   = false,
}

local cfg = {}

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
-- Field helpers (shared by all effect hooks)
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

local function GetHP(char)
    local hpOk, cur = pcall(function() return char:GetPropertyValue("HP") end)
    local mhpOk, max = pcall(function() return char:GetPropertyValue("MaxHP") end)
    if not hpOk or not mhpOk or not cur or not max then return nil, nil, nil end
    local curVal = type(cur) == "number" and cur or (pcall(function() return cur:get() end) and cur:get() or nil)
    local maxVal = type(max) == "number" and max or (pcall(function() return max:get() end) and max:get() or nil)
    if not curVal or not maxVal or maxVal == 0 then return nil, nil, nil end
    return curVal, maxVal, curVal / maxVal
end

-- ------------------------------------------------------------------------
-- Field constants (CsgCharEffects mangled property names)
-- ------------------------------------------------------------------------
local F                 = {
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
local AppliedModifiers  = {}
local GiftedAddedHooked = false
local FeatBaseHooked    = false
local RegenBaseHooked   = false

-- ------------------------------------------------------------------------
-- Hook helpers
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
            Log("[INFO] Hook registered: " .. classPath)
        else
            Log("[WARN] Hook FAILED: " .. classPath .. " | " .. tostring(err))
        end
    end)
end

local function GetFeatClassName(self)
    local ok, cls = pcall(function() return self:get():GetClass() end)
    if not ok or not cls then return "" end
    local nok, name = pcall(function() return cls:GetFullName() end)
    return nok and (name or "") or ""
end

-- ------------------------------------------------------------------------
-- LONE WOLF
-- Vanilla (solo): +12 Evasion, +16 Initiative
-- Rebalanced:     +LW_EVASION Evasion, +LW_INITIATIVE Initiative,
--                 +LW_ARMOR_PENALTY ArmorHandling
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_LoneWolf.F_LoneWolf_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref  = GetEffects(Effects)
        local char = GetChar(OwnerCharacter)
        if not char or not char:IsValid() then return end

        local ok, charAddress = pcall(function() return char:get():GetAddress() end)
        if not ok then
            local nameObj = char:GetPropertyValue("Name")
            charAddress = nameObj and tostring(nameObj) or "unknown"
        end

        if not ref or not IsConditionMet(IsValid) then return end

        Set(ref, F.Evasion, cfg.LW_EVASION)
        Set(ref, F.Initiative, cfg.LW_INITIATIVE)
        Set(ref, F.ArmorPenalty, cfg.LW_ARMOR_PENALTY)

        AppliedModifiers[charAddress] = AppliedModifiers[charAddress] or {}
        if not AppliedModifiers[charAddress].LoneWolf then
            Log("[INFO] LoneWolf: stats injected")
            AppliedModifiers[charAddress].LoneWolf = true
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
        local ref = GetEffects(Effects)
        if not ref or not IsConditionMet(IsValid) then return end

        local char = GetChar(OwnerCharacter)
        if not char then return end

        local ok, charAddress = pcall(function() return char:get():GetAddress() end)
        if not ok then
            local nameObj = char:GetPropertyValue("Name")
            charAddress = nameObj and tostring(nameObj) or "unknown"
        end

        local skillLevel = 1
        for _, name in ipairs({ "MeleeSkill", "Melee", "MeleeLevel", "SkillMelee" }) do
            local sok, skillObj = pcall(function() return char:GetPropertyValue(name) end)
            if sok and skillObj then
                for _, lvlName in ipairs({ "Level", "SkillLevel", "CurrentLevel", "Rank" }) do
                    local lok, lv = pcall(function() return skillObj:GetPropertyValue(lvlName) end)
                    if lok and lv and type(lv) == "number" and lv > 0 then
                        skillLevel = lv
                        break
                    end
                end
                if skillLevel > 1 then break end
            end
        end

        local bonus = skillLevel * cfg.WARRIOR_ARMOR_PER_LEVEL
        Set(ref, F.ArmorPenalty, bonus)

        AppliedModifiers[charAddress] = AppliedModifiers[charAddress] or {}
        if not AppliedModifiers[charAddress].Warrior then
            Log("[INFO] Warrior: ArmorHandling set to " .. bonus)
            AppliedModifiers[charAddress].Warrior = true
        end
    end
)

-- ------------------------------------------------------------------------
-- BERSERKER
-- Vanilla: +2 MeleeDMG at <=13 HP
-- Rebalanced: tiered above vanilla threshold
--   >50% HP  : nothing
--   <=50% HP : +1 min/max melee DMG
--   <=25% HP : +2 min/max melee DMG
--   <=13 HP  : vanilla fires, we stay out
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_Berserker.F_Berserker_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        -- it should not rely on IsConditionMet since it would nope out
        -- if not ref or not IsConditionMet(IsValid) then return end

        local char = GetChar(OwnerCharacter)
        if not char then return end

        local curHP, maxHP, ratio = GetHP(char)
        if not curHP or curHP == 0 then return end

        if curHP > 13 then
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
    end
)

-- ------------------------------------------------------------------------
-- BASHER (blunt weapons)
-- Vanilla: penetration bonus
-- Rebalanced: accuracy + knockdown + aimed THC per skill level
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_Basher.F_Basher_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        if not ref or not IsConditionMet(IsValid) then return end

        local skillLevel = 1
        local char = GetChar(OwnerCharacter)
        if char then
            for _, name in ipairs({ "MeleeSkill", "Melee", "MeleeLevel", "SkillMelee" }) do
                local ok, sv = pcall(function() return char:GetPropertyValue(name) end)
                if ok and sv and type(sv) == "number" and sv > 0 then
                    skillLevel = sv
                    break
                end
            end
        end

        Set(ref, F.PenetrationPct, 0)
        Set(ref, F.MeleeTHC, cfg.BASHER_THC)
        Set(ref, F.KnockdownChance, cfg.BASHER_KNOCKDOWN)
        Set(ref, F.AimedTHC, skillLevel * cfg.BASHER_AIMED_PER_LEVEL)
        Log("[INFO] Basher: applied (aimed=" .. skillLevel * cfg.BASHER_AIMED_PER_LEVEL .. ")")
    end
)

-- ------------------------------------------------------------------------
-- BUTCHER (bladed weapons)
-- Vanilla: aimed bonus
-- Rebalanced: accuracy + crit chance + penetration per skill level
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_Butcher.F_Butcher_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        if not ref or not IsConditionMet(IsValid) then return end

        local skillLevel = 1
        local char = GetChar(OwnerCharacter)
        if char then
            for _, name in ipairs({ "MeleeSkill", "Melee", "MeleeLevel", "SkillMelee" }) do
                local ok, sv = pcall(function() return char:GetPropertyValue(name) end)
                if ok and sv and type(sv) == "number" and sv > 0 then
                    skillLevel = sv
                    break
                end
            end
        end

        Set(ref, F.AimedTHC, 0)
        Set(ref, F.MeleeTHC, cfg.BUTCHER_THC)
        Set(ref, F.CSC, cfg.BUTCHER_CSC)
        Set(ref, F.PenetrationPct, skillLevel * cfg.BUTCHER_PEN_PER_LEVEL)
        Log("[INFO] Butcher: applied (pen=" .. skillLevel * cfg.BUTCHER_PEN_PER_LEVEL .. ")")
    end
)

-- ------------------------------------------------------------------------
-- JUGGERNAUT (Heroic)
-- Vanilla: +1 DR always, +3 more at <=13 HP
-- Rebalanced: tiered above vanilla threshold
--   >50% HP  : +1 DR
--   <=50% HP : +2 DR
--   <=25% HP : +3 DR
--   <=13 HP  : vanilla handles +4, we stay out
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_H_Juggernaut.F_H_Juggernaut_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        -- it should not rely on IsConditionMet since it would nope out
        -- if not ref or not IsConditionMet(IsValid) then return end

        local char = GetChar(OwnerCharacter)
        if not char then return end

        local curHP, maxHP, ratio = GetHP(char)
        if not curHP or curHP == 0 then return end

        if curHP > 13 then
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
    end
)

-- ------------------------------------------------------------------------
-- GLADIATOR
-- Addition: flat +GLADIATOR_MIN/MAX min/max melee damage
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_Gladiator.F_Gladiator_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        if not ref or not IsConditionMet(IsValid) then return end

        Set(ref, F.MeleeMinDMG, cfg.GLADIATOR_MIN)
        Set(ref, F.MeleeMaxDMG, cfg.GLADIATOR_MAX)
        Log("[INFO] Gladiator: +" .. cfg.GLADIATOR_MIN .. " min +" .. cfg.GLADIATOR_MAX .. " max dmg")
    end
)

-- ------------------------------------------------------------------------
-- HEAVY HITTER
-- Addition: +HH_CRIT_PER_STEP% Crit Chance per HH_PER Perception
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_HeavyHitter.F_HeavyHitter_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        if not ref or not IsConditionMet(IsValid) then return end

        local char = GetChar(OwnerCharacter)
        if not char then return end

        local perception = 0
        for _, name in ipairs({ "Perception", "Per", "PERCEPTION" }) do
            local ok, val = pcall(function() return char:GetPropertyValue(name) end)
            if ok and val and type(val) == "number" then
                perception = val
                break
            end
        end

        local critBonus = math.floor(perception / cfg.HH_PER) * cfg.HH_CRIT_PER_STEP
        if critBonus > 0 then
            Set(ref, F.CSC, critBonus)
            Log("[INFO] HeavyHitter: +" .. critBonus .. "% CSC from " .. perception .. " Perception")
        end
    end
)

-- ------------------------------------------------------------------------
-- Educated
-- Addition: EDUCATED_INT_MIN, limiting feat availability
-- ------------------------------------------------------------------------
HookFeat("/Game/Gameplay/Feats/F_Educated.F_Educated_C",
    "Is Available To Learn",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        if not ref then return end

        local char = GetChar(OwnerCharacter)
        if not char then return end

        local meetsReq = true
        if char then
            for _, name in ipairs({ "Intelligence", "Int", "INTEL" }) do
                local iOk, iv = pcall(function() return char:GetPropertyValue(name) end)
                if iOk and iv and type(iv) == "number" then
                    meetsReq = iv >= cfg.EDUCATED_INT_MIN
                    break
                end
            end
        end
        if meetsReq then
            Log("[INFO] Educated: Intelligence >=" .. cfg.EDUCATED_INT_MIN .. ", applied")
            return true
        else
            Log("[INFO] Educated: Intelligence <" .. cfg.EDUCATED_INT_MIN .. ", suppressed")
            return false
        end
    end
)

-- ------------------------------------------------------------------------
-- FEATBASE HOOK
-- Handles feats that use FeatBase's Get Conditional Effects without
-- overriding it: Educated, Mastermind, Gifted, FastRunner, ToughBastard
-- ------------------------------------------------------------------------
NotifyOnNewObject("/Game/Gameplay/Feats/BaseTypes/FeatBase.FeatBase_C",
    function()
        if FeatBaseHooked then return end
        FeatBaseHooked = true

        local ok, err = pcall(function()
            RegisterHook(
                "/Game/Gameplay/Feats/BaseTypes/FeatBase.FeatBase_C:Get Conditional Effects",
                function(self, OwnerCharacter, Effects, IsValid)
                    local className = GetFeatClassName(self)

                    -- EDUCATED
                    if className:find("F_Educated_C") then
                        local ref = GetEffects(Effects)
                        if not ref then return end
                        local meetsReq = true
                        local char = GetChar(OwnerCharacter)
                        if char then
                            for _, name in ipairs({ "Intelligence", "Int", "INTEL" }) do
                                local iOk, iv = pcall(function() return char:GetPropertyValue(name) end)
                                if iOk and iv and type(iv) == "number" then
                                    meetsReq = iv >= cfg.EDUCATED_INT_MIN
                                    break
                                end
                            end
                        end
                        if meetsReq then
                            Set(ref, F.SkillXPGain, cfg.EDUCATED_SXP_BONUS)
                            Log("[INFO] Educated: +" .. cfg.EDUCATED_SXP_BONUS .. "% SkillXP applied")
                        else
                            Log("[INFO] Educated: Int<" .. cfg.EDUCATED_INT_MIN .. ", suppressed")
                        end

                        -- MASTERMIND
                    elseif className:find("F_H_Mastermind_C") then
                        local ref = GetEffects(Effects)
                        if not ref then return end
                        Set(ref, F.SkillXPGain, cfg.MASTERMIND_SXP_BONUS)
                        Log("[INFO] Mastermind: +" .. cfg.MASTERMIND_SXP_BONUS .. "% SkillXP applied")

                        -- GIFTED
                    elseif className:find("F_Gifted_C") then
                        local ref = GetEffects(Effects)
                        if not ref then return end
                        Set(ref, F.SkillXPGain, cfg.GIFTED_SKILL_SXP)
                        Log("[INFO] Gifted: +" .. cfg.GIFTED_SKILL_SXP .. "% SkillXP applied")

                        local char = GetChar(OwnerCharacter)
                        if char then
                            for _, propName in ipairs({ "UnspentStatPoints" }) do
                                local pOk, val = pcall(function() return char:GetPropertyValue(propName) end)
                                if pOk and type(val) == "number" then
                                    local sOk = pcall(function() char:SetPropertyValue(propName, val + 1) end)
                                    if sOk then
                                        Log("[INFO] Gifted: +1 stat point (now " .. (val + 1) .. ")")
                                        return
                                    end
                                end
                            end
                        end
                        Log("[WARN] Gifted: could not find stat point property")

                        -- FAST RUNNER
                    elseif className:find("F_H_FastRunner_C") then
                        local ref = GetEffects(Effects)
                        if not ref then return end
                        Set(ref, F.Evasion, cfg.FR_EVASION)
                        Log("[INFO] FastRunner: +" .. cfg.FR_EVASION .. " Evasion applied")

                        -- TOUGH BASTARD
                    elseif className:find("F_ToughBastard_C") then
                        local ref = GetEffects(Effects)
                        if not ref then return end
                        local char = GetChar(OwnerCharacter)
                        local meetsReq = true
                        if char then
                            for _, name in ipairs({ "Constitution", "Con", "CON" }) do
                                local cOk, cv = pcall(function() return char:GetPropertyValue(name) end)
                                if cOk and cv and type(cv) == "number" then
                                    meetsReq = cv >= cfg.TB_CON
                                    break
                                end
                            end
                        end
                        if not meetsReq then
                            Set(ref, F.MaxHP, 0)
                            Set(ref, F.NaturalDR, 0)
                            Log("[INFO] ToughBastard: CON<" .. cfg.TB_CON .. ", suppressed")
                        else
                            Log("[INFO] ToughBastard: active")
                        end
                    end
                end
            )
        end)
        if ok then
            Log("[INFO] Hook registered: FeatBase")
        else
            Log("[WARN] Hook FAILED: FeatBase | " .. tostring(err))
        end
    end
)

-- ------------------------------------------------------------------------
-- REGENBASE HOOK (Healing Factor)
-- Vanilla: flat HP regen per turn
-- Rebalanced: HPRegen = floor(char level / HF_REGEN_PER_LEVELS)
-- ------------------------------------------------------------------------
NotifyOnNewObject("/Game/Gameplay/Feats/BaseTypes/F_RegenBase.F_RegenBase_C",
    function()
        if RegenBaseHooked then return end
        RegenBaseHooked = true

        local ok, err = pcall(function()
            RegisterHook(
                "/Game/Gameplay/Feats/BaseTypes/F_RegenBase.F_RegenBase_C:Get Conditional Effects",
                function(self, OwnerCharacter, Effects, IsValid)
                    local className = GetFeatClassName(self)
                    if not className:find("F_H_HealingFactor_C") then return end

                    local ref = GetEffects(Effects)
                    if not ref then return end

                    local char = GetChar(OwnerCharacter)
                    if not char then return end

                    local level = GetCharLevel(char)
                    local bonus = math.floor(level / cfg.HF_REGEN_PER_LEVELS)
                    Set(ref, F.HPRegen, bonus)
                    Log("[INFO] HealingFactor: level " .. level .. " -> HPRegen=" .. bonus)
                end
            )
        end)
        if ok then
            Log("[INFO] Hook registered: RegenBase")
        else
            Log("[WARN] Hook FAILED: RegenBase | " .. tostring(err))
        end
    end
)

-- ------------------------------------------------------------------------
-- FAST RUNNER
-- Vanilla: "+6 AP to movement,Initiative +24, disables enemy Reaction, Evasion skill gain +100%"
-- Rebalanced: +FR_EVASION Evasion
-- ------------------------------------------------------------------------
-- NotifyOnNewObject("/Game/Gameplay/Feats/F_H_FastRunner.F_H_FastRunner_C", function()
--     if FastRunnerHooked then return end
--     FastRunnerHooked = true

--     local ok, err = pcall(function()
--         RegisterHook(
--             "/Game/Gameplay/Feats/F_H_FastRunner.F_H_FastRunner_C:On Feat Added",
--             function(self, OwnerCharacter, Effects, IsValid)
--                 local className = GetFeatClassName(self)
--                 if not className:find("F_H_FastRunner_C") then return end

--                 local ref = GetEffects(Effects)
--                 if not ref then return end

--                 local char = GetChar(OwnerCharacter)
--                 if not char then return end

--                 Set(ref, F.Evasion, cfg.FR_EVASION)
--                 Log("[INFO] FastRunner: Evasion +" .. cfg.FR_EVASION .. ".")
--             end
--         )
--     end)
--     if ok then
--         Log("[INFO] Hook registered: FastRunner OnFeatAdded")
--     else
--         Log("[WARN] Hook FAILED: FastRunner OnFeatAdded | " .. tostring(err))
--     end
-- end)

-- ------------------------------------------------------------------------
-- GIFTED — OnFeatAdded: grant +1 additional stat point at feat acquisition
-- ------------------------------------------------------------------------
-- NotifyOnNewObject("/Game/Gameplay/Feats/F_Gifted.F_Gifted_C", function()
--     if GiftedAddedHooked then return end
--     GiftedAddedHooked = true

--     local ok, err = pcall(function()
--         RegisterHook("/Game/Gameplay/Feats/F_Gifted.F_Gifted_C:On Feat Added",
--             function(self, OwnerCharacter)
--                 local char = GetChar(OwnerCharacter)
--                 if not char then return end
--                 for _, propName in ipairs({ "UnspentStatPoints" }) do
--                     local pOk, val = pcall(function() return char:GetPropertyValue(propName) end)
--                     if pOk and type(val) == "number" then
--                         local sOk = pcall(function() char:SetPropertyValue(propName, val + 1) end)
--                         if sOk then
--                             Log("[INFO] Gifted: +1 stat point (now " .. (val + 1) .. ")")
--                             return
--                         end
--                     end
--                 end
--                 Log("[WARN] Gifted: could not find stat point property")
--             end
--         )
--     end)
--     if ok then
--         Log("[INFO] Hook registered: Gifted OnFeatAdded")
--     else
--         Log("[WARN] Hook FAILED: Gifted OnFeatAdded | " .. tostring(err))
--     end
-- end)

-- ------------------------------------------------------------------------
-- Description patching via StaticFindObject on CDOs
-- Derives CDO path from class path:
--   /Game/Gameplay/Feats/F_LoneWolf.F_LoneWolf_C
--   -> /Game/Gameplay/Feats/F_LoneWolf.Default__F_LoneWolf_C
-- Called from InitGameState hook; returns false when Feats DB is empty
-- (menu world load) so the hook silently waits for the game world load.
-- ------------------------------------------------------------------------
local function PatchFeatDescriptions(descriptions)
    Log("[INFO] Patching feat descriptions...")

    local updated = 0
    local failed  = 0

    for classPath, descText in pairs(descriptions) do
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
-- Main: load config + descriptions, patch CDOs
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
-- Trigger: fires after game state initializes.
-- First call(s) may have empty Feats DB (menu world); those return false
-- cleanly. The call after game world load succeeds.
-- Effect hooks (HookFeat / NotifyOnNewObject) are registered at startup
-- and fire independently whenever feat objects are constructed in-game.
-- ------------------------------------------------------------------------
RegisterInitGameStatePostHook(function()
    Log("[INFO] InitGameState fired — applying feat descriptions")
    ExecuteInGameThread(function()
        local ok = RunMod()
        if not ok then
            Log("[INFO] Descriptions not applied this cycle (game world not loaded yet)")
        end
    end)
end)

-- ------------------------------------------------------------------------
-- F8: manual re-apply (force description reload + re-patch)
-- ------------------------------------------------------------------------
RegisterKeyBind(Key.F8, function()
    descriptions = nil
    ExecuteInGameThread(function()
        local ok = RunMod()
        print("[FeatRebalance] F8 re-apply: " .. (ok and "OK" or "FAILED — check log"))
    end)
end)

Log("[INFO] Mod loaded. Effect hooks registered. Waiting for InitGameState for descriptions.")
