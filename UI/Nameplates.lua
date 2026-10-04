-- Option « barres de nom alliées invisibles » : les barres alliées restent actives (l'addon en a
-- besoin pour voir les inconnus) mais sont transparentes et laissent passer les clics.
local _, ns = ...

local Nameplates = {}
ns.Nameplates = Nameplates

local MAX_NAMEPLATES = 40
local hidden = setmetatable({}, { __mode = "k" }) -- cadres que l'on a rendus transparents

local function unitFrame(unit)
    local plate = ns.Compat.GetNamePlateForUnit(unit)
    return plate and plate.UnitFrame
end

local function restore(frame)
    if frame and hidden[frame] then
        frame:SetAlpha(1)
        hidden[frame] = nil
    end
end

-- Applique l'état voulu à la barre d'une unité (les barres sont recyclées entre alliés et ennemis).
function Nameplates.Update(unit)
    local frame = unitFrame(unit)
    if not frame then return end
    if ns.db.hiddenPlates and UnitExists(unit) and not UnitCanAttack("player", unit) then
        frame:SetAlpha(0)
        hidden[frame] = true
    else
        restore(frame)
    end
end

function Nameplates.Removed(unit)
    restore(unitFrame(unit))
end

-- Active ou retire le mode invisible (hors combat : la CVar est protégée en combat).
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
