-- Grille de buffs de combat : une case par membre du groupe, préparée hors combat. Chaque case est
-- un bouton sécurisé lié à l'unité ; ses clics lancent les buffs prioritaires de ce joueur (clic
-- gauche : 1er, clic droit : 2e, Maj + clic gauche : 3e, Maj + clic droit : 4e). En combat WoW
-- interdit de montrer, masquer, déplacer ou réaffecter ces boutons : la grille entière apparaît à
-- l'entrée en combat, une case est transparente tant que rien ne manque, et ses icônes (simples
-- textures) affichent, serrées, les buffs manquants. Hors combat elle est masquée (la liste
-- principale fait ce travail).
local _, ns = ...
local L = ns.L

local BuffGrid = {}
ns.BuffGrid = BuffGrid

local MAX_UNITS = 40
local COLUMNS = 5          -- joueurs par ligne (un groupe du raid par ligne)
local GAP = 2              -- entre deux icônes, et marge intérieure de la case
local TILE_GAP = 4         -- entre deux cases
local OUT_OF_RANGE_ALPHA = 0.4
-- Clics d'une case, dans l'ordre des priorités : { attribut type, attribut macro, libellé }.
local CLICKS = {
    { "type1", "macrotext1", L["Left click: %s"] },
    { "type2", "macrotext2", L["Right click: %s"] },
    { "shift-type1", "shift-macrotext1", L["Shift + left click: %s"] },
    { "shift-type2", "shift-macrotext2", L["Shift + right click: %s"] },
}

local frame, anchor
local tiles = {}           -- une case par place : { unit, fake, order = { clés }, spells = { [clé] = rang }, icons }
local families = {}        -- clés des buffs connus
local layoutPending = false
-- Vrai dès PLAYER_REGEN_DISABLED : dernier instant où la grille peut encore être montrée.
local fighting = false
local previewing = false   -- cases remplies par la simulation (Preview)

local function active()
    return ns.db.buffGrid and ns.hasFamilies and #families > 0
end

function BuffGrid.Active() return frame ~= nil and active() end

local function moving() return anchor ~= nil and anchor:IsShown() end

local function wanted()
    return active() and (fighting or InCombatLockdown() or moving() or previewing)
end

local function iconOf(rank) return (select(2, ns.Compat.GetSpellInfo(rank.id))) end

---------------------------------------------------------------------------
-- Affichage (permis en combat : transparence, textures, textes)
---------------------------------------------------------------------------

-- ns.groupMissing : GUID -> { [famille] = true }, rempli par chaque scan (FriendlyBuffer.lua).
local function missingOf(tile)
    if tile.fake then return tile.fake.missing end
    local guid = UnitGUID(tile.unit)
    return guid and not ns.Compat.IsSecret(guid) and ns.groupMissing and ns.groupMissing[guid] or {}
end

function BuffGrid.Update()
    if not frame or not frame:IsShown() then return end
    local all = moving()
    for _, tile in ipairs(tiles) do
        if tile.unit or tile.fake then
            -- Icônes serrées : les buffs manquants, dans l'ordre des clics.
            local missing, shown, first = missingOf(tile), 0, nil
            for _, key in ipairs(tile.order) do
                if all or missing[key] then
                    shown = shown + 1
                    first = first or key
                    tile.icons[shown]:SetTexture(iconOf(tile.spells[key]))
                    tile.icons[shown]:SetAlpha(1)
                end
            end
            for i = shown + 1, #tile.icons do tile.icons[i]:SetAlpha(0) end
            if shown == 0 then
                tile:SetAlpha(0)
            else
                local far
                if tile.fake then far = tile.fake.far
                elseif not all then far = ns.Compat.InRange(tile.spells[first].id, tile.unit) == false end
                tile:SetAlpha(far and not all and OUT_OF_RANGE_ALPHA or 1)
            end
            local name = tile.fake and tile.fake.name or UnitName(tile.unit)
            if name and not ns.Compat.IsSecret(name) then tile.name:SetText(name) end
            local class = tile.fake and tile.fake.class or select(2, UnitClass(tile.unit))
            if class and not ns.Compat.IsSecret(class) then tile.name:SetTextColor(ns.Compat.ClassColor(class)) end
        end
    end
