-- descriptions-en.lua
-- Receives cfg function, returns flat table of classPath -> description string
return function(cfg)
    return {
        ["/Game/Gameplay/Feats/F_LoneWolf.F_LoneWolf_C"] =
            "AP +2, " ..
            "+" .. cfg("LW_EVASION", 16) .. " Evasion, +" ..
            cfg("LW_INITIATIVE", 20) .. " Initiative, +" ..
            cfg("LW_ARMOR_PENALTY", 4) .. " Armor Handling," ..
            " Critical Chance +6% when working alone, harder to bond with Companions.",

        ["/Game/Gameplay/Feats/F_Warrior.F_Warrior_C"] =
            "Melee: 25% skill gain (retroactive), Accuracy +6, Per Melee skill level: +1% Evasion, +1% Accuracy, +" ..
            cfg("WARRIOR_ARMOR_PER_LEVEL", 1) ..
            " Armor Handling.",

        ["/Game/Gameplay/Feats/F_Berserker.F_Berserker_C"] =
            "Melee: Attack cost -1, Aimed attacks are permanently disabled, when " ..
            "HP <= " .. math.floor(cfg("BERSERK_MID_HP_PCT", 0.50) * 100) .. "%: +1 Melee DMG. " ..
            "HP <= " .. math.floor(cfg("BERSERK_LOW_HP_PCT", 0.25) * 100) .. "%: +2 Melee DMG. " ..
            "HP <=13: +2 Melee DMG.",

        ["/Game/Gameplay/Feats/F_Basher.F_Basher_C"] =
            "Blunt: +" .. cfg("BASHER_THC", 8) .. "% accuracy, +" ..
            cfg("BASHER_KNOCKDOWN", 20) .. "% Knockdown, +" ..
            cfg("BASHER_AIMED_PER_LEVEL", 2) .. "% Aimed Accuracy per Melee skill level.",

        ["/Game/Gameplay/Feats/F_Butcher.F_Butcher_C"] =
            "Bladed: +" .. cfg("BUTCHER_THC", 8) .. "% accuracy, +" ..
            cfg("BUTCHER_CSC", 20) .. "% Carve Crit, +" ..
            cfg("BUTCHER_PEN_PER_LEVEL", 2) .. "% penetration per Melee skill level.",

        ["/Game/Gameplay/Feats/F_H_Juggernaut.F_H_Juggernaut_C"] =
            "Knockdowns become Stuns, melee damage +2, Armor skill gain +100%, " ..
            "HP > " .. math.floor(cfg("JUGG_MID_HP_PCT", 0.50) * 100) .. "%: +1 Natural DR. HP <= " ..
            math.floor(cfg("JUGG_MID_HP_PCT", 0.50) * 100) .. "%: +2 Natural DR. HP <= " ..
            math.floor(cfg("JUGG_LOW_HP_PCT", 0.25) * 100) .. "%: +3 Natural DR. HP <=13: +4 DR.",

        ["/Game/Gameplay/Feats/F_Educated.F_Educated_C"] =
            "+1 Tagged Skill, +25% Extra Experience (works retroactively). " ..
            "INT >= " .. cfg("EDUCATED_INT_MIN", 6) .. ": +" ..
            cfg("EDUCATED_SXP_BONUS", 5) .. "% Skill XP gain.",

        ["/Game/Gameplay/Feats/F_H_Mastermind.F_H_Mastermind_C"] =
            "+25% Experience Bonus, free Feats at level 2, 6 and 10. +" ..
            cfg("MASTERMIND_SXP_BONUS", 5) .. "% Skill XP gain.",

        ["/Game/Gameplay/Feats/F_Gifted.F_Gifted_C"] =
            "+4 stat points, +4 skill points, +" ..
            cfg("GIFTED_SKILL_SXP", 5) .. "% Skill XP gain.",

        ["/Game/Gameplay/Feats/F_H_HealingFactor.F_H_HealingFactor_C"] =
            "CON +2, Regeneration +3, Stat Healing +1, Max Implants +2, Biotech skill gain +100%, " ..
            "Regeneration increases per level = floor(level / " ..
            cfg("HF_REGEN_PER_LEVELS", 3) .. ").",

        ["/Game/Gameplay/Feats/F_H_FastRunner.F_H_FastRunner_C"] =
            "+6 AP to movement, +" ..
            cfg("FR_EVASION", 6) .. " Evasion, Initiative +24, disables enemy Reaction, Evasion skill gain +100%",

        ["/Game/Gameplay/Feats/F_Gladiator.F_Gladiator_C"] =
            "Melee Reaction +30, Graze +10, Graze damage +25%, " ..
            "+" .. cfg("GLADIATOR_MIN", 1) .. " min and +" ..
            cfg("GLADIATOR_MAX", 1) .. " max melee damage",

        ["/Game/Gameplay/Feats/F_HeavyHitter.F_HeavyHitter_C"] =
            "Melee Stagger +20, Penetration +10, Critical Damage +15% (0.15) " ..
            "+" .. cfg("HH_CRIT_PER_STEP", 1) .. "% Crit Chance per " ..
            cfg("HH_PER", 3) .. " Perception.",

        ["/Game/Gameplay/Feats/F_ToughBastard.F_ToughBastard_C"] =
            "HP +10, enemy's critical damage is halved. " ..
            "CON >= " .. cfg("TB_CON", 6) ..
            " required, if less does nothing.",
    }
end
