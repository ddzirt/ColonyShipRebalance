print("\n[Perks Rebalance] Starting...\n")

-- ============================================================
-- SCRIPT PATH
-- ============================================================
local function get_script_path()
    local path = debug.getinfo(1, "S").source:sub(2)
    return path:match("(.*[/\\])") or "./"
end
local SCRIPT_PATH = get_script_path()

-- ============================================================
-- CONFIG LOADER
-- Reads config.ini next to main.lua
-- Format: KEY=VALUE, one per line, # for comments
-- ============================================================
local function LoadConfig()
    local cfg = {}
    local f = io.open(SCRIPT_PATH .. "config.ini", "r")
    if not f then return cfg end
    for line in f:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") then
            local k, v = line:match("^([%w_]+)%s*=%s*(.+)$")
            if k and v then
                if v == "true" then
                    cfg[k] = true
                elseif v == "false" then
                    cfg[k] = false
                elseif tonumber(v) then
                    cfg[k] = tonumber(v)
                else
                    cfg[k] = v
                end
            end
        end
    end
    f:close()
    return cfg
end

local C = LoadConfig()
local function cfg(key, default)
    return C[key] ~= nil and C[key] or default
end

-- ============================================================
-- PERSISTENT STATE
-- Survives across game sessions via state.json next to main.lua
-- Use for tracking things vanilla saves don't expose to Lua
-- ============================================================
local STATE_PATH = SCRIPT_PATH .. "state.json"

local function LoadState()
    local f = io.open(STATE_PATH, "r")
    if not f then return {} end
    local content = f:read("*a")
    f:close()
    -- Minimal JSON parser for flat key=value number/bool/string
    local state = {}
    for k, v in content:gmatch('"([^"]+)"%s*:%s*([^,}]+)') do
        v = v:match("^%s*(.-)%s*$")
        if v == "true" then
            state[k] = true
        elseif v == "false" then
            state[k] = false
        elseif tonumber(v) then
            state[k] = tonumber(v)
        else
            state[k] = v:match('^"(.*)"$') or v
        end
    end
    return state
end

local function SaveState(state)
    local f = io.open(STATE_PATH, "w")
    if not f then return end
    f:write("{\n")
    local entries = {}
    for k, v in pairs(state) do
        if type(v) == "string" then
            table.insert(entries, '  "' .. k .. '": "' .. v .. '"')
        else
            table.insert(entries, '  "' .. k .. '": ' .. tostring(v))
        end
    end
    f:write(table.concat(entries, ",\n"))
    f:write("\n}\n")
    f:close()
end

local STATE = LoadState()

-- ============================================================
-- LOGGING
-- ============================================================
local logPath = SCRIPT_PATH .. "RebalanceLog.txt"
io.open(logPath, "w"):write("[Perks Rebalance] Session start.\n"):close()

local function Log(msg)
    local f = io.open(logPath, "a")
    if f then
        f:write(msg .. "\n")
        f:close()
    end
    print("[Perks Rebalance] " .. msg)
end

-- ============================================================
-- FIELD HELPERS
-- ============================================================
local function Set(ref, field, value)
    local ok, err = pcall(function() ref[field] = value end)
    if not ok then Log("SET FAILED [" .. field .. "]: " .. tostring(err)) end
end

local function Get(ref, field)
    local ok, val = pcall(function() return ref[field] end)
    return ok and val or nil
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
    local hpOk, hp     = pcall(function() return char:GetPropertyValue("HP") end)
    local mhpOk, maxHp = pcall(function() return char:GetPropertyValue("MaxHP") end)
    if hpOk and hp and mhpOk and maxHp and maxHp > 0 then
        return hp, maxHp, hp / maxHp
    end
    return nil, nil, nil
end

