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

local function strangerUnits()
    local units = { "target", "mouseover" }
    for i = 1, MAX_NAMEPLATES do units[#units + 1] = "nameplate" .. i end
    return units
end

local function isCandidate(unit, isGroup)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
    if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then return false end
    if not UnitCanAssist("player", unit) then return false end
    if not isGroup then
        if UnitInParty(unit) or UnitInRaid(unit) or UnitIsUnit(unit, "player") then return false end
        -- Ne pas se faire marquer JcJ en buffant un inconnu marqué.
        if UnitIsPVP(unit) and not UnitIsPVP("player") then return false end
    end
    return true
end

local function fullName(unit)
    local name, realm = UnitName(unit)
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

-- Retourne { {unit, guid, name, class, level, isGroup}, ... }, dédoublonné par GUID.
function Scanner.Collect(includeStrangers)
    local result, seen = {}, {}
    local function add(unit, isGroup)
        if not isCandidate(unit, isGroup) then return end
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
    return result
end
