-- Option « barres de nom alliées discrètes » : les barres alliées restent actives (l'addon en a
-- besoin pour voir les inconnus) mais on n'en garde que le nom, comme sans Maj+V, et elles laissent
-- passer les clics.
local _, ns = ...

local Nameplates = {}
ns.Nameplates = Nameplates

local MAX_NAMEPLATES = 40
local hidden = setmetatable({}, { __mode = "k" }) -- UnitFrame -> éléments rendus transparents

local function unitFrame(unit)
    local plate = ns.Compat.GetNamePlateForUnit(unit)
    return plate and plate.UnitFrame
end

-- Vrai si `object` est le nom ou contient le nom (on ne doit pas le masquer).
local function holdsName(object, name)
    local node = name
    while node do
        if node == object then return true end
        node = node:GetParent()
    end
    return false
end

-- Masque tout ce qui compose la barre (barre de vie, bordure, icônes…) sauf le nom.
-- Si le nom est imbriqué dans un élément (ex. la barre de vie), on descend dans cet élément.
local function keepOnlyName(frame)
    if hidden[frame] then return end
    local name, faded = frame.name or frame.Name, {}
    local function fadeContents(container)
        local parts = { container:GetRegions() }
        if container.GetChildren then
            for _, child in ipairs({ container:GetChildren() }) do parts[#parts + 1] = child end
        end
        for _, object in ipairs(parts) do
            if not name or not holdsName(object, name) then
                object:SetAlpha(0)
                faded[#faded + 1] = object
            elseif object ~= name then
                fadeContents(object)
            end
        end
    end
    fadeContents(frame)
    hidden[frame] = faded
end

local function restore(frame)
    if not frame or not hidden[frame] then return end
    for _, object in ipairs(hidden[frame]) do object:SetAlpha(1) end
    hidden[frame] = nil
end

-- Applique l'état voulu à la barre d'une unité (les barres sont recyclées entre alliés et ennemis).
function Nameplates.Update(unit)
    local frame = unitFrame(unit)
    if not frame then return end
    if ns.db.hiddenPlates and UnitExists(unit) and not UnitCanAttack("player", unit) then
        keepOnlyName(frame)
    else
        restore(frame)
    end
end

function Nameplates.Removed(unit)
    restore(unitFrame(unit))
end

-- Active ou retire le mode discret (hors combat : la CVar est protégée en combat).
function Nameplates.Apply()
    if InCombatLockdown() then return end
    if ns.db.hiddenPlates then
        if not ns.Compat.FriendlyNameplatesShown() then
            ns.Compat.SetFriendlyNameplates(true)
            ns.db.platesEnabledByAddon = true
        end
        ns.Compat.SetFriendlyClickThrough(true)
        ns.db.clickThroughByAddon = true
    else
        if ns.db.clickThroughByAddon then
            ns.Compat.SetFriendlyClickThrough(false)
            ns.db.clickThroughByAddon = nil
        end
        if ns.db.platesEnabledByAddon then
            ns.Compat.SetFriendlyNameplates(false)
            ns.db.platesEnabledByAddon = nil
        end
    end
    for i = 1, MAX_NAMEPLATES do Nameplates.Update("nameplate" .. i) end
end
