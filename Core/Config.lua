-- Réglages : valeurs par défaut et fusion avec la sauvegarde par personnage.
local _, ns = ...

local Config = {}
ns.Config = Config

Config.DISPLAY_MODES = { "minimal", "info", "range" }

local DEFAULTS = {
    groupBuffs = false,
    displayMode = "minimal",
    autoHide = true,
    locked = false,
    maxRows = 10,
    includeStrangers = true,
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
