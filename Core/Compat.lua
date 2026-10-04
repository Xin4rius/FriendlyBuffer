-- Enveloppes d'API : seul endroit qui teste l'existence des fonctions du client.
local _, ns = ...

local Compat = {}
ns.Compat = Compat

local MAX_BUFFS = 40

function Compat.GetBuffs(unit)
    local list = {}
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        for i = 1, MAX_BUFFS do
            local data = C_UnitAuras.GetBuffDataByIndex(unit, i)
            if not data then break end
            list[#list + 1] = {
                spellId = data.spellId, name = data.name, sourceUnit = data.sourceUnit,
                duration = data.duration, expirationTime = data.expirationTime,
            }
        end
    else
        for i = 1, MAX_BUFFS do
            local name, _, _, _, duration, expirationTime, source, _, _, spellId = UnitBuff(unit, i)
            if not name then break end
            list[#list + 1] = {
                spellId = spellId, name = name, sourceUnit = source,
                duration = duration, expirationTime = expirationTime,
            }
        end
    end
    return list
end

-- Retourne nom, icône ou nil si le sort n'existe pas sur ce client.
function Compat.GetSpellInfo(spellId)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellId)
        if info then return info.name, info.iconID end
        return nil
    end
    local name, _, icon = GetSpellInfo(spellId)
    return name, icon
end

function Compat.GetSpellSubtext(spellId)
    if C_Spell and C_Spell.GetSpellSubtext then return C_Spell.GetSpellSubtext(spellId) end
    if GetSpellSubtext then return GetSpellSubtext(spellId) end
    return nil
end

function Compat.IsKnown(spellId)
    if IsSpellKnown and IsSpellKnown(spellId) then return true end
    if IsPlayerSpell and IsPlayerSpell(spellId) then return true end
    return false
end

-- true / false, ou nil si la portée ne peut pas être déterminée.
function Compat.InRange(spellId, unit)
    if C_Spell and C_Spell.IsSpellInRange then
        return C_Spell.IsSpellInRange(spellId, unit)
    end
    local name = Compat.GetSpellInfo(spellId)
    if not name or not IsSpellInRange then return nil end
    local r = IsSpellInRange(name, unit)
    if r == nil then return nil end
    return r == 1
end

function Compat.ItemCount(itemId)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemId) end
    return GetItemCount(itemId)
end

function Compat.ClassColor(class)
    local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Enregistre un panneau d'options ; retourne un objet à passer à OpenOptions.
function Compat.RegisterOptions(panel, title)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, title)
        Settings.RegisterAddOnCategory(category)
        return category
    end
    panel.name = title
    InterfaceOptions_AddCategory(panel)
    return panel
end

function Compat.OpenOptions(handle)
    if Settings and Settings.OpenToCategory and handle.GetID then
        Settings.OpenToCategory(handle:GetID())
    else
        InterfaceOptionsFrame_OpenToCategory(handle)
        InterfaceOptionsFrame_OpenToCategory(handle)
    end
end
