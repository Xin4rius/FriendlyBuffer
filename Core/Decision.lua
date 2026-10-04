-- Logique pure : quel buff donner à une cible, et pourquoi.
-- N'utilise aucune API WoW : testable hors jeu (voir tests/).
local _, ns = ...

local Decision = {}
ns.Decision = Decision

local MAX_LEVEL = 60
-- Un rang de niveau requis L ne peut être posé que sur une cible de niveau >= L - 10.
local LEVEL_GAP = 10

Decision.URGENCY = { missing = 1, expiring = 2, lower = 3 }

-- Meilleur rang connu et utilisable sur une cible de ce niveau, ou nil.
function Decision.BestRank(ranks, isKnown, targetLevel)
    if not ranks then return nil end
    if not targetLevel or targetLevel <= 0 then targetLevel = MAX_LEVEL end
    local best
    for _, rank in ipairs(ranks) do
        if isKnown(rank.id) and rank.level - LEVEL_GAP <= targetLevel then
            if not best or rank.power > best.power then best = rank end
        end
    end
    return best
end

local function threshold(settings, duration)
    if duration <= 600 then return settings.thresholdShort end
    return settings.thresholdLong
end

local function isExpiring(aura, settings)
    if not aura.remaining or not aura.duration or aura.duration <= 0 then return false end
    return aura.remaining < threshold(settings, aura.duration)
end

-- Aura la plus puissante d'une famille sur la cible (filtre optionnel).
local function strongestAura(auras, familyKey, filter)
    local best
    for _, aura in ipairs(auras) do
        if aura.family == familyKey and (not filter or filter(aura)) then
            if not best or (aura.power or 0) > (best.power or 0) then best = aura end
        end
    end
    return best
end

local function makeNeed(fam, reason, aura, single, ctx, target)
    local need = {
        family = fam.key,
        reason = reason,
        remaining = aura and aura.remaining or nil,
        single = single,
    }
    if ctx.settings.groupBuffs and target.isGroup and fam.group then
        need.group = Decision.BestRank(fam.group, ctx.isKnown, target.level)
    end
    return need
end

-- Besoin pour une famille donnée en ne regardant que `aura` (déjà choisie), ou nil.
local function familyNeed(fam, aura, ctx, target)
    local single = Decision.BestRank(fam.ranks, ctx.isKnown, target.level)
    if not single then return nil end
    if not aura then return makeNeed(fam, "missing", nil, single, ctx, target) end
    if isExpiring(aura, ctx.settings) then return makeNeed(fam, "expiring", aura, single, ctx, target) end
    if aura.power and aura.power < single.power then return makeNeed(fam, "lower", aura, single, ctx, target) end
    return nil
end

local function evaluateCumulative(classData, ctx, target)
    local chosen
    for _, entry in ipairs(ctx.priorities) do
        local fam = classData.families[entry.key]
        if entry.enabled and fam then
            local need = familyNeed(fam, strongestAura(target.auras, fam.key), ctx, target)
            if need and (not chosen or Decision.URGENCY[need.reason] < Decision.URGENCY[chosen.reason]) then
                chosen = need
            end
        end
    end
    return chosen
end

local function evaluateExclusive(classData, ctx, target)
    local enabled = {}
    for _, entry in ipairs(ctx.priorities) do
        if entry.enabled then enabled[entry.key] = true end
    end

    -- Ma bénédiction actuelle sur la cible (une seule possible).
    local mine
    for _, aura in ipairs(target.auras) do
        if aura.mine and classData.families[aura.family] then mine = aura break end
    end
    if mine and enabled[mine.family] then
        return familyNeed(classData.families[mine.family], mine, ctx, target)
    end

    -- Sinon : première bénédiction activée que personne n'a encore posée.
    for _, entry in ipairs(ctx.priorities) do
        local fam = classData.families[entry.key]
        if entry.enabled and fam then
            local others = strongestAura(target.auras, fam.key, function(a) return not a.mine end)
            if not others then
                local single = Decision.BestRank(fam.ranks, ctx.isKnown, target.level)
                if single then return makeNeed(fam, "missing", nil, single, ctx, target) end
            end
        end
    end
    return nil
end

-- classData : ns.Spells[classe du joueur]
-- ctx : { isKnown = function(spellId), settings = {thresholdShort, thresholdLong, groupBuffs}, priorities = { {key, enabled}, ... } }
-- target : { level, isGroup, auras = { {family, power, mine, remaining, duration}, ... } }
-- Retourne { family, reason, remaining, single = rang, group = rang|nil } ou nil.
function Decision.Evaluate(classData, ctx, target)
    if not classData or not ctx.priorities then return nil end
    if classData.mode == "exclusive" then
        return evaluateExclusive(classData, ctx, target)
    end
    return evaluateCumulative(classData, ctx, target)
end

-- Tri des lignes : joueurs derrière un obstacle en dernier, puis urgence, groupe avant inconnus, nom.
function Decision.Compare(a, b)
    if (a.blocked or false) ~= (b.blocked or false) then return not a.blocked end
    local ua, ub = Decision.URGENCY[a.need.reason], Decision.URGENCY[b.need.reason]
    if ua ~= ub then return ua < ub end
    if a.isGroup ~= b.isGroup then return a.isGroup end
    return a.name < b.name
end
