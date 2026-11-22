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

-- Nom et icône d'une famille : ceux du meilleur rang connu (à défaut, du premier).
function ns.FamilyName(fam)
    local rank = ns.Decision.BestRank(fam.ranks, ns.Compat.IsKnown) or fam.ranks[1]
    local name, icon = ns.Compat.GetSpellInfo(rank.id)
    return name or fam.key, icon
end

-- Remplit l'index nom -> famille et signale une fois les IDs absents du client.
local function indexSpellNames()
    local missing = {}
    for _, data in pairs(ns.Spells) do
        for _, families in ipairs({ data.families, data.personal.families }) do
            for key, fam in pairs(families) do
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

-- Résurrections : le joueur relevé reste mort tant qu'il n'a pas accepté (60 s au plus) ;
-- on ne le propose plus pendant ce temps.
local REZ_PENDING = 60
local REZ_WINDOW = 15     -- délai max entre le clic et la fin du sort
local rezzedUntil = {}    -- guid -> GetTime() de fin
local lastRezClick
local lastBuffClick       -- { row, time } : pour inscrire nos buffs lancés en combat

function ns.NoteClick(row)
    local now = GetTime()
    lastClick = { guid = row.guid, time = now }
    recentClicks[row.guid] = { time = now, row = row }
    if row.dead then lastRezClick = { guid = row.guid, time = now } else lastBuffClick = { row = row, time = now } end
end

local function onSpellSucceeded(unit, spellId)
    if unit ~= "player" or not lastRezClick or ns.Compat.IsSecret(spellId) then return end
    local isRez = false
    for _, rank in ipairs((ns.Resurrection[ns.playerClass] or { ranks = {} }).ranks) do
        if rank.id == spellId then isRez = true end
    end
    if not isRez or GetTime() - lastRezClick.time > REZ_WINDOW then return end
    rezzedUntil[lastRezClick.guid] = GetTime() + REZ_PENDING
    lastRezClick = nil
    ns.RequestScan()
end

local function rezPending(candidate, now)
    local untilTime = rezzedUntil[candidate.guid]
    if untilTime and untilTime <= now then rezzedUntil[candidate.guid], untilTime = nil, nil end
    return untilTime ~= nil or (UnitHasIncomingResurrection ~= nil and UnitHasIncomingResurrection(candidate.unit) == true)
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

-- Compteurs par buff sur les membres du groupe (joueurs vivants, à portée ou non) :
-- clé -> { missing, total }. Les bénédictions (une seule par paladin) n'ont qu'un compteur, "*".
-- Retourne les familles manquantes de la cible (pour la grille de combat).
local function count(counters, ctx, target)
    local missing, wanted = ns.Decision.Missing(ns.classData, ctx, target)
    local result = missing
    if ns.classData.mode == "exclusive" then missing, wanted = { ["*"] = next(missing) and true or nil }, { ["*"] = true } end
    for key in pairs(wanted) do
        local c = counters[key] or { missing = 0, total = 0 }
        counters[key] = c
        c.total = c.total + 1
        if missing[key] then c.missing = c.missing + 1 end
    end
    return result
end

-- Portée d'une version de groupe : le groupe du raid, ou la classe (bénédictions supérieures).
local function groupScope(row)
    if ns.classData.mode == "exclusive" then return row.class end
    return row.subgroup
end