-- ============================================================
-- FIELD CONSTANTS  (CsgCharEffects — full mangled names)
-- ============================================================
local F = {
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

-- ============================================================
-- HOOK HELPERS
-- ============================================================
local function HookFeat(classPath, fnName, callback)
    local registered = false
    NotifyOnNewObject(classPath, function()
        if registered then return end
        registered = true
        local ok, err = pcall(function()
            RegisterHook(classPath .. ":" .. fnName, callback)
        end)
        if ok then
            Log("Hook registered: " .. classPath)
        else
            Log("Hook FAILED: " .. classPath .. " | " .. tostring(err))
        end
    end)
end

-- Single shared hook for all feats that inherit without overriding
local FeatBaseHooked  = false
local RegenBaseHooked = false

local function GetFeatClassName(self)
    local ok, cls = pcall(function() return self:get():GetClass() end)
    if not ok or not cls then return "" end
    local nok, name = pcall(function() return cls:GetFullName() end)
    return nok and (name or "") or ""
end

-- ============================================================
-- LONE WOLF
-- Vanilla (solo): +12 Evasion, +16 Initiative
-- Rebalanced:     +16 Evasion, +20 Initiative
--                 +4 ArmorPenalty (reduces heavy armor AP cost)
-- Config: LW_EVASION, LW_INITIATIVE, LW_ARMOR_PENALTY
-- ============================================================
HookFeat("/Game/Gameplay/Feats/F_LoneWolf.F_LoneWolf_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        if not ref or not IsConditionMet(IsValid) then return end

        Set(ref, F.Evasion, cfg("LW_EVASION", 16))
        Set(ref, F.Initiative, cfg("LW_INITIATIVE", 20))
        Set(ref, F.ArmorPenalty, cfg("LW_ARMOR_PENALTY", 4))
        Log("LoneWolf: applied")
    end
)

-- ============================================================
-- WARRIOR
-- Vanilla: THC and CSC bonuses per melee skill level
-- Addition: +ArmorPenalty per skill level (armor becomes usable
--           without needing STR 10 Juggernaut)
-- Config: WARRIOR_ARMOR_PER_LEVEL
-- ============================================================
HookFeat("/Game/Gameplay/Feats/F_Warrior.F_Warrior_C",
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

        local bonus = skillLevel * cfg("WARRIOR_ARMOR_PER_LEVEL", 1)
        -- Set directly, not additive, to avoid stacking across recalculations
        Set(ref, F.ArmorPenalty, bonus)
        Log("Warrior: ArmorPenalty set to " .. bonus)
    end
)

-- ============================================================
-- BERSERKER
-- Vanilla: +2 MeleeDMG at <=13 HP
-- Rebalanced: same cap, distributed into tiers above threshold
--   >50% HP  : nothing (vanilla gives nothing)
--   <=50% HP : +1 min/max melee DMG
--   <=25% HP : +2 min/max melee DMG
--   <=13 HP  : vanilla fires its own +2, we do nothing
-- Config: BERSERK_MID_HP_PCT, BERSERK_LOW_HP_PCT
-- ============================================================
HookFeat("/Game/Gameplay/Feats/F_Berserker.F_Berserker_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        if not ref or not IsConditionMet(IsValid) then return end

        local char = GetChar(OwnerCharacter)
        if not char then return end

        local hp, maxHp, pct = GetHP(char)
        if not hp then return end

        -- Only act above the vanilla threshold; below it vanilla handles
        if hp > 13 then
            if pct <= cfg("BERSERK_LOW_HP_PCT", 0.25) then
                Set(ref, F.MeleeMinDMG, 2)
                Set(ref, F.MeleeMaxDMG, 2)
                Log("Berserker: tier 2 (" .. math.floor(pct * 100) .. "%)")
            elseif pct <= cfg("BERSERK_MID_HP_PCT", 0.50) then
                Set(ref, F.MeleeMinDMG, 1)
                Set(ref, F.MeleeMaxDMG, 1)
                Log("Berserker: tier 1 (" .. math.floor(pct * 100) .. "%)")
            end
        end
    end
)

-- ============================================================
-- BASHER (blunt weapons)
-- Vanilla: aimed attack bonus
-- Rebalanced: blunt accuracy + knockdown + aimed THC per skill level
-- Config: BASHER_THC, BASHER_KNOCKDOWN, BASHER_AIMED_PER_LEVEL
-- ============================================================
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

        Set(ref, F.PenetrationPct, 0) -- remove any vanilla penetration
        Set(ref, F.MeleeTHC, cfg("BASHER_THC", 8))
        Set(ref, F.KnockdownChance, cfg("BASHER_KNOCKDOWN", 20))
        Set(ref, F.AimedTHC, skillLevel * cfg("BASHER_AIMED_PER_LEVEL", 2))
        Log("Basher: applied (aimed=" .. skillLevel * cfg("BASHER_AIMED_PER_LEVEL", 2) .. ")")
    end
)

