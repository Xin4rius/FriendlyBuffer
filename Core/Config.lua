-- Réglages : valeurs par défaut et fusion avec la sauvegarde par personnage.
local _, ns = ...

local L = ns.L

local Config = {}
ns.Config = Config

Config.DISPLAY_MODES = { "minimal", "info" }

-- Style des noms des barres de nom discrètes.
Config.PLATE_FONTS = {
    { key = "friz", label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arial", label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { key = "skurri", label = "Skurri", path = "Fonts\\skurri.ttf" },
    { key = "morpheus", label = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
}
Config.PLATE_OUTLINES = {
    { key = "none", label = L["None"], flags = "" },
    { key = "thin", label = L["Thin"], flags = "OUTLINE" },
    { key = "thick", label = L["Thick"], flags = "THICKOUTLINE" },
}

function Config.Find(list, key)
    for _, entry in ipairs(list) do
        if entry.key == key then return entry end
    end
    return list[1]
end

local DEFAULTS = {
    groupBuffs = false,
    displayMode = "minimal",
    autoHide = true,
    locked = false,
    maxRows = 10,
    includeStrangers = true,
    detectSpecs = true,     -- inspecte les joueurs pour connaître leur spé
    hiddenPlates = false,
    -- Par défaut : aspect des noms de WoW sans Maj+V.
    plateFont = "friz",
    plateFontSize = 12,
    plateOutline = "none",
    plateShadow = true,
    plateGuild = true,
    thresholdShort = 60,
    thresholdLong = 180,
    doneDuration = 5,       -- secondes d'affichage « OK » d'un joueur qu'on vient de buffer (0 = jamais)
    includePets = false,    -- familiers des membres du groupe
    reagentWarn = 5,        -- prévient quand il reste ce nombre de composants de groupe ou moins (0 = jamais)
    contextPresets = false, -- priorités distinctes seul / en groupe / en raid
}

Config.CONTEXTS = { solo = L["solo"], party = L["group"], raid = L["raid"] }

local function copyList(list)
    local out = {}
    for i, entry in ipairs(list) do out[i] = { key = entry.key, enabled = entry.enabled } end
    return out
end

-- Garde l'ordre et l'état sauvegardés, retire les familles inconnues, ajoute les nouvelles.
function Config.MergePriorities(saved, defaults, families)
    local out, seen = {}, {}
    for _, entry in ipairs(saved or {}) do
        if families[entry.key] and not seen[entry.key] then
            out[#out + 1] = { key = entry.key, enabled = entry.enabled and true or false }
            seen[entry.key] = true
        end
    end
    for _, entry in ipairs(defaults) do
        if not seen[entry.key] then
            out[#out + 1] = { key = entry.key, enabled = entry.enabled }
            seen[entry.key] = true
        end
    end
    return out
end

-- Remet les priorités (par profil et personnelles) en accord avec les données de la classe.
local function normalize(db, classData)
    db.priorities = db.priorities or {}
    if not classData then return end
    -- Les priorités sauvegardées par classe (versions sans spé) restent celles du profil « spé inconnue ».
    for _, profile in ipairs(ns.TARGET_PROFILES) do
        db.priorities[profile] = Config.MergePriorities(db.priorities[profile], classData.defaults[profile], classData.families)
    end
    db.personal = Config.MergePriorities(db.personal, classData.personal.defaults, classData.personal.families)
end

-- db : table sauvegardée (peut être vide) ; classData : ns.Spells[classe] ou nil.
function Config.Load(db, classData)
    for key, value in pairs(DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end
    -- L'ancien mode « range » (grisé hors portée) n'existe plus : les joueurs hors portée sont exclus.
    if db.displayMode == "range" then db.displayMode = "info" end
    db.ignored = db.ignored or {}
    normalize(db, classData)
    return db
end

-- Priorités distinctes par contexte ("solo", "party", "raid") : range celles du contexte quitté,
-- reprend celles du nouveau (ou part d'une copie des priorités en cours). Retourne true si changé.
function Config.SwitchContext(db, classData, context)
    if db.context == context then return false end
    db.contexts = db.contexts or {}
    if db.context then db.contexts[db.context] = { priorities = db.priorities, personal = db.personal } end
    local saved = db.contexts[context]
    if saved then
        db.priorities, db.personal = saved.priorities, saved.personal
    elseif db.context then
        local copy = {}
        for profile, list in pairs(db.priorities) do copy[profile] = copyList(list) end
        db.priorities, db.personal = copy, copyList(db.personal or {})
    end
    db.context = context
    normalize(db, classData)
    return true
end

function Config.ResetPriorities(db, classData, profile)
    db.priorities[profile] = copyList(classData.defaults[profile])
end

-- Coche ou décoche une famille dans une liste. En cocher une décoche celles qu'elle remplace
-- (même groupe excl) : une seule des deux peut tenir sur la cible.
function Config.SetEnabled(list, key, enabled)
    local excl = enabled and ns.FamilyExcl[key]
    for _, entry in ipairs(list) do
        if entry.key == key then
            entry.enabled = enabled
        elseif excl and ns.FamilyExcl[entry.key] == excl then
            entry.enabled = false
        end
    end
end

-- Active ou coupe une famille pour tous les profils (l'ordre de chacun est gardé),
-- ou dans les buffs personnels si c'en est une.
function Config.SetFamilyForAll(db, key, enabled)
    local lists = { db.personal }
    for _, list in pairs(db.priorities) do lists[#lists + 1] = list end
    for _, list in pairs(lists) do Config.SetEnabled(list, key, enabled) end
end

-- La famille est-elle activée partout où elle figure ?
function Config.FamilyEnabledForAll(db, key)
    local lists = { db.personal }
    for _, list in pairs(db.priorities) do lists[#lists + 1] = list end
    for _, list in pairs(lists) do
        for _, entry in ipairs(list) do
            if entry.key == key and not entry.enabled then return false end
        end
    end
    return true
end
