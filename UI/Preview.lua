-- Simulation (options, /fb test) : hors combat, la grille de combat et la fenêtre de dissipation
-- s'affichent comme en combat, avec de faux joueurs (nombre réglable, groupe ou raid) à qui il
-- manque des buffs et qui portent des débuffs à retirer. Les cases simulées ne lancent rien.
-- L'état change toutes les quelques secondes ; un vrai combat arrête la simulation.
local _, ns = ...
local L = ns.L

local Preview = {}
ns.Preview = Preview

local CHANGE_EVERY = 2     -- secondes entre deux changements de l'état simulé
local MISSING_CHANCE = 0.4
local DEBUFF_CHANCE = 0.3
local FAR_CHANCE = 0.15
local CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "PALADIN", "SHAMAN" }

local active = false
local players = {}
local ticker

function Preview.Active() return active end

-- Débuffs que nos sorts retirent : { {type, icon}, ... } (icône du sort qui le retire).
local function debuffKinds()
    local kinds = {}
    for _, spell in ipairs(ns.Decision.DispelSpells(ns.Dispels[ns.playerClass], ns.Compat.IsKnown)) do
        local _, icon = ns.Compat.GetSpellInfo(spell.rank.id)
        for dtype in pairs(spell.types) do kinds[#kinds + 1] = { type = dtype, icon = icon } end
    end
    table.sort(kinds, function(a, b) return a.type < b.type end)
    return kinds
end

-- Familles manquantes au hasard ; une seule bénédiction (mode exclusif).
local function rollMissing()
    local missing = {}
    if not ns.classData then return missing end
    local keys = {}
    for key in pairs(ns.classData.families) do keys[#keys + 1] = key end
    table.sort(keys)
    if ns.classData.mode == "exclusive" then
        if #keys > 0 and math.random() < MISSING_CHANCE then missing[keys[math.random(#keys)]] = true end
        return missing
    end
    for _, key in ipairs(keys) do
        if math.random() < MISSING_CHANCE then missing[key] = true end
    end
    return missing
end

local function rollDebuff(kinds)
    if #kinds == 0 or math.random() >= DEBUFF_CHANCE then return nil end
    return kinds[math.random(#kinds)]
end

local function generate()
    local kinds = debuffKinds()
    players = {}
    for i = 1, ns.db.previewCount do
        players[i] = {
            name = string.format(L["Player %d"], i), class = CLASSES[(i - 1) % #CLASSES + 1],
            missing = rollMissing(), debuff = rollDebuff(kinds), far = math.random() < FAR_CHANCE,
        }
    end
end

-- Même forme que Scanner.GroupLayout : { {position, fake}, ... } (5 par groupe, dans l'ordre).
function Preview.Layout()
    if #players ~= ns.db.previewCount then generate() end
    local list = {}
    for i, player in ipairs(players) do list[i] = { position = i, fake = player } end
    return list
end

local function refresh()
    ns.Dispel.Refresh()
    ns.BuffGrid.Refresh()
    ns.RequestScan() -- la liste principale laisse la place à la grille
    ns.Options.Refresh()
end

-- Un joueur au hasard change de buffs manquants ou de débuff.
local function change()
    if #players == 0 then return end
    local player = players[math.random(#players)]
    if math.random() < 0.5 then player.missing = rollMissing() else player.debuff = rollDebuff(debuffKinds()) end
    ns.Dispel.Request()
    ns.BuffGrid.Update()
end

function Preview.Start()
    if InCombatLockdown() then
        ns.Print(L["not possible during combat."])
        return
    end
    active = true
    generate()
    if not ticker then
        ticker = CreateFrame("Frame")
        local since = 0
        ticker:SetScript("OnUpdate", function(_, elapsed)
            if not active then return end
            since = since + elapsed
            if since >= CHANGE_EVERY then
                since = 0
                change()
            end
        end)
    end
    refresh()
end

-- Appelé aussi par chaque fenêtre au début d'un vrai combat, avant de se figer.
function Preview.Stop()
    if not active then return end
    active = false
    if InCombatLockdown() then return end
    refresh()
end

function Preview.Toggle()
    if active then Preview.Stop() else Preview.Start() end
end

-- Vrai combat : chaque fenêtre appelle ceci puis, si elle montrait la simulation, se remet sur
-- les vrais joueurs avant de se figer.
function Preview.OnCombat()
    if not active then return end
    active = false
    ns.Print(L["simulation stopped: combat started."])
end