-- ============================================================
-- BUTCHER (bladed weapons)
-- Vanilla: penetration bonus
-- Rebalanced: bladed accuracy + crit chance + penetration per skill level
-- Config: BUTCHER_THC, BUTCHER_CSC, BUTCHER_PEN_PER_LEVEL
-- ============================================================
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

        Set(ref, F.AimedTHC, 0) -- remove any vanilla aimed bonus
        Set(ref, F.MeleeTHC, cfg("BUTCHER_THC", 8))
        Set(ref, F.CSC, cfg("BUTCHER_CSC", 20))
        Set(ref, F.PenetrationPct, skillLevel * cfg("BUTCHER_PEN_PER_LEVEL", 2))
        Log("Butcher: applied (pen=" .. skillLevel * cfg("BUTCHER_PEN_PER_LEVEL", 2) .. ")")
    end
)

-- ============================================================
-- JUGGERNAUT (Heroic)
-- Vanilla: +1 NaturalDR always, +3 more at <=13 HP (total 4)
-- Rebalanced: same total cap, split into tiers above threshold
--   >50% HP  : +1 DR (vanilla, we set explicitly)
--   <=50% HP : +2 DR (we set)
--   <=25% HP : +3 DR (we set)
--   <=13 HP  : +4 DR (vanilla handles, we don't touch)
-- Config: JUGG_MID_HP_PCT, JUGG_LOW_HP_PCT
-- ============================================================
HookFeat("/Game/Gameplay/Feats/F_H_Juggernaut.F_H_Juggernaut_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        if not ref or not IsConditionMet(IsValid) then return end

        local char = GetChar(OwnerCharacter)
        if not char then return end

        local hp, maxHp, pct = GetHP(char)

        -- If we can't read HP, let vanilla handle everything
        if not hp then return end

        -- Only intercept above vanilla's threshold
        if hp > 13 then
            if pct <= cfg("JUGG_LOW_HP_PCT", 0.25) then
                Set(ref, F.NaturalDR, 3)
                Log("Juggernaut: tier 3 (" .. math.floor(pct * 100) .. "%)")
            elseif pct <= cfg("JUGG_MID_HP_PCT", 0.50) then
                Set(ref, F.NaturalDR, 2)
                Log("Juggernaut: tier 2 (" .. math.floor(pct * 100) .. "%)")
            else
                Set(ref, F.NaturalDR, 1)
            end
        end
        -- hp <= 13: vanilla fires its +4, we stay out of the way
    end
)

-- ============================================================
-- FAST RUNNER
-- Vanilla: +4 Initiative when move on turn
-- Addition: +6 Evasion (same condition)
-- ============================================================
HookFeat("/Game/Gameplay/Feats/F_FastRunner.F_FastRunner_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        if not ref or not IsConditionMet(IsValid) then return end

        Set(ref, F.Evasion, 6)
        Log("FastRunner: +6 Evasion applied")
    end
)

-- ============================================================
-- GLADIATOR
-- Addition: flat +1 min/max melee damage
-- ============================================================
HookFeat("/Game/Gameplay/Feats/F_Gladiator.F_Gladiator_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        if not ref or not IsConditionMet(IsValid) then return end

        Set(ref, F.MeleeMinDMG, 1)
        Set(ref, F.MeleeMaxDMG, 1)
        Log("Gladiator: +1 melee damage applied")
    end
)

-- ============================================================
-- HEAVY HITTER
-- Addition: +1% Crit Chance per 3 Perception
-- ============================================================
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

        local critBonus = math.floor(perception / 3)
        if critBonus > 0 then
            Set(ref, F.CSC, critBonus)
            Log("HeavyHitter: +" .. critBonus .. "% CSC from " .. perception .. " Perception")
        end
    end
)

