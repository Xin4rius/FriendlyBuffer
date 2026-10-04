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
    hiddenPlates = false,
    -- Par défaut : aspect des noms de WoW sans Maj+V.
    plateFont = "friz",
    plateFontSize = 12,
    plateOutline = "none",
    plateShadow = true,
    plateGuild = true,
    thresholdShort = 60,
    thresholdLong = 180,
}

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

-- db : table sauvegardée (peut être vide) ; classData : ns.Spells[classe] ou nil.
function Config.Load(db, classData)
    for key, value in pairs(DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end
    -- L'ancien mode « range » (grisé hors portée) n'existe plus : les joueurs hors portée sont exclus.
    if db.displayMode == "range" then db.displayMode = "info" end
    db.priorities = db.priorities or {}
    if classData then
        for _, cls in ipairs(ns.TARGET_CLASSES) do
            db.priorities[cls] = Config.MergePriorities(db.priorities[cls], classData.defaults[cls], classData.families)
        end
    end
    return db
end

function Config.ResetPriorities(db, classData, targetClass)
    db.priorities[targetClass] = copyList(classData.defaults[targetClass])
end