end

---------------------------------------------------------------------------
-- Cases : unités, positions et sorts (hors combat)
---------------------------------------------------------------------------

-- Buffs d'un profil de cible, dans l'ordre de ses priorités : au plus un par clic.
local function orderFor(profile)
    local order = {}
    for _, entry in ipairs(ns.db.priorities[profile] or {}) do
        local fam = ns.classData.families[entry.key]
        if entry.enabled and fam and ns.Decision.BestRank(fam.ranks, ns.Compat.IsKnown) and #order < #CLICKS then
            order[#order + 1] = entry.key
        end
    end
    return order
end

local function onEnter(tile)
    if tile:GetAlpha() == 0 or tile.fake or not tile.unit then return end
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    local name = UnitName(tile.unit)
    if name and not ns.Compat.IsSecret(name) then GameTooltip:AddLine(name) end
    for i, key in ipairs(tile.order) do
        GameTooltip:AddLine(string.format(CLICKS[i][3], ns.SpellLabel(tile.spells[key])), 1, 1, 1)
    end
    GameTooltip:Show()
end

local function createTile(index)
    local tile = CreateFrame("Button", "FriendlyBufferGrid" .. index, frame, "SecureActionButtonTemplate")
    tile:RegisterForClicks("AnyUp", "AnyDown")
    local bg = tile:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    local highlight = tile:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.15)
    tile.name = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tile.name:SetPoint("TOPLEFT", GAP, -GAP)
    tile.name:SetPoint("TOPRIGHT", -GAP, -GAP)
    tile.name:SetJustifyH("LEFT")
    tile.name:SetWordWrap(false)
    tile.icons = {}
    for i = 1, #CLICKS do
        local icon = tile:CreateTexture(nil, "ARTWORK")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetAlpha(0)
        tile.icons[i] = icon
    end
    tile:SetScript("OnEnter", onEnter)
    tile:SetScript("OnLeave", GameTooltip_Hide)
    tile:SetAlpha(0)
    tiles[index] = tile
    return tile
end