-- ============================================================
-- TOUGH BASTARD
-- Requirement: Constitution >= 6, otherwise all benefits suppressed
-- ============================================================
HookFeat("/Game/Gameplay/Feats/F_ToughBastard.F_ToughBastard_C",
    "Get Conditional Effects",
    function(self, OwnerCharacter, Effects, IsValid)
        local ref = GetEffects(Effects)
        if not ref or not IsConditionMet(IsValid) then return end

        local char = GetChar(OwnerCharacter)
        if not char then return end

        local con = 0
        for _, name in ipairs({ "Constitution", "Con", "CONSTITUTION" }) do
            local ok, val = pcall(function() return char:GetPropertyValue(name) end)
            if ok and val and type(val) == "number" then
                con = val
                break
            end
        end

        if con < 6 then
            -- Zero out the feat's bonuses (common fields for Tough Bastard)
            Set(ref, F.NaturalDR, 0)
            Set(ref, F.MaxHP, 0)
            Log("ToughBastard: CON < 6, bonuses suppressed")
        else
            Log("ToughBastard: CON >= 6, normal effects active")
        end
    end
)

-- ============================================================
-- FEATBASE HOOK
-- Handles all feats that inherit Get Conditional Effects
-- without overriding it: Educated, Mastermind, Gifted
-- ============================================================
NotifyOnNewObject("/Game/Gameplay/Feats/BaseTypes/FeatBase.FeatBase_C",
    function()
        if FeatBaseHooked then return end
        FeatBaseHooked = true

        local ok, err = pcall(function()
            RegisterHook("/Game/Gameplay/Feats/BaseTypes/FeatBase.FeatBase_C:Get Conditional Effects",
                function(self, OwnerCharacter, Effects, IsValid)
                    local className = GetFeatClassName(self)

                    -- EDUCATED
                    -- Vanilla: retroactive skill LP bonus on feat add (one-time)
                    -- Addition: persistent +5% SkillXPGain each combat recalc
                    -- Soft Int>=5 gate: bonus zeroed below threshold
                    -- Config: EDUCATED_XP_BONUS
                    if className:find("F_Educated_C") then
                        local ref = GetEffects(Effects)
                        if not ref then return end

                        local meetsReq = true
                        local char = GetChar(OwnerCharacter)
                        if char then
                            for _, name in ipairs({ "Intelligence", "Int", "INTEL" }) do
                                local iOk, iv = pcall(function() return char:GetPropertyValue(name) end)
                                if iOk and iv and type(iv) == "number" then
                                    meetsReq = iv >= 5
                                    break
                                end
                            end
                        end

                        if meetsReq then
                            Set(ref, F.SkillXPGain, cfg("EDUCATED_XP_BONUS", 5))
                            Log("Educated: +5% SkillXP applied")
                        else
                            Log("Educated: Int<5, suppressed")
                        end

                        -- MASTERMIND (Heroic)
                        -- Vanilla: bonus feat levels, Int-gated
                        -- Addition: +5% SkillXPGain to address skill point
                        --           deficit on Str-heavy solo builds
                        -- Config: MASTERMIND_XP_BONUS
                    elseif className:find("F_H_Mastermind_C") then
                        local ref = GetEffects(Effects)
                        if not ref then return end
                        Set(ref, F.SkillXPGain, cfg("MASTERMIND_XP_BONUS", 5))
                        Log("Mastermind: +5% SkillXP applied")

                        -- GIFTED (Heroic)
                        -- Vanilla: +4 stat points, +4 skill points at creation
                        -- Addition: +5% SkillXPGain (makes ongoing play
                        --           competitive with Mastermind/Educated)
                        -- Config: GIFTED_SKILL_XP
                    elseif className:find("F_Gifted_C") then
                        local ref = GetEffects(Effects)
                        if not ref then return end
                        Set(ref, F.SkillXPGain, cfg("GIFTED_SKILL_XP", 5))
                        Log("Gifted: +5% SkillXP applied")
                    end
                end
            )
        end)
        if ok then
            Log("Hook registered: FeatBase")
        else
            Log("Hook FAILED: FeatBase | " .. tostring(err))
        end
    end
)

