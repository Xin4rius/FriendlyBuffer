-- Lecture des buffs d'une unité, ramenés à nos familles de buffs.
local _, ns = ...

local Auras = {}
ns.Auras = Auras

-- Nom localisé -> famille, rempli au chargement (secours si un spellId est inconnu de nos tables).
Auras.NameIndex = {}

-- raw : { {spellId, name, sourceUnit, duration, expirationTime}, ... }
-- Retourne { {family, power, mine, remaining, duration}, ... } (seulement les buffs reconnus).
function Auras.Normalize(raw, now)
    local result = {}
    for _, aura in ipairs(raw) do
        local info = aura.spellId and ns.SpellIndex[aura.spellId]
        local family, power
        if info then
            family, power = info.family, info.power
        elseif aura.name then
            family = Auras.NameIndex[aura.name] -- puissance inconnue : jamais « rang inférieur »
        end
        if family then
            local duration = aura.duration or 0
            local remaining
            if duration > 0 and aura.expirationTime and aura.expirationTime > 0 then
                remaining = aura.expirationTime - now
            end
            result[#result + 1] = {
                family = family,
                power = power,
                mine = aura.sourceUnit == "player",
                remaining = remaining,
                duration = duration,
                spellId = aura.spellId,
            }
        end
    end
    return result
end

---------------------------------------------------------------------------
-- Mode combat : les auras deviennent secrètes. On garde la dernière lecture hors combat de chaque
-- joueur (par GUID) et on la tient à jour : retraits (UNIT_AURA, API par identifiant), expirations
-- connues, auras ajoutées encore lisibles, et nos propres buffs lancés (NoteCast).
---------------------------------------------------------------------------

local DISPELLABLE = "HARMFUL|RAID_PLAYER_DISPELLABLE"
local tracked = {} -- guid -> { buffs = {raw...}, debuffs = {raw...} } ; raw.id = identifiant d'aura

local function isSecret(v) return ns.Compat.IsSecret(v) end
local function plain(v) if not isSecret(v) then return v end end

local function guidOf(unit)
    local guid = UnitGUID(unit)
    if guid and not isSecret(guid) then return guid end
end

local function entry(guid)
    local t = tracked[guid] or { buffs = {}, debuffs = {} }
    tracked[guid] = t
    return t
end

local function indexOf(list, id)
    for i, a in ipairs(list) do
        if a.id == id then return i end
    end
end

-- Aura ajoutée en combat (charge utile de UNIT_AURA ou lecture par identifiant) : gardée si lisible.
local function addAura(unit, t, id, aura)
    if indexOf(t.buffs, id) or indexOf(t.debuffs, id) then return end
    local harmful = plain(aura.isHarmful)
    if harmful == nil then harmful = ns.Compat.AuraPasses(unit, id, "HARMFUL") end
    if harmful == true then
        t.debuffs[#t.debuffs + 1] = {
            id = id, icon = aura.icon, dispelName = plain(aura.dispelName), expirationTime = plain(aura.expirationTime),
            dispellable = ns.Compat.AuraPasses(unit, id, DISPELLABLE),
        }
    elseif harmful == false then
        local spellId, name = plain(aura.spellId), plain(aura.name)
        -- Buff non identifiable : ignoré (le joueur reste « à buffer », comme avant).
        if spellId or name then
            t.buffs[#t.buffs + 1] = {
                id = id, spellId = spellId, name = name, sourceUnit = plain(aura.sourceUnit),
                duration = plain(aura.duration), expirationTime = plain(aura.expirationTime),
            }
        end
    end
end

-- Retire de `list` les auras expirées ou disparues ; ajoute celles que le client liste et qu'on ignore.
local function refresh(unit, t, list, filter, now)
    local ids = ns.Compat.AuraIds(unit, filter)
    local present
    if ids then
        present = {}
        for _, id in ipairs(ids) do present[id] = true end
    end
    for i = #list, 1, -1 do
        local a = list[i]
        local gone
        if a.id and present then
            gone = not present[a.id]
        elseif a.id then
            gone = ns.Compat.AuraById(unit, a.id) == false
        end
        if gone or (a.expirationTime and a.expirationTime > 0 and a.expirationTime <= now) then table.remove(list, i) end
    end
    for _, id in ipairs(ids or {}) do
        local data = not indexOf(list, id) and ns.Compat.AuraById(unit, id)
        if type(data) == "table" then addAura(unit, t, id, data) end
    end
end

-- UNIT_AURA en combat. Tout champ peut être secret : appeler sous pcall.
function Auras.OnUnitAura(unit, info)
    if not ns.Compat.AurasSecret() or type(info) ~= "table" or isSecret(info) then return end
    local guid = guidOf(unit)
    local t = guid and tracked[guid]
    if not t then return end
    for _, id in ipairs(plain(info.removedAuraInstanceIDs) or {}) do
        if not isSecret(id) then
            local i = indexOf(t.buffs, id)
            if i then table.remove(t.buffs, i) end
            i = indexOf(t.debuffs, id)
            if i then table.remove(t.debuffs, i) end
        end
    end
    for _, aura in ipairs(plain(info.addedAuras) or {}) do
        local id = plain(aura.auraInstanceID)
        if id then addAura(unit, t, id, aura) end
    end
end

-- Écoute propre : la mémoire doit suivre UNIT_AURA quelle que soit la classe (buffs et/ou dissipation).
function Auras.Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_AURA")
    f:SetScript("OnEvent", function(_, _, unit, info) pcall(Auras.OnUnitAura, unit, info) end)
end

-- Buff lancé par nous en combat (le client ne nous le montre pas) : supposé posé pour `duration` s.
function Auras.NoteCast(guid, spellId, duration)
    if not (tracked[guid] and tracked[guid].seen) then return end
    local buffs = tracked[guid].buffs
    buffs[#buffs + 1] = {
        spellId = spellId, sourceUnit = "player", duration = duration or 0,
        expirationTime = duration and duration > 0 and (GetTime() + duration) or 0,
    }
end

-- Buffs normalisés d'une unité. Hors combat : lecture directe, mémorisée. En combat : la mémoire
-- tenue à jour ; nil si ce joueur n'a jamais été lu hors combat (état inconnu).
function Auras.Read(unit)
    local guid = guidOf(unit)
    if not ns.Compat.AurasSecret() then
        local raw = ns.Compat.GetBuffs(unit)
        if guid then
            local t = entry(guid)
            t.buffs, t.seen = raw, true
        end
        return Auras.Normalize(raw, GetTime())
    end
    local t = guid and tracked[guid]
    if not (t and t.seen) then return nil end
    refresh(unit, t, t.buffs, "HELPFUL", GetTime())
    return Auras.Normalize(t.buffs, GetTime())
end

-- Débuffs bruts { {name, icon, dispelName, dispellable}, ... }, même principe ({} si inconnu).
function Auras.ReadDebuffs(unit)
    local guid = guidOf(unit)
    if not ns.Compat.AurasSecret() then
        local raw = ns.Compat.GetDebuffs(unit)
        if guid then entry(guid).debuffs = raw end
        return raw
    end
    local t = guid and tracked[guid]
    if not t then
        -- Jamais lu hors combat : on commence une mémoire vide, alimentée par les ajouts.
        if not guid then return {} end
        t = entry(guid)
    end
    refresh(unit, t, t.debuffs, "HARMFUL", GetTime())
    return t.debuffs
end
