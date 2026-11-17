-- Coordination entre joueurs de FriendlyBuffer d'un même groupe (messages d'addon).
-- Paladins : une bénédiction attribuée à chacun par profil de cible. Autres classes, en raid :
-- les groupes du raid sont répartis entre les joueurs de la même classe.
-- Les fonctions marquées « pur » n'utilisent aucune API WoW (tests/).
local _, ns = ...

local Coord = {}
ns.Coord = Coord

local PREFIX = "FriendlyBuffer"
local PEER_TIMEOUT = 600    -- un joueur muet depuis 10 min est oublié
local HELLO_DELAY = 3       -- regroupe les annonces après un changement de groupe
local REPLY_INTERVAL = 10   -- au plus une réponse à un nouveau venu par intervalle

local peers = {}            -- guid -> { class, families = { clé = true }, seen }
local helloAt, lastReply = nil, 0
local players, myIndex = {}, nil   -- joueurs de ma classe dans le groupe (moi compris), triés
local assignedCache = {}

-- Pur : répartit les bénédictions. players = { {guid, families}, ... } triés ; order = clés
-- activées dans l'ordre de priorité. Chacun prend, à son tour, la première qu'il connaît et que
-- personne n'a prise. Retourne la clé de `me`, ou nil.
function Coord.Assign(list, order, me)
    local taken = {}
    for _, p in ipairs(list) do
        for _, key in ipairs(order) do
            if not taken[key] and p.families[key] then
                taken[key] = true
                if p.guid == me then return key end
                break
            end
        end
    end
    return nil
end

-- Pur : le groupe de raid `subgroup` revient-il au joueur n° `index` parmi `count` ?
function Coord.OwnsSubgroup(index, count, subgroup)
    return (subgroup - 1) % count == index - 1
end

-- Pur : "H:<guid>:<classe>:<clé,clé>".
function Coord.Encode(guid, class, families)
    local keys = {}
    for key in pairs(families) do keys[#keys + 1] = key end
    table.sort(keys)
    return "H:" .. guid .. ":" .. class .. ":" .. table.concat(keys, ",")
end

-- Pur : message reçu (non fiable) -> { guid, class, families } ou nil s'il est mal formé.
function Coord.Decode(text)
    if type(text) ~= "string" or #text > 250 then return nil end
    local guid, class, list = text:match("^H:(Player%-[%w%-]+):(%u+):([%w,]*)$")
    if not guid then return nil end
    local families = {}
    for key in list:gmatch("[^,]+") do families[key] = true end
    return { guid = guid, class = class, families = families }
end

---------------------------------------------------------------------------
-- Envoi et réception
---------------------------------------------------------------------------

local function enabled()
    return ns.db and ns.db.coordinate and ns.hasFamilies
end

local function knownFamilies()
    local families = {}
    for key, fam in pairs(ns.classData.families) do
        if ns.Decision.BestRank(fam.ranks, ns.Compat.IsKnown) then families[key] = true end
    end
    return families
end

local function channel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function send()
    helloAt = nil
    local chan = channel()
    local api = C_ChatInfo
    if not chan or not (api and api.SendAddonMessage) then return end
    pcall(api.SendAddonMessage, PREFIX, Coord.Encode(UnitGUID("player"), ns.playerClass, knownFamilies()), chan)
end

-- Annonce (différée) : connexion, changement de groupe, de sorts.
function Coord.Announce()
    if enabled() and not helloAt then helloAt = GetTime() + HELLO_DELAY end
end

function Coord.Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
end

function Coord.OnMessage(prefix, text)
    if ns.Compat.IsSecret(prefix) or prefix ~= PREFIX or ns.Compat.IsSecret(text) or not enabled() then return end
    local msg = Coord.Decode(text)
    if not msg or msg.guid == UnitGUID("player") then return end
    local isNew = peers[msg.guid] == nil
    peers[msg.guid] = { class = msg.class, families = msg.families, seen = GetTime() }
    -- Un nouveau venu ne nous connaît pas encore : on lui répond.
    if isNew and GetTime() - lastReply > REPLY_INTERVAL then
        lastReply = GetTime()
        Coord.Announce()
    end
    ns.RequestScan()
end

function Coord.Tick()
    if helloAt and GetTime() >= helloAt then send() end
end

---------------------------------------------------------------------------
-- Avant chaque scan
---------------------------------------------------------------------------

-- Liste les joueurs de ma classe dans le groupe qui ont l'addon (moi compris), triés par GUID :
-- tous obtiennent le même ordre, donc la même répartition.
function Coord.Prepare()
    players, myIndex, assignedCache = {}, nil, {}
    if not enabled() then return end
    local me = UnitGUID("player")
    local now = GetTime()
    for guid, peer in pairs(peers) do
        if now - peer.seen > PEER_TIMEOUT then peers[guid] = nil end
    end
    players[1] = { guid = me, families = knownFamilies() }
    for _, unit in ipairs(ns.Scanner.GroupUnits()) do
        local guid = UnitGUID(unit)
        local peer = guid and peers[guid]
        if peer and peer.class == ns.playerClass and UnitIsConnected(unit) then
            players[#players + 1] = { guid = guid, families = peer.families }
        end
    end
    table.sort(players, function(a, b) return a.guid < b.guid end)
    for i, p in ipairs(players) do
        if p.guid == me then myIndex = i end
    end
end

-- Bénédiction attribuée pour ce profil de cible (paladins), ou nil (seul paladin de l'addon).
function Coord.Assigned(profile, priorities)
    if #players < 2 or ns.classData.mode ~= "exclusive" or not priorities then return nil end
    if assignedCache[profile] == nil then
        local order = {}
        for _, entry in ipairs(priorities) do
            if entry.enabled then order[#order + 1] = entry.key end
        end
        assignedCache[profile] = Coord.Assign(players, order, UnitGUID("player")) or false
    end
    return assignedCache[profile] or nil
end

-- En raid, ce groupe revient-il à un autre joueur de ma classe ? (classes autres que paladin)
function Coord.OtherSubgroup(subgroup)
    if #players < 2 or not myIndex or not subgroup or not IsInRaid() or ns.classData.mode == "exclusive" then return false end
    return not Coord.OwnsSubgroup(myIndex, #players, subgroup)
end

-- Pour /fb debug : nombre de joueurs de ma classe coordonnés (moi compris), mon rang.
function Coord.Status()
    return #players, myIndex
end
