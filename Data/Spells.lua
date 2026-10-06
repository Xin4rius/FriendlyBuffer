-- Données des buffs par classe.
-- Chaque famille : rangs individuels {id, level, power}, versions groupe/supérieures
-- (power = rang individuel équivalent), durées en secondes, composant de la version groupe.
local _, ns = ...

-- Profils de cible : la classe seule (spé inconnue), puis, pour les classes hybrides, un profil
-- par arbre de talents (tab = index de l'arbre). Pour chaque profil : utilise la mana (esprit,
-- intelligence), reçoit des coups (épines), bénédictions par ordre de priorité.
local PROFILES = {
    { key = "WARRIOR",             class = "WARRIOR", thorns = true, blessings = { "might", "kings", "light" } },
    { key = "WARRIOR_ARMS",        class = "WARRIOR", tab = 1, thorns = true, blessings = { "might", "kings", "salvation", "light" } },
    { key = "WARRIOR_FURY",        class = "WARRIOR", tab = 2, thorns = true, blessings = { "might", "kings", "salvation", "light" } },
    { key = "WARRIOR_PROTECTION",  class = "WARRIOR", tab = 3, thorns = true, blessings = { "kings", "might", "light", "sanctuary" } },
    { key = "ROGUE",               class = "ROGUE", blessings = { "might", "kings", "salvation", "light" } },
    { key = "HUNTER",              class = "HUNTER", mana = true, blessings = { "wisdom", "kings", "salvation", "might" } },
    { key = "MAGE",                class = "MAGE", mana = true, blessings = { "wisdom", "kings", "salvation", "light" } },
    { key = "WARLOCK",             class = "WARLOCK", mana = true, blessings = { "wisdom", "kings", "salvation", "light" } },
    { key = "PRIEST",              class = "PRIEST", mana = true, blessings = { "wisdom", "kings", "salvation", "light" } },
    { key = "DRUID",               class = "DRUID", mana = true, blessings = { "wisdom", "kings", "salvation", "might" } },
    { key = "DRUID_BALANCE",       class = "DRUID", tab = 1, mana = true, blessings = { "wisdom", "kings", "salvation", "light" } },
    -- Farouche : peut tanker en ours, donc pas de salut par défaut.
    { key = "DRUID_FERAL",         class = "DRUID", tab = 2, thorns = true, blessings = { "might", "kings", "light" } },
    { key = "DRUID_RESTORATION",   class = "DRUID", tab = 3, mana = true, blessings = { "wisdom", "kings", "salvation", "light" } },
    { key = "SHAMAN",              class = "SHAMAN", mana = true, blessings = { "wisdom", "kings", "salvation", "might" } },
    { key = "SHAMAN_ELEMENTAL",    class = "SHAMAN", tab = 1, mana = true, blessings = { "wisdom", "kings", "salvation", "light" } },
    { key = "SHAMAN_ENHANCEMENT",  class = "SHAMAN", tab = 2, mana = true, blessings = { "might", "kings", "salvation", "wisdom" } },
    { key = "SHAMAN_RESTORATION",  class = "SHAMAN", tab = 3, mana = true, blessings = { "wisdom", "kings", "salvation", "light" } },
    { key = "PALADIN",             class = "PALADIN", mana = true, blessings = { "wisdom", "kings", "might", "light" } },
    { key = "PALADIN_HOLY",        class = "PALADIN", tab = 1, mana = true, blessings = { "wisdom", "kings", "salvation", "light" } },
    { key = "PALADIN_PROTECTION",  class = "PALADIN", tab = 2, mana = true, thorns = true, blessings = { "kings", "wisdom", "light", "sanctuary" } },
    { key = "PALADIN_RETRIBUTION", class = "PALADIN", tab = 3, mana = true, blessings = { "might", "kings", "salvation", "wisdom" } },
}

