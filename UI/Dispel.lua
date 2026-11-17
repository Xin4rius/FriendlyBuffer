-- Fenêtre de dissipation : une case par membre du groupe, qui n'apparaît que lorsqu'il porte un
-- débuff que l'on peut retirer. Ni fond ni cadre : en combat, seules les cases utiles se voient.
--
-- Chaque case est un bouton sécurisé lié à une unité (player, partyN, raidN). Son sort ne dépend
-- pas du débuff (clic gauche / droit = 1er / 2e sort de dissipation de la classe), donc rien n'est
-- à réaffecter en combat. En raid, une ligne par groupe. Hors combat les cases vides sont masquées ;
-- en combat (Show / Hide interdits sur les boutons sécurisés), elles restent en place, transparentes.
local _, ns = ...
local L = ns.L

local Dispel = {}
ns.Dispel = Dispel

local MAX_SLOTS = 40
local COLUMNS = 5
local GAP = 3
local THROTTLE = 0.1      -- délai minimum entre deux mises à jour déclenchées par événement
local TICK = 0.5          -- rafraîchissement périodique (portée)
local OUT_OF_RANGE_ALPHA = 0.4

local TYPE_COLORS = {
    Magic = { 0.2, 0.6, 1 },
    Curse = { 0.6, 0, 1 },
    Disease = { 0.6, 0.4, 0 },
    Poison = { 0, 0.6, 0 },
}
local UNKNOWN_COLOR = { 0.8, 0.8, 0.8 }

local frame, anchor
local slots = {}
local spells = {}         -- Decision.DispelSpells : { {key, types, rank}, ... }
local byUnit = {}         -- unité -> case
local dirty, layoutPending, since = true, false, 0
-- Vrai dès PLAYER_REGEN_DISABLED : le verrou de combat n'est pas encore posé, mais les cases
-- montrées à cet instant ne doivent plus être masquées.
local fighting = false

local function active()
    return ns.db.dispel and #spells > 0
end

---------------------------------------------------------------------------
-- Lecture
---------------------------------------------------------------------------

-- Débuff à retirer sur l'unité : présent, icône, type. Hors combat on lit les débuffs et on garde
-- ceux que nos sorts retirent ; quand les auras sont secrètes, on s'en remet au filtre du client.
local function read(unit)
    if not UnitExists(unit) or UnitIsDeadOrGhost(unit) or not UnitCanAssist("player", unit) then return false end
    if ns.Compat.AurasSecret() then return ns.Compat.DispellableSecret(unit) end
    for _, debuff in ipairs(ns.Compat.GetDebuffs(unit)) do
        if ns.Decision.DispelIndex(spells, debuff.dispelName) then return true, debuff.icon, debuff.dispelName end
    end
    return false
end

-- Pour /fb debug : lecture normale et lecture « combat » sur une unité.
function Dispel.Diagnose(unit)
    local normal = false
    if not ns.Compat.AurasSecret() then normal = read(unit) end
    return normal, ns.Compat.DispellableSecret(unit)
end

---------------------------------------------------------------------------
-- Affichage
---------------------------------------------------------------------------

local function paint(slot)
    local unit = slot.unit
    local present, icon, dtype = read(unit)
    slot.present = present == true
    slot.dtype = dtype
    if slot.present then
        pcall(slot.icon.SetTexture, slot.icon, icon) -- icône éventuellement secrète : acceptée par SetTexture
        local c = TYPE_COLORS[dtype] or UNKNOWN_COLOR
        slot.border:SetColorTexture(c[1], c[2], c[3], 1)
        local name = UnitName(unit)
        if name and not ns.Compat.IsSecret(name) then slot.name:SetText(name) end
        local _, class = UnitClass(unit)
        if class and not ns.Compat.IsSecret(class) then slot.name:SetTextColor(ns.Compat.ClassColor(class)) end
        slot.name:SetShown(ns.db.dispelNames)
        local inRange = ns.Compat.InRange(spells[1].rank.id, unit)
        slot:SetAlpha(inRange == false and OUT_OF_RANGE_ALPHA or 1)
    else
        slot:SetAlpha(0)
    end
    if not fighting and not InCombatLockdown() then slot:SetShown(slot.present or (anchor and anchor:IsShown())) end
end

local function update()
    dirty, since = false, 0
    if not frame or not active() then return end
    for _, slot in ipairs(slots) do
        if slot.unit then paint(slot) end
    end
end

function Dispel.Request() dirty = true end

---------------------------------------------------------------------------
-- Cases : unités, positions et sorts (hors combat)
---------------------------------------------------------------------------

local function macro(unit, index)
    local spell = spells[index] or spells[1]
    return "/cast [@" .. unit .. "] " .. ns.CastString(spell.rank)
end

