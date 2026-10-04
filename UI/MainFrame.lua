-- Fenêtre principale : pool de boutons sécurisés, un par joueur à buffer.
-- Les attributs sécurisés ne peuvent changer qu'hors combat ; en combat on ne met à jour que l'affichage.
local _, ns = ...

local MainFrame = {}
ns.MainFrame = MainFrame

local ROW_HEIGHT = 18
local TITLE_HEIGHT = 20
local PADDING = 6
local WIDTH = { minimal = 150, info = 210, range = 210 }
local MAX_ROWS_LIMIT = 20

local REASON_COLORS = {
    missing = { 1, 0.25, 0.25 },
    expiring = { 1, 0.6, 0.1 },
    lower = { 1, 0.9, 0.2 },
}
local REASON_LABELS = { missing = "manquant", expiring = "expire", lower = "rang inf." }

local frame, buttons = nil, {}
local pending = false     -- une reconstruction complète attend la fin du combat / du survol
local lastRows = {}

local function formatTime(seconds)
    if not seconds then return "" end
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 60 then return string.format("%d:%02d", seconds / 60, seconds % 60) end
    return seconds .. "s"
end

local function reasonText(need)
    if need.reason == "expiring" and need.remaining then return formatTime(need.remaining) end
    return REASON_LABELS[need.reason]
end

---------------------------------------------------------------------------
-- Attributs sécurisés
---------------------------------------------------------------------------

local function clearAttributes(button)
    for _, attr in ipairs({ "type1", "type2", "macrotext1", "macrotext2" }) do
        button:SetAttribute(attr, nil)
    end
end

-- Membre du groupe : /cast [@unité], sans toucher à la cible.
local function groupMacro(unit, rank)
    return "/cast [@" .. unit .. "] " .. ns.CastString(rank)
end

-- Inconnu : cibler par « Prénom Nom », lancer, revenir à la cible d'avant.
-- /cleartarget d'abord : si le ciblage échoue, [@target,help,nodead] ne trouve personne et rien
-- n'est lancé (sans ça, /cast partirait sur soi-même ou sur l'ancienne cible).
local function strangerMacro(row, restore)
    return "/cleartarget\n/targetexact " .. row.name .. "\n/cast [@target,help,nodead] "
        .. ns.CastString(row.need.single) .. "\n" .. restore
end

local function applyMacros(button, row, restore)
    local left, right
    if row.isGroup then
        left = groupMacro(button.unit, row.need.group or row.need.single)
        right = groupMacro(button.unit, row.need.single)
    else
        left = strangerMacro(row, restore)
        right = left
    end
    button:SetAttribute("type1", "macro")
    button:SetAttribute("macrotext1", left)
    button:SetAttribute("type2", "macro")
    button:SetAttribute("macrotext2", right)
end

local function assign(button, row)
    clearAttributes(button)
    button.row = row
    button.unit = row.unit
    button.done = false
    applyMacros(button, row, "/targetlasttarget")
end

-- Hors combat, juste avant le sort :
-- inconnu : sans cible au départ, on vide la cible au lieu de revenir à une ancienne ;
-- groupe : l'unité désigne-t-elle toujours ce joueur ? Sinon on la recale, ou on désactive le clic.
local function onPreClick(button)
    local row = button.row
    if not row or button.done or InCombatLockdown() then return end
    if not row.isGroup then
        applyMacros(button, row, UnitExists("target") and "/targetlasttarget" or "/cleartarget")
        return
    end
    if UnitGUID(button.unit) == row.guid then return end
    local found = ns.Scanner.FindUnit(row.guid)
    if found then
        button.unit = found
        applyMacros(button, row)
    else
        clearAttributes(button)
        button.done = true
        ns.Print(row.name .. " n'est plus visible.")
    end
end
---------------------------------------------------------------------------
-- Affichage
---------------------------------------------------------------------------

local function paint(button, row, done)
    local mode = ns.db.displayMode
    local r, g, b = ns.Compat.ClassColor(row.class)
    button.name:SetText(row.name)
    button.name:SetTextColor(r, g, b)

    local showDetails = mode ~= "minimal"
    button.icon:SetShown(showDetails)
    button.reason:SetShown(showDetails)
    button.name:ClearAllPoints()
    if showDetails then
        local _, icon = ns.Compat.GetSpellInfo(row.need.single.id)
        button.icon:SetTexture(icon)
        button.name:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
        button.reason:SetText(done and "OK" or reasonText(row.need))
        local c = done and { 0.4, 1, 0.4 } or REASON_COLORS[row.need.reason]
        button.reason:SetTextColor(c[1], c[2], c[3])
    else
        button.name:SetPoint("LEFT", button, "LEFT", 2, 0)
    end
    button.name:SetPoint("RIGHT", button, "RIGHT", showDetails and -50 or -2, 0)

    local alpha = 1
    if done then
        alpha = 0.35
    elseif mode == "range" and row.inRange == false then
        alpha = 0.45
    end
    button:SetAlpha(alpha)
end