ns.TARGET_PROFILES = {}       -- clés dans l'ordre d'affichage
ns.PROFILES = {}              -- clé -> profil
ns.SPEC_PROFILES = {}         -- classe -> { [arbre] = clé } (classes hybrides seulement)
for _, profile in ipairs(PROFILES) do
    ns.TARGET_PROFILES[#ns.TARGET_PROFILES + 1] = profile.key
    ns.PROFILES[profile.key] = profile
    if profile.tab then
        ns.SPEC_PROFILES[profile.class] = ns.SPEC_PROFILES[profile.class] or {}
        ns.SPEC_PROFILES[profile.class][profile.tab] = profile.key
    end
end

-- Construit une liste de priorités identique (même ordre) pour tous les profils.
-- enabledFor(profile, key) -> booléen
local function uniformPriorities(order, enabledFor)
    local result = {}
    for _, profile in ipairs(PROFILES) do
        local list = {}
        for _, key in ipairs(order) do
            list[#list + 1] = { key = key, enabled = enabledFor(profile, key) }
        end
        result[profile.key] = list
    end
    return result
end

-- Paladin : ordre explicite par profil ; les familles non citées sont ajoutées désactivées.
local PALADIN_ALL = { "might", "wisdom", "kings", "salvation", "light", "sanctuary" }

local function paladinPriorities()
    local result = {}
    for _, profile in ipairs(PROFILES) do
        local list, seen = {}, {}
        for _, key in ipairs(profile.blessings) do
            list[#list + 1] = { key = key, enabled = true }
            seen[key] = true
        end
        for _, key in ipairs(PALADIN_ALL) do
            if not seen[key] then list[#list + 1] = { key = key, enabled = false } end
        end
        result[profile.key] = list
    end
    return result
end

-- reagent : composant propre à ce rang (sinon celui de la famille)
local function r(id, level, power, reagent) return { id = id, level = level, power = power, reagent = reagent } end

local SYMBOL_OF_KINGS = 21177

ns.Spells = {
    PALADIN = {
        mode = "exclusive",
        families = {
            might = {
                ranks = { r(19740, 4, 1), r(19834, 12, 2), r(19835, 22, 3), r(19836, 32, 4), r(19837, 42, 5), r(19838, 52, 6), r(25291, 60, 7) },
                group = { r(25782, 52, 6), r(25916, 60, 7) },
                duration = 300, groupDuration = 900, reagent = SYMBOL_OF_KINGS,
            },
            wisdom = {
                ranks = { r(19742, 14, 1), r(19850, 24, 2), r(19852, 34, 3), r(19853, 44, 4), r(19854, 54, 5), r(25290, 60, 6) },
                group = { r(25894, 54, 5), r(25918, 60, 6) },
                duration = 300, groupDuration = 900, reagent = SYMBOL_OF_KINGS,
            },
            kings = {
                ranks = { r(20217, 20, 1) },
                group = { r(25898, 60, 1) },
                duration = 300, groupDuration = 900, reagent = SYMBOL_OF_KINGS,
            },
            salvation = {
                ranks = { r(1038, 26, 1) },
                group = { r(25895, 60, 1) },
                duration = 300, groupDuration = 900, reagent = SYMBOL_OF_KINGS,
            },
            light = {
                ranks = { r(19977, 40, 1), r(19978, 50, 2), r(19979, 60, 3) },
                group = { r(25890, 60, 3) },
                duration = 300, groupDuration = 900, reagent = SYMBOL_OF_KINGS,
            },
            sanctuary = {
                ranks = { r(20911, 30, 1), r(20912, 40, 2), r(20913, 50, 3), r(20914, 60, 4) },
                group = { r(25899, 60, 4) },
                duration = 300, groupDuration = 900, reagent = SYMBOL_OF_KINGS,
            },
        },
        defaults = paladinPriorities(),
    },

    PRIEST = {
        mode = "cumulative",
        families = {
            fortitude = {
                ranks = { r(1243, 1, 1), r(1244, 12, 2), r(1245, 24, 3), r(2791, 36, 4), r(10937, 48, 5), r(10938, 60, 6) },
                group = { r(21562, 48, 5, 17028), r(21564, 60, 6, 17029) },
                duration = 1800, groupDuration = 3600, reagent = 17029,
            },
            spirit = {
                ranks = { r(14752, 30, 1), r(14818, 40, 2), r(14819, 50, 3), r(27841, 60, 4) },
                group = { r(27681, 60, 4) },
                duration = 1800, groupDuration = 3600, reagent = 17029,
            },
            shadowprot = {
                ranks = { r(976, 30, 1), r(10957, 42, 2), r(10958, 56, 3) },
                group = { r(27683, 56, 3) },
                duration = 600, groupDuration = 1200, reagent = 17029,
            },
        },
        defaults = uniformPriorities({ "fortitude", "spirit", "shadowprot" }, function(profile, key)
            if key == "fortitude" then return true end
            if key == "spirit" then return profile.mana == true end
            return false
        end),
    },

    MAGE = {
        mode = "cumulative",
        families = {
            intellect = {
                ranks = { r(1459, 1, 1), r(1460, 14, 2), r(1461, 28, 3), r(10156, 42, 4), r(10157, 56, 5) },
                group = { r(23028, 56, 5) },
                duration = 1800, groupDuration = 3600, reagent = 17020,
            },
            amplify = {
                ranks = { r(1008, 18, 1), r(8455, 30, 2), r(10169, 42, 3), r(10170, 54, 4) },
                duration = 600,
            },
            dampen = {
                ranks = { r(604, 12, 1), r(8450, 24, 2), r(8451, 36, 3), r(10173, 48, 4), r(10174, 60, 5) },
                duration = 600,
            },
        },
        defaults = uniformPriorities({ "intellect", "amplify", "dampen" }, function(profile, key)
            return key == "intellect" and profile.mana == true
        end),
    },

    DRUID = {
        mode = "cumulative",
        families = {
            mark = {
                ranks = { r(1126, 1, 1), r(5232, 10, 2), r(6756, 20, 3), r(5234, 30, 4), r(8907, 40, 5), r(9884, 50, 6), r(9885, 60, 7) },
                group = { r(21849, 50, 6, 17021), r(21850, 60, 7, 17026) },
                duration = 1800, groupDuration = 3600, reagent = 17026,
            },
            thorns = {
                ranks = { r(467, 6, 1), r(782, 14, 2), r(1075, 24, 3), r(8914, 34, 4), r(9756, 44, 5), r(9910, 54, 6) },
                duration = 600,
            },
        },
        defaults = uniformPriorities({ "mark", "thorns" }, function(profile, key)
            if key == "mark" then return true end
            return profile.thorns == true
        end),
    },
}

-- Index spellId -> { family, power, group } pour toutes les classes (on reconnaît aussi
-- les buffs posés par d'autres joueurs d'une autre classe que la nôtre, sans effet ici).
ns.SpellIndex = {}
for class, data in pairs(ns.Spells) do
    for key, fam in pairs(data.families) do
        fam.key = key
        for _, rank in ipairs(fam.ranks) do
            ns.SpellIndex[rank.id] = { class = class, family = key, power = rank.power, group = false }
        end
        for _, rank in ipairs(fam.group or {}) do
            ns.SpellIndex[rank.id] = { class = class, family = key, power = rank.power, group = true }
        end
    end
end
