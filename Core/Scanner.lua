-- Liste des joueurs candidats : groupe/raid, puis inconnus visibles (barres de nom, cible, survol).
local _, ns = ...

local Scanner = {}
ns.Scanner = Scanner

local MAX_NAMEPLATES = 40

local function groupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        units[1] = "player"
        if IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
        end
    end
    return units
end

-- Barres de nom d'abord : c'est l'unité sur laquelle le sort sera lancé. La cible en dernier
-- (le survol est exclu : il disparaît dès que la souris va sur la fenêtre).
local function strangerUnits()
    local units = {}
    for i = 1, MAX_NAMEPLATES do units[#units + 1] = "nameplate" .. i end
    units[#units + 1] = "target"
    return units
end

-- Retourne true, ou false + raison du rejet (pour /fb debug).
local function isCandidate(unit, isGroup)
    if not UnitExists(unit) then return false, nil end
    if not UnitIsPlayer(unit) then return false, "pnj" end
    if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then return false, "mort/déco" end
    if not UnitCanAssist("player", unit) then return false, "non assistable" end
    if not isGroup then
        if UnitInParty(unit) or UnitInRaid(unit) or UnitIsUnit(unit, "player") then return false, nil end
        -- Ne pas se faire marquer JcJ en buffant un inconnu marqué.
        if UnitIsPVP(unit) and not UnitIsPVP("player") then return false, "JcJ" end
    end
    return true
end

local function fullName(unit)
    local name, realm = UnitName(unit)
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

-- Retourne { {unit, guid, name, class, level, isGroup}, ... } dédoublonné par GUID,
-- et le décompte des unités rejetées par raison.
function Scanner.Collect(includeStrangers)
    local result, seen, rejected = {}, {}, {}
    local function add(unit, isGroup)
        local ok, reason = isCandidate(unit, isGroup)
        if not ok then
            if reason then rejected[reason] = (rejected[reason] or 0) + 1 end
            return
        end
        local guid = UnitGUID(unit)
        if not guid or seen[guid] then return end
        seen[guid] = true
        local _, class = UnitClass(unit)
        result[#result + 1] = {
            unit = unit, guid = guid, name = fullName(unit), class = class,
            level = UnitLevel(unit), isGroup = isGroup,
        }
    end
    for _, unit in ipairs(groupUnits()) do add(unit, true) end
    if includeStrangers then
        for _, unit in ipairs(strangerUnits()) do add(unit, false) end
    end
    return result, rejected
end

-- Unité qui désigne actuellement ce GUID (les numéros de barres de nom changent), ou nil.
function Scanner.FindUnit(guid)
    for _, list in ipairs({ groupUnits(), strangerUnits() }) do
        for _, unit in ipairs(list) do
            if UnitGUID(unit) == guid then return unit end
        end
    end
    return nil
end