-- stats (optionnel) : compte les joueurs écartés, pour /fb debug.
-- Retourne aussi les GUIDs des joueurs vus qui n'ont besoin de rien, les compteurs par buff et,
-- par GUID des membres du groupe, les familles qui leur manquent (grille de combat).
local function buildRows(stats)
    local rows, satisfied, counters, groupMissing = {}, {}, {}, {}
    if not ns.classData then return rows, satisfied, counters, groupMissing end
    local db = ns.db
    local now = GetTime()
    local ctx = { isKnown = ns.Compat.IsKnown, settings = db }
    -- Classe sans buff à poser sur autrui : seul le joueur lui-même compte (buffs personnels).
    local others = ns.hasFamilies
    local rez = db.resurrect and ns.Resurrection[ns.playerClass]
    ns.Coord.Prepare()
    for _, candidate in ipairs(ns.Scanner.Collect(others and db.includeStrangers, others and db.includePets, rez ~= nil)) do
        local isSelf = UnitIsUnit(candidate.unit, "player")
        if candidate.dead then
            local need = not db.ignored[candidate.name] and ns.Decision.Resurrect(rez, ns.Compat.IsKnown)
            if need and rezPending(candidate, now) then
                satisfied[candidate.guid] = true
            elseif need and ns.Compat.InRange(need.single.id, candidate.unit) ~= false then
                candidate.need = need
                candidate.blocked = isBlocked(candidate.guid, now)
                rows[#rows + 1] = candidate
            end
        elseif (others or isSelf) and not db.ignored[candidate.name] then
            candidate.auras = ns.Auras.Read(candidate.unit)
        end
        -- auras nil : joueur jamais lu hors combat, état inconnu, ni proposé ni compté.
        if candidate.auras then
            candidate.profile = ns.Specs.ProfileFor(candidate)
            local target = { level = candidate.level, isGroup = candidate.isGroup, auras = candidate.auras }
            ctx.priorities = db.priorities[candidate.profile]
            ctx.assigned = ns.Coord.Assigned(candidate.profile, ctx.priorities)
            -- En raid, un autre joueur de ma classe s'occupe de ce groupe.
            local otherPeer = others and candidate.isGroup and not isSelf and ns.Coord.OtherSubgroup(candidate.subgroup)
            if others and candidate.isGroup and not candidate.isPet then
                local missing = count(counters, ctx, target)
                groupMissing[candidate.guid] = not otherPeer and missing or {}
            end
            local need
            if otherPeer then
                if stats then stats.otherPeer = stats.otherPeer + 1 end
            else
                need = ns.Decision.Evaluate(ns.classData, ctx, target)
            end
            ctx.assigned = nil
            -- Soi-même : à défaut, un buff personnel.
            if not need and isSelf then
                ctx.priorities = db.personal
                need = ns.Decision.Evaluate(ns.classData.personal, ctx, target)
            end
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
    if db.groupBuffs then ns.Decision.ApplyGroupMin(rows, db.groupMin, groupScope) end
    table.sort(rows, ns.Decision.Compare)
    return rows, satisfied, counters, groupMissing
end

-- Libellé d'un compteur : nom (ou icône) du buff, déjà posés / total.
function ns.CounterLabel(key, c, withIcon)
    local name, icon = L["Blessings"], nil
    if key ~= "*" then name, icon = ns.FamilyName(ns.classData.families[key]) end
    local prefix = (withIcon and icon) and ("|T" .. icon .. ":14|t ") or (name .. " ")
    return prefix .. (c.total - c.missing) .. "/" .. c.total
end

-- Compteurs triés par clé : { {key, c}, ... } ; seulement ceux où il manque quelque chose si onlyMissing.
function ns.SortedCounters(counters, onlyMissing)
    local list = {}
    for key, c in pairs(counters or {}) do
        if not onlyMissing or c.missing > 0 then list[#list + 1] = { key = key, c = c } end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

local dirty, sinceScan, sinceTick = true, 0, 0
local lastRows = {}

-- Combat : nos buffs n'apparaissent pas sur la cible (auras secrètes), on les inscrit nous-mêmes.
local CAST_WINDOW = 2     -- délai max entre le clic et la réussite du sort
local function noteBuffCast(spellId)
    local click = lastBuffClick
    if not click or not ns.classData or not ns.Compat.AurasSecret() or GetTime() - click.time > CAST_WINDOW then return end
    local row = click.row
    local fam = ns.classData.families[row.need.family] or ns.classData.personal.families[row.need.family]
    local secret = ns.Compat.IsSecret(spellId)
    local info = not secret and ns.SpellIndex[spellId]
    -- Sort secret : on suppose la version individuelle du buff cliqué ; sinon il doit en faire partie.
    if not fam or (not secret and not (info and info.family == row.need.family)) then return end
    lastBuffClick = nil
    local isGroup = info and info.group
    local duration = isGroup and (fam.groupDuration or fam.duration) or fam.duration
    spellId = secret and row.need.single.id or spellId
    ns.Auras.NoteCast(row.guid, spellId, duration)
    if isGroup then
        for _, other in ipairs(lastRows) do
            if other.guid ~= row.guid and other.need.family == row.need.family and groupScope(other) == groupScope(row) then
                ns.Auras.NoteCast(other.guid, spellId, duration)
            end
        end
    end
    ns.RequestScan()
end

local function currentContext()
    if IsInRaid() then return "raid" end
    if IsInGroup() then return "party" end
    return "solo"
end

local function scan()
    dirty, sinceScan, sinceTick = false, 0, 0
    if ns.classData and ns.db.contextPresets and ns.Config.SwitchContext(ns.db, ns.classData, currentContext()) then
        say(string.format(L["priorities in use: %s."], ns.Config.CONTEXTS[ns.db.context]))
        ns.Options.Refresh()
    end
    local rows, satisfied, counters, groupMissing = buildRows()
    lastRows = rows
    ns.counters, ns.groupMissing = counters, groupMissing
    ns.BuffGrid.Update()
    ns.MainFrame.Render(rows, doneRows(rows, satisfied, GetTime()), counters)
    if ns.db.hiddenPlates then ns.Nameplates.Refresh() end
    ns.Specs.Update()
end

function ns.RequestScan() dirty = true end

function ns.OnSettingsChanged()
    ns.Nameplates.Apply()
    ns.Dispel.Refresh()
    ns.BuffGrid.Refresh()
    ns.Minimap.Refresh()
    scan()
end

---------------------------------------------------------------------------
-- Composants des buffs de groupe
---------------------------------------------------------------------------

local reagentCounts = {}  -- itemId -> dernier décompte vu

-- Prévient quand un composant passe sous le seuil, puis à chaque nouvelle baisse.
local function checkReagents()
    local limit = ns.db.reagentWarn
    if limit <= 0 or not ns.db.groupBuffs then return end
    for _, item in ipairs(ns.Decision.Reagents(ns.classData, ns.Compat.IsKnown)) do
        local count, last = ns.Compat.ItemCount(item), reagentCounts[item]
        reagentCounts[item] = count
        if count <= limit and (not last or count < last) then
            say(string.format(L["only %d left: %s."], count, ns.Compat.ItemName(item) or L["group buff reagents"]))
        end
    end
end

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------

local NAMEPLATE_HINT = L["players outside your group can only be detected through friendly nameplates, which are disabled: press Shift+V, type /fb plates, or enable the 'discreet friendly nameplates' option."]

local function warnNameplates()
    if ns.hasFamilies and ns.db.includeStrangers and not ns.db.hiddenPlates and not ns.Compat.FriendlyNameplatesShown() then
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
    local candidates, rejected = ns.Scanner.Collect(ns.db.includeStrangers, ns.db.includePets)
    local group, strangers = 0, 0
    for _, c in ipairs(candidates) do
        if c.isGroup then group = group + 1 else strangers = strangers + 1 end
    end
    local parts = {}
    for reason, count in pairs(rejected) do parts[#parts + 1] = reason .. "=" .. count end
    local stats = { outOfRange = 0, otherPeer = 0 }
    local count = #buildRows(stats)
    say(string.format(L["scan: %d candidates (%d in group, %d outside), %d to buff, %d out of range; rejected: %s"],
        #candidates, group, strangers, count, stats.outOfRange, #parts > 0 and table.concat(parts, ", ") or L["none"]))
    local coordinated, index = ns.Coord.Status()
    if coordinated > 1 then
        say(string.format(L["coordination: %d players of your class with FriendlyBuffer (you are #%d); %d left to them"],
            coordinated, index or 0, stats.otherPeer))
    end
    local function yesNo(value) return value and L["yes"] or L["no"] end
    say(string.format(L["strangers included: %s; friendly nameplates: %s; window hidden by /fb: %s"],
        yesNo(ns.db.includeStrangers),
        ns.Compat.FriendlyNameplatesShown() and L["enabled"] or L["DISABLED"],
        yesNo(ns.db.hidden)))
end

local function debugTarget()
    local unit = UnitExists("target") and "target" or "player"
    -- Diagnostic de dissipation avant le reste : il fonctionne aussi en combat (filtre du client).
    if ns.Dispels[ns.playerClass] then
        local readable, combat = ns.Dispel.Diagnose(unit)
        local name = UnitName(unit)
        if not name or ns.Compat.IsSecret(name) then name = "?" end
        say(string.format(L["dispel on %s: debuff to remove %s; combat filter: %s"], name,
            readable and L["yes"] or L["no"], combat == nil and L["unavailable"] or (combat and L["yes"] or L["no"])))
        print("  " .. ns.Dispel.Dump(unit))
        for _, line in ipairs(ns.Dispel.Probe(unit)) do print("  " .. line) end
        for _, line in ipairs(ns.Dispel.ProbeIds(unit)) do print("  " .. line) end
    end
    if ns.Compat.AurasSecret() then
        say(L["not possible during combat."])
        return
    end
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
    local profile = ns.Specs.ProfileFor({ unit = unit, guid = UnitGUID(unit), class = class, level = UnitLevel(unit) })
    say(string.format(L["priorities used: %s"], ns.Specs.Label(profile)))
    local need = ns.Decision.Evaluate(ns.classData, {
        isKnown = ns.Compat.IsKnown, settings = ns.db, priorities = ns.db.priorities[profile],
    }, { level = UnitLevel(unit), isGroup = UnitInParty(unit) or UnitInRaid(unit) or UnitIsUnit(unit, "player"), auras = ns.Auras.Read(unit) })
    if need then
        say(string.format(L["decision: %s (%s)"], ns.SpellLabel(need.single), ns.MainFrame.ReasonLabel(need.reason))
            .. (need.group and string.format(L[" / group: %s"], ns.SpellLabel(need.group)) or ""))
    else
        say(L["decision: nothing to do."])
    end
end

-- Ready check : rappelle ce qui manque au groupe.
local function onReadyCheck()
    if not ns.db.readyCheck or not ns.hasFamilies or not ns.counters then return end
    local parts = {}
    for _, item in ipairs(ns.SortedCounters(ns.counters, true)) do parts[#parts + 1] = ns.CounterLabel(item.key, item.c) end
    if #parts > 0 then say(string.format(L["ready check, buffs missing: %s"], table.concat(parts, ", "))) end
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
ns.ToggleWindow = toggleWindow

-- Familles (de cible ou personnelles) désignées par leur clé, leur nom ou un bout de leur nom,
-- et les noms de toutes les familles de la classe.
local function findFamilies(text)
    text = text:lower()
    local matches, names, exact = {}, {}, nil
    for _, families in ipairs({ ns.classData.families, ns.classData.personal.families }) do
        for key, fam in pairs(families) do
            local name = ns.FamilyName(fam)
            names[#names + 1] = name
            if key == text or name:lower() == text then exact = fam end
            if text ~= "" and name:lower():find(text, 1, true) then matches[#matches + 1] = fam end
        end
    end
    table.sort(names)
    return exact and { exact } or matches, names
end

-- Active ou coupe un buff pour tout le monde (macro, raccourci).
local function toggleFamily(text)
    if not ns.classData then
        say(L["your class has no supported buff."])
        return
    end
    local matches, names = findFamilies(text)
    if #matches ~= 1 then
        say(string.format(L["/fb toggle <buff>, among: %s"], table.concat(names, ", ")))
        return
    end
    local fam = matches[1]
    local enabled = not ns.Config.FamilyEnabledForAll(ns.db, fam.key)
    ns.Config.SetFamilyForAll(ns.db, fam.key, enabled)
    say(string.format(enabled and L["%s: enabled for everyone."] or L["%s: disabled for everyone."], (ns.FamilyName(fam))))
    ns.Options.Refresh()
    scan()
end

-- Ignore un joueur (ou cesse de l'ignorer) ; sans nom, liste les ignorés.
local function toggleIgnore(name)
    local ignored = ns.db.ignored
    if name == "" then
        local names = {}
        for n in pairs(ignored) do names[#names + 1] = n end
        table.sort(names)
        say(string.format(L["ignored players: %s"], #names > 0 and table.concat(names, ", ") or L["none"]))
        return
    end
    ignored[name] = not ignored[name] or nil
    say(string.format(ignored[name] and L["%s is now ignored (same command to undo)."] or L["%s is no longer ignored."], name))
    scan()
end

-- Raccourci clavier (Bindings.xml) : un clic gauche sur la première ligne de la liste.
BINDING_HEADER_FRIENDLYBUFFER = "FriendlyBuffer"
_G["BINDING_NAME_CLICK FriendlyBufferRow1:LeftButton"] = L["Buff the first player of the list"]

SLASH_FRIENDLYBUFFER1 = "/fb"
SLASH_FRIENDLYBUFFER2 = "/friendlybuffer"
SlashCmdList.FRIENDLYBUFFER = function(input)
    -- L'argument garde sa casse (nom de joueur).
    local cmd, arg = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
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
    elseif cmd == "toggle" then
        toggleFamily(arg)
    elseif cmd == "ignore" then
        toggleIgnore(arg)
    elseif cmd == "dispel" or cmd == "dissipation" then
        ns.Dispel.ToggleMove()
    elseif cmd == "grid" or cmd == "grille" then
        ns.BuffGrid.ToggleMove()
    elseif cmd == "test" then
        ns.Preview.Toggle()
    else
        say(L["/fb (show/hide), /fb options, /fb debug (analyze your target), /fb plates (friendly nameplates), /fb reset (position)"])
        say(L["/fb toggle <buff> (on/off for everyone), /fb ignore <name> (ignore or stop ignoring a player; no name: list)"])
        say(L["/fb dispel (move the dispel window)"])
        say(L["/fb grid (move the combat buff grid)"])
        say(L["/fb test (simulate combat with fake players)"])
    end
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

local events = CreateFrame("Frame")

local SCAN_EVENTS = {
    "UNIT_AURA", "GROUP_ROSTER_UPDATE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_TARGET_CHANGED", "UNIT_LEVEL", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_FLAGS",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UI_ERROR_MESSAGE", "INSPECT_READY",
    "CHARACTER_POINTS_CHANGED", "BAG_UPDATE_DELAYED", "READY_CHECK", "UNIT_SPELLCAST_SUCCEEDED", "CHAT_MSG_ADDON",
}

-- Priorités de chaque personnage, pour les copier d'un personnage à l'autre (Options).
function ns.CharKey()
    return (UnitName("player") or "?") .. " - " .. (GetRealmName and GetRealmName() or "")
end

local function saveCharacter()
    if not ns.db or not ns.classData then return end
    FriendlyBufferDB.chars[ns.CharKey()] = { class = ns.playerClass, priorities = ns.db.priorities, personal = ns.db.personal }
end

local function onLogin()
    local _, class = UnitClass("player")
    ns.playerClass = class
    ns.classData = ns.Spells[class]
    ns.hasFamilies = ns.classData ~= nil and next(ns.classData.families) ~= nil
    FriendlyBufferCharDB = FriendlyBufferCharDB or {}
    FriendlyBufferDB = FriendlyBufferDB or {}
    FriendlyBufferDB.chars = FriendlyBufferDB.chars or {}
    ns.db = ns.Config.Load(FriendlyBufferCharDB, ns.classData)
    ns.Specs.Init(ns.db)

    indexSpellNames()
    ns.Auras.Init()
    ns.MainFrame.Create()
    ns.Dispel.Create()
    ns.Options.Create()
    events:RegisterEvent("PLAYER_LOGOUT")

    if not ns.classData then
        say(L["your class has no supported buff; the addon stays inactive."])
        return
    end
    say(string.format(L["loaded (%s). /fb options for settings, /fb debug if something is wrong."], (UnitClass("player"))))
    ns.Nameplates.Apply()
    warnNameplates()
    ns.Minimap.Create()
    ns.BuffGrid.Create()
    ns.Coord.Init()
    ns.Coord.Announce()

    for _, event in ipairs(SCAN_EVENTS) do events:RegisterEvent(event) end
    -- Nos propres inspections passent aussi par là : sans conséquence (simple délai).
    if NotifyInspect then hooksecurefunc("NotifyInspect", ns.Specs.OnForeignInspect) end
    events:SetScript("OnUpdate", function(_, elapsed)
        sinceScan = sinceScan + elapsed
        sinceTick = sinceTick + elapsed
        ns.Coord.Tick()
        if (dirty and sinceScan >= SCAN_THROTTLE) or sinceTick >= TICK then scan() end
    end)
    scan()
end

events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, unit, arg2, ...)
    if event == "PLAYER_LOGIN" then
        onLogin()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.Nameplates.Apply() -- entrée / sortie d'instance
        ns.RequestScan()
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.MainFrame.EnterCombat()
        ns.RequestScan()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.MainFrame.LeaveCombat()
        ns.Nameplates.Apply()
        scan()
        ns.MainFrame.Flush()
    elseif event == "PLAYER_LOGOUT" then
        saveCharacter()
    elseif event == "BAG_UPDATE_DELAYED" then
        checkReagents()
    elseif event == "READY_CHECK" then
        scan()
        onReadyCheck()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        onSpellSucceeded(unit, (...)) -- unité, castGUID, spellId
        if unit == "player" then noteBuffCast((...)) end
    elseif event == "CHAT_MSG_ADDON" then
        ns.Coord.OnMessage(unit, arg2)
    elseif event == "UI_ERROR_MESSAGE" then
        onUIError(unit, arg2)
    elseif event == "INSPECT_READY" then
        ns.Specs.OnInspectReady(unit)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        ns.Nameplates.Update(unit)
        ns.RequestScan()
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        ns.Nameplates.Removed(unit)
        ns.RequestScan()
    else
        if event == "GROUP_ROSTER_UPDATE" or event == "SPELLS_CHANGED" then ns.Coord.Announce() end
        ns.RequestScan()
    end
end)
