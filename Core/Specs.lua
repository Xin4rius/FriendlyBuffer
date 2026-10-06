-- Spécialisation des cibles : arbre de talents principal, lu par inspection (une à la fois,
-- hors combat), mémorisé par GUID. Tant qu'elle est inconnue, le profil de la classe seule sert.
local _, ns = ...

local L = ns.L

local Specs = {}
ns.Specs = Specs

local INSPECT_INTERVAL = 1.5  -- secondes minimum entre deux inspections
local INSPECT_TIMEOUT = 4     -- sans réponse : abandon, nouvel essai plus tard
local RETRY_DELAY = 30        -- délai avant de réessayer un joueur qui n'a pas répondu
local CACHE_DAYS = 30         -- spés mémorisées oubliées après ce délai sans être revues

-- Spécialisations modernes (GetInspectSpecialization) -> arbre classique.
local SPEC_ID_TAB = {
    [71] = 1, [72] = 2, [73] = 3,               -- guerrier
    [65] = 1, [66] = 2, [70] = 3,               -- paladin
    [262] = 1, [263] = 2, [264] = 3,            -- chaman
    [102] = 1, [103] = 2, [104] = 2, [105] = 3, -- druide (gardien = farouche)
}
Specs.SPEC_ID_TAB = SPEC_ID_TAB

local LABELS = {
    WARRIOR_ARMS = L["Arms"], WARRIOR_FURY = L["Fury"], WARRIOR_PROTECTION = L["Protection"],
    DRUID_BALANCE = L["Balance"], DRUID_FERAL = L["Feral Combat"], DRUID_RESTORATION = L["Restoration"],
    SHAMAN_ELEMENTAL = L["Elemental"], SHAMAN_ENHANCEMENT = L["Enhancement"], SHAMAN_RESTORATION = L["Restoration"],
    PALADIN_HOLY = L["Holy"], PALADIN_PROTECTION = L["Protection"], PALADIN_RETRIBUTION = L["Retribution"],
}

-- Nom de la spé d'un profil, ou nil pour un profil de classe seule.
function Specs.SpecLabel(profileKey)
    return LABELS[profileKey]
end

-- « Classe – Spé » / « Classe (spé inconnue) » pour les classes hybrides, « Classe » sinon.
function Specs.Label(profileKey)
    local profile = ns.PROFILES[profileKey]
    local class = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[profile.class]) or profile.class
    if LABELS[profileKey] then return class .. " - " .. LABELS[profileKey] end
    if ns.SPEC_PROFILES[profile.class] then return class .. " (" .. L["spec unknown"] .. ")" end
    return class
end

-- Arbre qui a reçu le plus de points (le premier en cas d'égalité), ou nil sans aucun point.
function Specs.MainTab(points)
    local best, bestPoints = nil, 0
    for tab, count in ipairs(points) do
        if count > bestPoints then best, bestPoints = tab, count end
    end
    return best
end

-- Profil de priorités pour une classe et un arbre (nil = inconnu).
function Specs.Profile(class, tab)
    local specs = ns.SPEC_PROFILES[class]
    return specs and tab and specs[tab] or class
end

---------------------------------------------------------------------------
-- Inspection (API du jeu)
---------------------------------------------------------------------------

local cache               -- ns.db.specs : guid -> { tab = n ou 0, level, time }
local seen = {}           -- guids inspectés pendant cette session
local failed = {}         -- guid -> GetTime() du dernier échec
local wanted = {}         -- { {guid, unit, cached}, ... } du dernier scan
local pending             -- { guid, unit, sent }
local lastSent = -math.huge

function Specs.Init(db)
    db.specs = db.specs or {}
    cache = db.specs
    local limit = time() - CACHE_DAYS * 86400
    for guid, entry in pairs(cache) do
        if (entry.time or 0) < limit then cache[guid] = nil end
    end
end

-- Arbre principal du joueur lui-même (sans inspection), ou nil.
local function ownTab()
    local tab = Specs.MainTab(ns.Compat.TalentPoints(false))
    if tab then return tab end
    return SPEC_ID_TAB[ns.Compat.OwnSpecId() or 0]
end

-- Profil de priorités d'un candidat { unit, guid, class, level }. Note les joueurs à inspecter.
function Specs.ProfileFor(candidate)
    local class = candidate.class
    if not ns.SPEC_PROFILES[class] then return class end
    if UnitIsUnit(candidate.unit, "player") then return Specs.Profile(class, ownTab()) end
    local entry = cache and cache[candidate.guid]
    -- Pas de talents : à revoir quand le joueur aura pris un niveau.
    local stale = entry and entry.tab == 0 and entry.level ~= candidate.level
    if not entry or stale or not seen[candidate.guid] then
        wanted[#wanted + 1] = { guid = candidate.guid, unit = candidate.unit, cached = entry ~= nil and not stale }
    end
    return Specs.Profile(class, entry and entry.tab ~= 0 and entry.tab or nil)
end

local function inspectFrameShown()
    return InspectFrame ~= nil and InspectFrame:IsShown()
end

-- Après chaque scan : lance au plus une inspection (spés inconnues d'abord).
function Specs.Update()
    local list = wanted
    wanted = {}
    if not ns.db.detectSpecs or InCombatLockdown() or inspectFrameShown() then return end
    local now = GetTime()
    if pending then
        if now - pending.sent < INSPECT_TIMEOUT then return end
        failed[pending.guid] = now
        pending = nil
    end
    if now - lastSent < INSPECT_INTERVAL then return end
    local choice
    for _, want in ipairs(list) do
        local failedAt = failed[want.guid]
        if (not failedAt or now - failedAt > RETRY_DELAY) and UnitGUID(want.unit) == want.guid
            and ns.Compat.CanInspect(want.unit) then
            if not want.cached then choice = want break end
            choice = choice or want
        end
    end
    if not choice then return end
    pending = { guid = choice.guid, unit = choice.unit, sent = now }
    lastSent = now
    ns.Compat.NotifyInspect(choice.unit)
end

-- Inspection lancée par l'interface ou un autre addon : on lui laisse la place.
function Specs.OnForeignInspect()
    lastSent = GetTime()
end

function Specs.OnInspectReady(guid)
    local mine = pending and pending.guid == guid
    if mine then pending = nil end
    local unit = ns.Scanner.FindUnit(guid)
    if not unit or not cache then return end
    local _, class = UnitClass(unit)
    if not ns.SPEC_PROFILES[class] then return end
    local tab = Specs.MainTab(ns.Compat.TalentPoints(true)) or SPEC_ID_TAB[ns.Compat.InspectSpecId(unit) or 0]
    cache[guid] = { tab = tab or 0, level = UnitLevel(unit), time = time() }
    seen[guid] = true
    failed[guid] = nil
    if mine and not inspectFrameShown() then ns.Compat.ClearInspect() end
    ns.RequestScan()
end
