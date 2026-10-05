-- Initialisation, événements, scan et commandes.
local ADDON, ns = ...
local L = ns.L

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
        say(string.format(L["unknown spells on this client, ignored: %s"], table.concat(missing, ", ")))
    end
end

---------------------------------------------------------------------------
-- Scan
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Obstacles : WoW n'a pas d'API de ligne de vue. On repère l'erreur « pas en vue »
-- qui suit un clic et on grise ce joueur quelques secondes.
---------------------------------------------------------------------------

local LOS_DURATION = 5    -- secondes pendant lesquelles le joueur reste grisé
local CLICK_WINDOW = 1.0  -- délai max entre le clic et l'erreur
local blockedUntil = {}   -- guid -> GetTime() de fin
local lastClick

-- Joueurs qu'on vient de buffer : affichés « OK » en bas de la liste pendant ns.db.doneDuration s,
-- pour enchaîner les clics au même endroit.
local CLICK_WATCH = 10    -- délai max entre le clic et la disparition du besoin
local recentClicks = {}   -- guid -> { time, row }
local doneUntil = {}      -- guid -> { untilTime, row }

function ns.NoteClick(row)
    local now = GetTime()
    lastClick = { guid = row.guid, time = now }
    recentClicks[row.guid] = { time = now, row = row }
end

