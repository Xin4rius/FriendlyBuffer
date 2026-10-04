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

-- Buffs normalisés d'une unité (API du jeu, via Compat).
function Auras.Read(unit)
    return Auras.Normalize(ns.Compat.GetBuffs(unit), GetTime())
end