-- ============================================================
-- REGENBASE HOOK (Healing Factor)
-- Vanilla: flat HP regen per turn (doesn't scale with level)
-- Rebalanced: HPRegen = floor(character level / HF_REGEN_PER_LEVELS)
-- Config: HF_REGEN_PER_LEVELS
-- ============================================================
NotifyOnNewObject("/Game/Gameplay/Feats/BaseTypes/F_RegenBase.F_RegenBase_C",
    function()
        if RegenBaseHooked then return end
        RegenBaseHooked = true

        local ok, err = pcall(function()
            RegisterHook("/Game/Gameplay/Feats/BaseTypes/F_RegenBase.F_RegenBase_C:Get Conditional Effects",
                function(self, OwnerCharacter, Effects, IsValid)
                    local className = GetFeatClassName(self)
                    if not className:find("F_H_HealingFactor_C") then return end

                    local ref = GetEffects(Effects)
                    if not ref then return end

                    local char = GetChar(OwnerCharacter)
                    if not char then return end

                    local level = GetCharLevel(char)
                    local perLevels = cfg("HF_REGEN_PER_LEVELS", 5)
                    local bonus = math.floor(level / perLevels)

                    -- Override vanilla completely; set absolute value
                    Set(ref, F.HPRegen, bonus)
                    Log("HealingFactor: level " .. level .. " -> HPRegen set to " .. bonus)
                end
            )
        end)
        if ok then
            Log("Hook registered: RegenBase")
        else
            Log("Hook FAILED: RegenBase | " .. tostring(err))
        end
    end
)

-- ============================================================
-- FEAT DESCRIPTION OVERRIDE
-- Replace in-game feat descriptions with custom text.
-- ============================================================
local function SetFeatDescription(featClass, newDescription)
    NotifyOnNewObject(featClass, function(feat)
        ExecuteInGameThread(function()
            local ok, desc = pcall(function()
                return feat.Description
            end)
            if ok and desc then
                pcall(function()
                    feat.Description = FText(newDescription)
                end)
                Log("Description updated: " .. featClass)
            else
                Log("Could not access Description for " .. featClass)
            end
        end)
    end)
end

-- LONE WOLF
SetFeatDescription("/Game/Gameplay/Feats/F_LoneWolf.F_LoneWolf_C",
    "SOLO: +" .. cfg("LW_EVASION", 16) .. " Evasion, +" .. cfg("LW_INITIATIVE", 20) ..
    " Initiative, +" .. cfg("LW_ARMOR_PENALTY", 4) .. " Armor Penalty reduction.")

-- WARRIOR
SetFeatDescription("/Game/Gameplay/Feats/F_Warrior.F_Warrior_C",
    "Grants melee accuracy bonuses and reduces armor penalty per Melee skill level." ..
    " (+" .. cfg("WARRIOR_ARMOR_PER_LEVEL", 1) .. " Armor Penalty per skill level)")

-- BERSERKER
SetFeatDescription("/Game/Gameplay/Feats/F_Berserker.F_Berserker_C",
    "HP > 50%: no bonus. HP <= 50%: +1 Melee DMG. HP <= " ..
    math.floor(cfg("BERSERK_LOW_HP_PCT", 0.25) * 100) ..
    "%: +2 Melee DMG. At 13 HP or below, vanilla +2 applies.")

-- BASHER
SetFeatDescription("/Game/Gameplay/Feats/F_Basher.F_Basher_C",
    "Blunt accuracy +" .. cfg("BASHER_THC", 8) .. "%, knockdown +" .. cfg("BASHER_KNOCKDOWN", 20) ..
    "%, penetration +" .. cfg("BASHER_PEN_PER_LEVEL", 2) .. "% per melee skill level.")

-- BUTCHER
SetFeatDescription("/Game/Gameplay/Feats/F_Butcher.F_Butcher_C",
    "Bladed accuracy +" .. cfg("BUTCHER_THC", 8) .. "%, crit +" .. cfg("BUTCHER_CSC", 20) ..
    "%, aimed +" .. cfg("BUTCHER_AIMED_PER_LEVEL", 1) .. " per melee skill level.")

-- JUGGERNAUT
SetFeatDescription("/Game/Gameplay/Feats/F_H_Juggernaut.F_H_Juggernaut_C",
    "HP > " .. math.floor(cfg("JUGG_MID_HP_PCT", 0.50) * 100) .. "%: +1 DR. HP <= " ..
    math.floor(cfg("JUGG_MID_HP_PCT", 0.50) * 100) .. "%: +2 DR. HP <= " ..
    math.floor(cfg("JUGG_LOW_HP_PCT", 0.25) * 100) .. "%: +3 DR. At 13 HP or below, vanilla +4 applies.")

-- EDUCATED
SetFeatDescription("/Game/Gameplay/Feats/F_Educated.F_Educated_C",
    "INT >= 5: +" .. cfg("EDUCATED_XP_BONUS", 5) .. "% Skill XP gain. Also retroactive skill points.")

-- MASTERMIND
SetFeatDescription("/Game/Gameplay/Feats/F_H_Mastermind.F_H_Mastermind_C",
    "Bonus feat levels (INT-gated) plus +" .. cfg("MASTERMIND_SXP_BONUS", 5) .. "% Skill XP gain.")

-- GIFTED
SetFeatDescription("/Game/Gameplay/Feats/F_Gifted.F_Gifted_C",
    "+4 stat points, +4 skill points, plus +" .. cfg("GIFTED_SKILL_SXP", 5) .. "% Skill XP gain.")

-- HEALING FACTOR
SetFeatDescription("/Game/Gameplay/Feats/F_H_HealingFactor.F_H_HealingFactor_C",
    "HP regen per turn = floor(character level / " .. cfg("HF_REGEN_PER_LEVELS", 5) .. ").")

-- FAST RUNNER
SetFeatDescription("/Game/Gameplay/Feats/F_FastRunner.F_FastRunner_C",
    "+6 AP to movement, Initiative +24, disables enemy Reaction, Evasion skill gain +100%. Additionally grants +6 Evasion.")

-- GLADIATOR
SetFeatDescription("/Game/Gameplay/Feats/F_Gladiator.F_Gladiator_C",
    "The gladiator deals a little more damage. (+1 min/max melee damage)")

-- HEAVY HITTER
SetFeatDescription("/Game/Gameplay/Feats/F_HeavyHitter.F_HeavyHitter_C",
    "+1% Crit Chance for every 3 Perception.")

-- TOUGH BASTARD
SetFeatDescription("/Game/Gameplay/Feats/F_ToughBastard.F_ToughBastard_C",
    "Requires CON >= 6. If requirement not met, all bonuses are suppressed.")


-- -- ============================================================
-- -- MOD DESCRIPTION (description.txt)
-- -- ============================================================
-- local function CreateModDescription()
--     local f = io.open(SCRIPT_PATH .. "description.txt", "w")
--     if not f then return end
--     f:write([[
-- FeatRebalance Mod

-- Rebalances all major feats for solo play viability. Includes:
-- - Weapon-specific feats (Basher, Butcher) reworked for blunt / blade identity
-- - Warrior armor penalty reduction per melee skill level
-- - Tiered HP-based feats (Berserker, Juggernaut)
-- - Educated / Mastermind / Gifted: additional SkillXP gain
-- - Healing Factor: scaling HP regen based on character level
-- - Fast Runner: extra Evasion when moving
-- - Gladiator: +1 melee damage
-- - Heavy Hitter: +1% Crit Chance per 3 Perception
-- - Tough Bastard: CON 6 gate

-- Configurable via config.ini.
-- ]])
--     f:close()
-- end

CreateModDescription()

-- ============================================================
-- CONSOLE COMMANDS FOR TESTING
-- ============================================================
RegisterConsoleCommand("AddFeatPoints", function(args)
    local amount = tonumber(args[1]) or 5
    local pc = GetPlayerController()
    local char = pc and pc:GetPawn()
    if char then
        local current = char:GetPropertyValue("FeatPoints") or 0
        char:SetPropertyValue("FeatPoints", current + amount)
        Log("Added " .. amount .. " feat points. Total now: " .. (current + amount))
    else
        Log("AddFeatPoints: Player character not found")
    end
end)

RegisterConsoleCommand("RemoveAllFeats", function()
    local pc = GetPlayerController()
    local char = pc and pc:GetPawn()
    if not char then
        Log("RemoveAllFeats: Player character not found")
        return
    end

    local featComp = char:GetComponentByClass(UE.UClass.Load("/Script/ColonyShip.FeatComponent"))
    if not featComp then
        Log("RemoveAllFeats: No FeatComponent found.")
        return
    end

    local featCount = featComp:GetFeatCount() -- method name may vary
    Log("Removing " .. featCount .. " feats and refunding points.")
    featComp:ClearAllFeats()
    char:SetPropertyValue("FeatPoints", (char:GetPropertyValue("FeatPoints") or 0) + featCount)
    Log("Feats cleared. Points refunded.")
end)

print("[Perks Rebalance] All hooks, descriptions, and commands registered.\n")