-- Lignes « OK » à afficher sous `rows` (les joueurs qui ont encore besoin d'un buff).
-- `satisfied` : GUIDs vus pendant le scan et qui n'ont plus besoin de rien. Un joueur qui sort
-- simplement de la liste (hors de portée, barre de nom disparue) n'est pas « OK ».
local function doneRows(rows, satisfied, now)
    local needed = {}
    for _, row in ipairs(rows) do needed[row.guid] = true end
    for guid, click in pairs(recentClicks) do
        if satisfied[guid] then
            if ns.db.doneDuration > 0 then doneUntil[guid] = { untilTime = now + ns.db.doneDuration, row = click.row } end
            recentClicks[guid] = nil
        elseif now - click.time > CLICK_WATCH then
            recentClicks[guid] = nil
        end
    end
    local done = {}
    for guid, entry in pairs(doneUntil) do
        if entry.untilTime <= now or needed[guid] then
            doneUntil[guid] = nil
        else
            done[#done + 1] = entry
        end
    end
    -- Le plus récent en bas.
    table.sort(done, function(a, b) return a.untilTime < b.untilTime end)
    for i, entry in ipairs(done) do done[i] = entry.row end
    return done
end

local function onUIError(arg1, arg2)
    local message = type(arg2) == "string" and arg2 or arg1
    if message ~= SPELL_FAILED_LINE_OF_SIGHT or not lastClick then return end
    if GetTime() - lastClick.time > CLICK_WINDOW then return end
    blockedUntil[lastClick.guid] = GetTime() + LOS_DURATION
    lastClick = nil
    ns.RequestScan()
end

local function isBlocked(guid, now)
    local untilTime = blockedUntil[guid]
    if not untilTime then return false end
    if untilTime <= now then
        blockedUntil[guid] = nil
        return false
    end
    return true
end

-- stats (optionnel) : compte les joueurs écartés, pour /fb debug.
-- Retourne aussi les GUIDs des joueurs vus qui n'ont besoin de rien.
local function buildRows(stats)
    local rows, satisfied = {}, {}
    if not ns.classData then return rows, satisfied end
    local db = ns.db
    local now = GetTime()
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
            -- Hors de portée du sort : pas affiché (portée inconnue = affiché).
            if need and ns.Compat.InRange(need.single.id, candidate.unit) == false then
                if stats then stats.outOfRange = stats.outOfRange + 1 end
            elseif need then
                candidate.need = need
                candidate.blocked = isBlocked(candidate.guid, now)
                rows[#rows + 1] = candidate
            else
                satisfied[candidate.guid] = true
            end
        end
    end
    table.sort(rows, ns.Decision.Compare)
    return rows, satisfied
end

local dirty, sinceScan, sinceTick = true, 0, 0

local function scan()
    dirty, sinceScan, sinceTick = false, 0, 0
    local rows, satisfied = buildRows()
    ns.MainFrame.Render(rows, doneRows(rows, satisfied, GetTime()))
    if ns.db.hiddenPlates then ns.Nameplates.Refresh() end
end

function ns.RequestScan() dirty = true end

function ns.OnSettingsChanged()
    ns.Nameplates.Apply()
    scan()
end

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------

local NAMEPLATE_HINT = L["players outside your group can only be detected through friendly nameplates, which are disabled: press Shift+V, type /fb plates, or enable the 'discreet friendly nameplates' option."]

local function warnNameplates()
    if ns.db.includeStrangers and not ns.db.hiddenPlates and not ns.Compat.FriendlyNameplatesShown() then
        say(NAMEPLATE_HINT)
    end
end

local function toggleNameplates()
    if InCombatLockdown() then
        say(L["not possible during combat."])
        return
    end
    local shown = not ns.Compat.FriendlyNameplatesShown()
    ns.Compat.SetFriendlyNameplates(shown)
    say(shown and L["friendly nameplates enabled."] or L["friendly nameplates disabled."])
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
    local stats = { outOfRange = 0 }
    local count = #buildRows(stats)
    say(string.format(L["scan: %d candidates (%d in group, %d outside), %d to buff, %d out of range; rejected: %s"],
        #candidates, group, strangers, count, stats.outOfRange, #parts > 0 and table.concat(parts, ", ") or L["none"]))
    local function yesNo(value) return value and L["yes"] or L["no"] end
    say(string.format(L["strangers included: %s; friendly nameplates: %s; window hidden by /fb: %s"],
        yesNo(ns.db.includeStrangers),
        ns.Compat.FriendlyNameplatesShown() and L["enabled"] or L["DISABLED"],
        yesNo(ns.db.hidden)))
end

local function debugTarget()
    local unit = UnitExists("target") and "target" or "player"
    local _, class = UnitClass(unit)
    say(string.format(L["analysis of %s (%s, level %s)"], UnitName(unit) or "?", tostring(class), tostring(UnitLevel(unit))))
    for _, raw in ipairs(ns.Compat.GetBuffs(unit)) do
        local info = raw.spellId and ns.SpellIndex[raw.spellId]
        print(string.format("  %s [%s] source=%s duration=%s expiration=%s %s", tostring(raw.name), tostring(raw.spellId),
            tostring(raw.sourceUnit), tostring(raw.duration), tostring(raw.expirationTime),
            info and ("-> " .. info.family .. " power " .. info.power) or ""))
    end
    if not ns.classData then
        say(L["your class has no supported buff."])
        return
    end
    debugScan()
    local need = ns.Decision.Evaluate(ns.classData, {
        isKnown = ns.Compat.IsKnown, settings = ns.db, priorities = ns.db.priorities[class],
    }, { level = UnitLevel(unit), isGroup = UnitInParty(unit) or UnitInRaid(unit) or UnitIsUnit(unit, "player"), auras = ns.Auras.Read(unit) })
    if need then
        say(string.format(L["decision: %s (%s)"], ns.SpellLabel(need.single), ns.MainFrame.ReasonLabel(need.reason))
            .. (need.group and string.format(L[" / group: %s"], ns.SpellLabel(need.group)) or ""))
    else
        say(L["decision: nothing to do."])
    end
end

local function toggleWindow()
    if InCombatLockdown() then
        say(L["not possible during combat."])
        return
    end
    ns.db.hidden = not ns.db.hidden
    say(ns.db.hidden and L["window hidden (/fb to show it again)."] or L["window shown."])
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
    elseif cmd == "plates" or cmd == "plaques" or cmd == "nameplates" then
        toggleNameplates()
    else
        say(L["/fb (show/hide), /fb options, /fb debug (analyze your target), /fb plates (friendly nameplates), /fb reset (position)"])
    end
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

local events = CreateFrame("Frame")

local SCAN_EVENTS = {
    "UNIT_AURA", "GROUP_ROSTER_UPDATE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_TARGET_CHANGED", "UNIT_LEVEL", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_FLAGS",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UI_ERROR_MESSAGE",
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
        say(L["your class has no supported buff; the addon stays inactive."])
        return
    end
    say(string.format(L["loaded (%s). /fb options for settings, /fb debug if something is wrong."], (UnitClass("player"))))
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
events:SetScript("OnEvent", function(_, event, unit, arg2)
    if event == "PLAYER_LOGIN" then
        onLogin()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.Nameplates.Apply()
        scan()
        ns.MainFrame.Flush()
    elseif event == "UI_ERROR_MESSAGE" then
        onUIError(unit, arg2)
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
