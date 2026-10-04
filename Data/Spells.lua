-- Données des buffs par classe.
-- Chaque famille : rangs individuels {id, level, power}, versions groupe/supérieures
-- (power = rang individuel équivalent), durées en secondes, composant de la version groupe.
local _, ns = ...

local TARGET_CLASSES = { "WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "SHAMAN", "PALADIN" }
ns.TARGET_CLASSES = TARGET_CLASSES

local MANA_CLASSES = { HUNTER = true, MAGE = true, WARLOCK = true, PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }

-- Construit une liste de priorités identique pour toutes les classes de cible.
-- enabledFor(targetClass, key) -> booléen
local function uniformPriorities(order, enabledFor)
    local result = {}
    for _, cls in ipairs(TARGET_CLASSES) do
        local list = {}
        for _, key in ipairs(order) do
            list[#list + 1] = { key = key, enabled = enabledFor(cls, key) }
        end
        result[cls] = list
    end
    return result
end

-- Paladin : ordre explicite par classe de cible ; les familles non citées sont ajoutées désactivées.
local PALADIN_ALL = { "might", "wisdom", "kings", "salvation", "light", "sanctuary" }
local PALADIN_ORDER = {
    WARRIOR = { "might", "kings", "light" },
    ROGUE   = { "might", "kings", "salvation", "light" },
    HUNTER  = { "wisdom", "kings", "salvation", "might" },
    MAGE    = { "wisdom", "kings", "salvation", "light" },
    WARLOCK = { "wisdom", "kings", "salvation", "light" },
    PRIEST  = { "wisdom", "kings", "salvation", "light" },
    DRUID   = { "wisdom", "kings", "salvation", "might" },
    SHAMAN  = { "wisdom", "kings", "salvation", "might" },
    PALADIN = { "wisdom", "kings", "might", "light" },
}

local function paladinPriorities()
    local result = {}
    for _, cls in ipairs(TARGET_CLASSES) do
        local list, seen = {}, {}
        for _, key in ipairs(PALADIN_ORDER[cls]) do
            list[#list + 1] = { key = key, enabled = true }
            seen[key] = true
        end
        for _, key in ipairs(PALADIN_ALL) do
            if not seen[key] then list[#list + 1] = { key = key, enabled = false } end
        end
        result[cls] = list
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
        defaults = uniformPriorities({ "fortitude", "spirit", "shadowprot" }, function(cls, key)
            if key == "fortitude" then return true end
            if key == "spirit" then return MANA_CLASSES[cls] == true end
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
        defaults = uniformPriorities({ "intellect", "amplify", "dampen" }, function(cls, key)
            return key == "intellect" and MANA_CLASSES[cls] == true
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
        defaults = uniformPriorities({ "mark", "thorns" }, function(cls, key)
            if key == "mark" then return true end
            return cls == "WARRIOR"
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