-- Sorts de la case ; unit nil : case simulée, qui ne lance rien.
local function setSpells(tile, unit)
    for _, click in ipairs(CLICKS) do
        tile:SetAttribute(click[1], nil)
        tile:SetAttribute(click[2], nil)
    end
    local level = unit and UnitLevel(unit)
    if not level or ns.Compat.IsSecret(level) then level = -1 end
    tile.spells = {}
    local order = {}
    for _, key in ipairs(tile.order) do
        local fam = ns.classData.families[key]
        local single = ns.Decision.BestRank(fam.ranks, ns.Compat.IsKnown, level)
        local group = ns.db.groupBuffs and fam.group and ns.Decision.BestRank(fam.group, ns.Compat.IsKnown, level)
        local rank = group or single
        if rank then
            order[#order + 1] = key
            tile.spells[key] = rank
            if unit then
                local click = CLICKS[#order]
                tile:SetAttribute(click[1], "macro")
                tile:SetAttribute(click[2], "/cast [@" .. unit .. "] " .. ns.CastString(rank))
            end
        end
    end
    tile.order = order
end

local function profileOf(unit)
    local _, class = UnitClass(unit)
    if not class or ns.Compat.IsSecret(class) then return nil end
    return ns.Specs.ProfileFor({ unit = unit, guid = UnitGUID(unit), class = class, level = UnitLevel(unit) })
end

local function layout()
    if fighting or InCombatLockdown() then
        layoutPending = true
        return
    end
    layoutPending = false
    families = {}
    for key, fam in pairs(ns.classData and ns.classData.families or {}) do
        if ns.Decision.BestRank(fam.ranks, ns.Compat.IsKnown) then families[#families + 1] = key end
    end
    if not active() then
        frame:Hide()
        return
    end
    local size = ns.db.buffGridSize
    local fontSize = math.max(8, math.floor(size / 2))
    local icons = math.min(#CLICKS, #families)
    local width = math.max(icons * (size + GAP) + GAP, 3 * size)
    local nameHeight = ns.db.buffGridNames and fontSize + 2 or 0
    local height = GAP + nameHeight + size + GAP
    previewing = ns.Preview.Active()
    local list = previewing and ns.Preview.Layout() or ns.Scanner.GroupLayout(COLUMNS)
    local rows = 1
    for i = 1, MAX_UNITS do
        local tile = tiles[i] or createTile(i)
        local entry = list[i]
        if entry then
            local index = entry.position - 1
            tile:SetSize(width, height)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", frame, "TOPLEFT", (index % COLUMNS) * (width + TILE_GAP),
                -math.floor(index / COLUMNS) * (height + TILE_GAP))
            rows = math.max(rows, math.floor(index / COLUMNS) + 1)
            tile.unit, tile.fake = entry.unit, entry.fake
            tile.name:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
            tile.name:SetShown(ns.db.buffGridNames)
            for j, icon in ipairs(tile.icons) do
                icon:SetSize(size, size)
                icon:ClearAllPoints()
                icon:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", GAP + (j - 1) * (size + GAP), GAP)
            end
            tile.order = orderFor(entry.fake and entry.fake.class or profileOf(entry.unit))
            setSpells(tile, entry.unit)
            tile:Show()
        elseif tiles[i] then
            tile.unit, tile.fake, tile.order = nil, nil, {}
            setSpells(tile, nil)
            tile:Hide()
        end
    end
    frame:SetSize(COLUMNS * (width + TILE_GAP) - TILE_GAP, rows * (height + TILE_GAP) - TILE_GAP)
    frame:SetShown(wanted())
    BuffGrid.Update()
end

function BuffGrid.Refresh()
    if frame then layout() end
end

-- Poignée de déplacement (/fb grid ou bouton des options), hors combat.
local function createAnchor()
    anchor = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    anchor:SetPoint("TOPLEFT", -4, 18)
    anchor:SetPoint("BOTTOMRIGHT", 4, -4)
    anchor:SetFrameStrata("HIGH")
    anchor:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    anchor:SetBackdropColor(0.1, 0.3, 0.6, 0.6)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function() if not InCombatLockdown() then frame:StartMoving() end end)
    anchor:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        ns.db.buffGridPoint = { point, relativePoint, x, y }
    end)
    local text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 6, -4)
    text:SetText(L["Buffs: drag, /fb grid when done"])
    anchor:Hide()
end

function BuffGrid.ToggleMove()
    if InCombatLockdown() then
        ns.Print(L["not possible during combat."])
        return
    end
    if not frame or not active() then
        ns.Print(L["the combat buff grid is off or your class has no buff for others."])
        return
    end
    anchor:SetShown(not anchor:IsShown())
    layout()
end

local function onEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        ns.Preview.OnCombat()
        if previewing then layout() end
        fighting = true
        if anchor:IsShown() then anchor:Hide() end
        frame:SetShown(active())
        BuffGrid.Update()
    elseif event == "PLAYER_REGEN_ENABLED" then
        fighting = false
        if layoutPending then layout() else frame:SetShown(wanted()) end
    else
        layout() -- groupe, sorts, niveaux, entrée en jeu
    end
end

function BuffGrid.Create()
    frame = CreateFrame("Frame", "FriendlyBufferGridFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    local p = ns.db.buffGridPoint
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 300, -100)
    end
    frame:Hide()
    createAnchor()

    local events = CreateFrame("Frame")
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_LEVEL", "INSPECT_READY" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", onEvent)
    layout()
end