local function onEnter(button)
    local row = button.row
    if not row then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(row.name, ns.Compat.ClassColor(row.class))
    if button.done then
        GameTooltip:AddLine("Plus besoin de buff", 0.4, 1, 0.4)
    else
        local c = REASON_COLORS[row.need.reason]
        local reason = REASON_LABELS[row.need.reason]
        if row.need.reason == "expiring" then reason = "expire dans " .. formatTime(row.need.remaining) end
        GameTooltip:AddLine(ns.SpellLabel(row.need.single) .. " : " .. reason, c[1], c[2], c[3])
        if row.isGroup and row.need.group then
            local reagent = row.need.group.reagent or ns.Spells[ns.playerClass].families[row.need.family].reagent
            local count = reagent and ns.Compat.ItemCount(reagent) or 0
            GameTooltip:AddLine("Clic gauche : " .. ns.SpellLabel(row.need.group) .. " (composants : " .. count .. ")", 1, 1, 1)
            GameTooltip:AddLine("Clic droit : " .. ns.SpellLabel(row.need.single), 1, 1, 1)
        else
            GameTooltip:AddLine("Clic : " .. ns.SpellLabel(row.need.single), 1, 1, 1)
        end
        if not row.isGroup then GameTooltip:AddLine("Hors groupe : ciblé par son nom puis cible précédente rétablie", 0.6, 0.6, 0.6) end
    end
    GameTooltip:Show()
end

local function createButton(index)
    local button = CreateFrame("Button", "FriendlyBufferRow" .. index, frame, "SecureActionButtonTemplate")
    button:SetHeight(ROW_HEIGHT)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -(TITLE_HEIGHT + (index - 1) * ROW_HEIGHT))
    button:SetPoint("RIGHT", frame, "RIGHT", -PADDING, 0)
    button:RegisterForClicks("AnyUp", "AnyDown")

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.12)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
    button.icon:SetPoint("LEFT", 1, 0)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.name:SetJustifyH("LEFT")
    button.name:SetWordWrap(false)

    button.reason = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.reason:SetPoint("RIGHT", -2, 0)
    button.reason:SetJustifyH("RIGHT")

    button:SetScript("PreClick", onPreClick)
    button:SetScript("OnEnter", onEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:Hide()
    return button
end

local function updateTitle(total)
    local text = "FriendlyBuffer"
    if total > 0 then text = text .. "  |cffffffff" .. total .. " à buffer|r" end
    if InCombatLockdown() then text = text .. "  |cffff4040(combat)|r" end
    frame.title:SetText(text)
end

local function layout(shown)
    local mode = ns.db.displayMode
    frame:SetWidth(WIDTH[mode] or WIDTH.minimal)
    frame:SetHeight(TITLE_HEIGHT + math.max(shown, 1) * ROW_HEIGHT + PADDING)
end

local function shouldShow(total)
    if ns.db.hidden then return false end
    if ns.db.autoHide and total == 0 then return false end
    return true
end

-- Reconstruction complète : ordre, attributs, visibilité. Hors combat uniquement.
local function fullRender(rows)
    local maxRows = math.min(ns.db.maxRows, MAX_ROWS_LIMIT)
    local shown = math.min(#rows, maxRows)
    for i = 1, MAX_ROWS_LIMIT do
        local button = buttons[i]
        if i <= shown then
            assign(button, rows[i])
            paint(button, rows[i], false)
            button:Show()
        else
            clearAttributes(button)
            button.row = nil
            button:Hide()
        end
    end
    layout(shown)
    frame:SetShown(shouldShow(#rows))
    pending = false
end

-- Mise à jour sur place des lignes affichées (même joueur, même position).
-- canAssign : hors combat on peut aussi réaffecter/désactiver les attributs.
local function softRender(rows, canAssign)
    local byGuid = {}
    for _, row in ipairs(rows) do byGuid[row.guid] = row end
    for i = 1, MAX_ROWS_LIMIT do
        local button = buttons[i]
        if button:IsShown() and button.row then
            local row = byGuid[button.row.guid]
            -- En combat le bouton lance toujours l'ancien sort : si le besoin a changé de buff,
            -- l'ancien est satisfait et la ligne est considérée comme faite.
            if row and not canAssign and row.need.family ~= button.row.need.family then row = nil end
            if row then
                if canAssign then assign(button, row) else button.row = row end
                button.done = false
                paint(button, row, false)
            else
                if canAssign then clearAttributes(button) end
                button.done = true
                paint(button, button.row, true)
            end
        end
    end
    pending = true
end

function MainFrame.Render(rows)
    if not frame then return end
    lastRows = rows
    updateTitle(#rows)
    if InCombatLockdown() then
        softRender(rows, false)
    elseif frame:IsShown() and frame:IsMouseOver() then
        -- Pas de réordonnancement sous le curseur : évite de cliquer sur le mauvais joueur.
        softRender(rows, true)
    else
        fullRender(rows)
    end
end

-- Appelé en sortie de combat ou quand le curseur quitte la fenêtre.
function MainFrame.Flush()
    if frame and pending and not InCombatLockdown() then
        fullRender(lastRows)
        updateTitle(#lastRows)
    end
end

function MainFrame.ResetPosition()
    if not frame or InCombatLockdown() then return end
    ns.db.point = nil
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
end

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    ns.db.point = { point, relativePoint, x, y }
end

function MainFrame.Create()
    frame = CreateFrame("Frame", "FriendlyBufferFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.75)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)

    frame:SetScript("OnDragStart", function(self)
        if not ns.db.locked and not InCombatLockdown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    frame:SetScript("OnLeave", function(self)
        if not self:IsMouseOver() then MainFrame.Flush() end
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("TOPLEFT", PADDING + 2, -6)
    frame.title:SetPoint("RIGHT", -PADDING, 0)
    frame.title:SetJustifyH("LEFT")

    for i = 1, MAX_ROWS_LIMIT do
        buttons[i] = createButton(i)
        -- Quitter une ligne pour sortir de la fenêtre doit aussi déclencher la mise à jour.
        buttons[i]:HookScript("OnLeave", function()
            if not frame:IsMouseOver() then MainFrame.Flush() end
        end)
    end

    local p = ns.db.point
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end
    layout(0)
    updateTitle(0)
    frame:Hide()
end