-- { {unit, position}, ... } ; en raid, position = (groupe - 1) * 5 + rang dans le groupe.
local function roster()
    local list = {}
    if IsInRaid() then
        local filled = {}
        for i = 1, GetNumGroupMembers() do
            local _, _, subgroup = GetRaidRosterInfo(i)
            subgroup = subgroup or 1
            filled[subgroup] = (filled[subgroup] or 0) + 1
            list[#list + 1] = { unit = "raid" .. i, position = (subgroup - 1) * COLUMNS + filled[subgroup] }
        end
    else
        list[1] = { unit = "player", position = 1 }
        if IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do list[#list + 1] = { unit = "party" .. i, position = i + 1 } end
        end
    end
    return list
end

local function layout()
    if fighting or InCombatLockdown() then
        layoutPending = true
        return
    end
    layoutPending = false
    spells = ns.Decision.DispelSpells(ns.Dispels[ns.playerClass], ns.Compat.IsKnown)
    if not active() then
        frame:Hide()
        return
    end
    local size = ns.db.dispelSize
    byUnit = {}
    local list = roster()
    local rows = 1
    for i, slot in ipairs(slots) do
        local entry = list[i]
        slot:SetSize(size, size)
        slot.name:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", math.max(8, math.floor(size / 3)), "OUTLINE")
        if entry then
            local index = entry.position - 1
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", frame, "TOPLEFT", (index % COLUMNS) * (size + GAP), -math.floor(index / COLUMNS) * (size + GAP))
            rows = math.max(rows, math.floor(index / COLUMNS) + 1)
            slot.unit = entry.unit
            byUnit[entry.unit] = slot
            slot:SetAttribute("type1", "macro")
            slot:SetAttribute("macrotext1", macro(entry.unit, 1))
            slot:SetAttribute("type2", "macro")
            slot:SetAttribute("macrotext2", macro(entry.unit, 2))
        else
            slot.unit = nil
            slot.present = false
            slot:SetAttribute("type1", nil)
            slot:SetAttribute("type2", nil)
            slot:Hide()
        end
    end
    frame:SetSize(COLUMNS * (size + GAP) - GAP, rows * (size + GAP) - GAP)
    frame:Show()
    update()
end

function Dispel.Refresh()
    if frame then layout() end
end

---------------------------------------------------------------------------
-- Création
---------------------------------------------------------------------------

local function onEnter(slot)
    if not slot.present or not slot.unit then return end
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    local name = UnitName(slot.unit)
    if name and not ns.Compat.IsSecret(name) then GameTooltip:AddLine(name) end
    if not ns.Compat.AurasSecret() then
        for _, debuff in ipairs(ns.Compat.GetDebuffs(slot.unit)) do
            if ns.Decision.DispelIndex(spells, debuff.dispelName) then
                local c = TYPE_COLORS[debuff.dispelName] or UNKNOWN_COLOR
                GameTooltip:AddLine(debuff.name, c[1], c[2], c[3])
            end
        end
    end
    GameTooltip:AddLine(string.format(L["Left click: %s"], ns.SpellLabel(spells[1].rank)), 1, 1, 1)
    if spells[2] then GameTooltip:AddLine(string.format(L["Right click: %s"], ns.SpellLabel(spells[2].rank)), 1, 1, 1) end
    GameTooltip:Show()
end

local function createSlot(index)
    local slot = CreateFrame("Button", "FriendlyBufferDispel" .. index, frame, "SecureActionButtonTemplate")
    slot:RegisterForClicks("AnyUp", "AnyDown")
    -- Bordure = fond coloré par le type de débuff, l'icône par-dessus avec une marge.
    slot.border = slot:CreateTexture(nil, "BACKGROUND")
    slot.border:SetAllPoints()
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 2, -2)
    slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local highlight = slot:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(slot.icon)
    highlight:SetColorTexture(1, 1, 1, 0.2)
    slot.name = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slot.name:SetPoint("BOTTOMLEFT", 1, 1)
    slot.name:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.name:SetWordWrap(false)
    slot:SetScript("OnEnter", onEnter)
    slot:SetScript("OnLeave", GameTooltip_Hide)
    slot:SetAlpha(0)
    slot:Hide()
    return slot
end

-- Poignée de déplacement (/fb dispel ou bouton des options), hors combat.
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
        ns.db.dispelPoint = { point, relativePoint, x, y }
    end)
    local text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 6, -4)
    text:SetText(L["Dispels: drag, /fb dispel when done"])
    anchor:Hide()
end

function Dispel.ToggleMove()
    if not frame then
        ns.Print(L["your class has no dispel."])
        return
    end
    if InCombatLockdown() then
        ns.Print(L["not possible during combat."])
        return
    end
    if #spells == 0 then
        ns.Print(L["your class has no dispel."])
        return
    end
    anchor:SetShown(not anchor:IsShown())
    layout()
end

local function onEvent(_, event, unit)
    if event == "UNIT_AURA" then
        if byUnit[unit] then dirty = true end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Dernier instant où les cases peuvent encore être montrées : toutes, transparentes si vides.
        fighting = true
        if anchor:IsShown() then anchor:Hide() end
        for _, slot in ipairs(slots) do
            if slot.unit and active() then slot:Show() end
        end
        update()
    elseif event == "PLAYER_REGEN_ENABLED" then
        fighting = false
        if layoutPending then layout() else update() end
    else
        layout() -- groupe, sorts, entrée en jeu
    end
end

function Dispel.Create()
    if not ns.Dispels[ns.playerClass] then return end
    frame = CreateFrame("Frame", "FriendlyBufferDispelFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    local p = ns.db.dispelPoint
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", -300, -100)
    end
    for i = 1, MAX_SLOTS do slots[i] = createSlot(i) end
    createAnchor()

    local events = CreateFrame("Frame")
    for _, event in ipairs({ "UNIT_AURA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", onEvent)
    events:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if (dirty and since >= THROTTLE) or since >= TICK then update() end
    end)
    layout()
end
