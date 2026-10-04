-- Initialisation, événements, scan et commandes.
local ADDON, ns = ...

local PREFIX = "|cff33ccffFriendlyBuffer|r : "
local SCAN_THROTTLE = 0.2   -- délai minimum entre deux scans déclenchés par événement
local TICK = 1.0            -- rafraîchissement périodique (expirations, portée)

local function say(msg) print(PREFIX .. msg) end
ns.Print = say

---------------------------------------------------------------------------
-- Sorts : libellés et texte de /cast
---------------------------------------------------------------------------

-- "Nom(Rang N)" pour les macros ; le nom seul si le client ne donne pas de rang.
function ns.CastString(rank)
    local name = ns.Compat.GetSpellInfo(rank.id) or ""
    local sub = ns.Compat.GetSpellSubtext(rank.id)
    if sub and sub ~= "" then return name .. "(" .. sub .. ")" end
    return name
end

function ns.SpellLabel(rank)
    local name = ns.Compat.GetSpellInfo(rank.id) or ("#" .. rank.id)
    local sub = ns.Compat.GetSpellSubtext(rank.id)
    if sub and sub ~= "" then return name .. " (" .. sub .. ")" end
    return name
end

-- Remplit l'index nom -> famille et signale une fois les IDs absents du client.
local function indexSpellNames()
    local missing = {}
    for _, data in pairs(ns.Spells) do
        for key, fam in pairs(data.families) do
            for _, list in ipairs({ fam.ranks, fam.group or {} }) do
                for _, rank in ipairs(list) do
                    local name = ns.Compat.GetSpellInfo(rank.id)
                    if name then
                        ns.Auras.NameIndex[name] = ns.Auras.NameIndex[name] or key
                    elseif data == ns.classData then
                        missing[#missing + 1] = rank.id
                    end
                end
            end
        end
    end
    if #missing > 0 then
        say("sorts inconnus de ce client, ignorés : " .. table.concat(missing, ", "))
    end
end

---------------------------------------------------------------------------
-- Scan
---------------------------------------------------------------------------

local function buildRows()
    local rows = {}
    if not ns.classData then return rows end
    local db = ns.db
    for _, candidate in ipairs(ns.Scanner.Collect(db.includeStrangers)) do
        local priorities = db.priorities[candidate.class]
        if priorities then
            local need = ns.Decision.Evaluate(ns.classData, {
                isKnown = ns.Compat.IsKnown,
                settings = db,
                priorities = priorities,
            }, {
                level = candidate.level,
                isGroup = candidate.isGroup,
                auras = ns.Auras.Read(candidate.unit),
            })
            if need then
                candidate.need = need
                if db.displayMode == "range" then
                    candidate.inRange = ns.Compat.InRange(need.single.id, candidate.unit)
                end
                rows[#rows + 1] = candidate
            end
        end
    end
    table.sort(rows, ns.Decision.Compare)
    return rows
end

local dirty, sinceScan, sinceTick = true, 0, 0

local function scan()
    dirty, sinceScan, sinceTick = false, 0, 0
    ns.MainFrame.Render(buildRows())
end

function ns.RequestScan() dirty = true end

function ns.OnSettingsChanged()
    ns.Nameplates.Apply()
    scan()
end

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------

local NAMEPLATE_HINT = "les joueurs hors groupe ne sont détectés que via les barres de nom alliées, actuellement désactivées : touche Maj+V ou /fb plaques."

local function warnNameplates()
    if ns.db.includeStrangers and not ns.db.hiddenPlates and not ns.Compat.FriendlyNameplatesShown() then
        say(NAMEPLATE_HINT)
    end
end

local function toggleNameplates()
    if InCombatLockdown() then
        say("impossible pendant le combat.")
        return
    end
    local shown = not ns.Compat.FriendlyNameplatesShown()
    ns.Compat.SetFriendlyNameplates(shown)
    say(shown and "barres de nom alliées activées." or "barres de nom alliées désactivées.")
    ns.RequestScan()
end
ns.ToggleNameplates = toggleNameplates

-- Bilan du scan : pourquoi la liste est (ou non) vide.
local function debugScan()
    local candidates, rejected = ns.Scanner.Collect(ns.db.includeStrangers)
    local group, strangers = 0, 0
    for _, c in ipairs(candidates) do
        if c.isGroup then group = group + 1 else strangers = strangers + 1 end
    end
    local parts = {}
    for reason, count in pairs(rejected) do parts[#parts + 1] = reason .. "=" .. count end
    say(string.format("scan : %d candidats (%d groupe, %d hors groupe), %d à buffer ; rejetés : %s",
        #candidates, group, strangers, #buildRows(), #parts > 0 and table.concat(parts, ", ") or "aucun"))
    say("inconnus inclus : " .. (ns.db.includeStrangers and "oui" or "non")
        .. " ; barres de nom alliées : " .. (ns.Compat.FriendlyNameplatesShown() and "activées" or "DÉSACTIVÉES")
        .. " ; fenêtre masquée par /fb : " .. (ns.db.hidden and "oui" or "non"))
end

local function debugTarget()
    local unit = UnitExists("target") and "target" or "player"
    local _, class = UnitClass(unit)
    say("analyse de " .. (UnitName(unit) or "?") .. " (" .. tostring(class) .. ", niveau " .. UnitLevel(unit) .. ")")
    for _, raw in ipairs(ns.Compat.GetBuffs(unit)) do
        local info = raw.spellId and ns.SpellIndex[raw.spellId]
        print(string.format("  %s [%s] source=%s durée=%s fin=%s %s", tostring(raw.name), tostring(raw.spellId),
            tostring(raw.sourceUnit), tostring(raw.duration), tostring(raw.expirationTime),
            info and ("-> " .. info.family .. " puissance " .. info.power) or ""))
    end
    if not ns.classData then
        say("votre classe n'a aucun buff géré.")
        return
    end
    debugScan()
    local need = ns.Decision.Evaluate(ns.classData, {
        isKnown = ns.Compat.IsKnown, settings = ns.db, priorities = ns.db.priorities[class],
    }, { level = UnitLevel(unit), isGroup = UnitInParty(unit) or UnitInRaid(unit) or UnitIsUnit(unit, "player"), auras = ns.Auras.Read(unit) })
    if need then
        say(string.format("décision : %s (%s)%s", ns.SpellLabel(need.single), need.reason,
            need.group and (" / groupe : " .. ns.SpellLabel(need.group)) or ""))
    else
        say("décision : rien à faire.")
    end
end

local function toggleWindow()
    if InCombatLockdown() then
        say("impossible pendant le combat.")
        return
    end
    ns.db.hidden = not ns.db.hidden
    say(ns.db.hidden and "fenêtre masquée (/fb pour la réafficher)." or "fenêtre affichée.")
    scan()
end

SLASH_FRIENDLYBUFFER1 = "/fb"
SLASH_FRIENDLYBUFFER2 = "/friendlybuffer"
SlashCmdList.FRIENDLYBUFFER = function(input)
    local cmd = strtrim(input or ""):lower()
    if cmd == "" then
        toggleWindow()
    elseif cmd == "options" or cmd == "config" then
        ns.Options.Open()
    elseif cmd == "debug" then
        debugTarget()
    elseif cmd == "reset" then
        ns.MainFrame.ResetPosition()
    elseif cmd == "plaques" or cmd == "nameplates" then
        toggleNameplates()
    else
        say("/fb (afficher/masquer), /fb options, /fb debug (analyse la cible), /fb plaques (barres de nom alliées), /fb reset (position)")
    end
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

local events = CreateFrame("Frame")

local SCAN_EVENTS = {
    "UNIT_AURA", "GROUP_ROSTER_UPDATE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_TARGET_CHANGED", "UNIT_LEVEL", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_FLAGS",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local function onLogin()
    local _, class = UnitClass("player")
    ns.playerClass = class
    ns.classData = ns.Spells[class]
    FriendlyBufferCharDB = FriendlyBufferCharDB or {}
    ns.db = ns.Config.Load(FriendlyBufferCharDB, ns.classData)

    indexSpellNames()
    ns.MainFrame.Create()
    ns.Options.Create()

    if not ns.classData then
        say("votre classe n'a aucun buff géré ; l'addon reste inactif.")
        return
    end
    say("chargé (" .. (UnitClass("player")) .. "). /fb options pour les réglages, /fb debug en cas de souci.")
    ns.Nameplates.Apply()
    warnNameplates()

    for _, event in ipairs(SCAN_EVENTS) do events:RegisterEvent(event) end
    events:SetScript("OnUpdate", function(_, elapsed)
        sinceScan = sinceScan + elapsed
        sinceTick = sinceTick + elapsed
        if (dirty and sinceScan >= SCAN_THROTTLE) or sinceTick >= TICK then scan() end
    end)
    scan()
end

events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        onLogin()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.Nameplates.Apply()
        scan()
        ns.MainFrame.Flush()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        ns.Nameplates.Update(unit)
        ns.RequestScan()
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        ns.Nameplates.Removed(unit)
        ns.RequestScan()
    else
        ns.RequestScan()
    end
end)
