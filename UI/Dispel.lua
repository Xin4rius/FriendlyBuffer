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
local previewing = false  -- cases remplies par la simulation (Preview)

local function active()
    return ns.db.dispel and #spells > 0
end

---------------------------------------------------------------------------
-- Lecture
---------------------------------------------------------------------------

-- Débuff à retirer sur l'unité : présent, icône, type. Hors combat on lit les débuffs et on garde
-- ceux que nos sorts retirent ; quand les auras sont secrètes, la mémoire tenue par Auras (débuffs
-- vus hors combat encore présents, ajouts lisibles), puis le filtre du client.
local function read(unit)
    if not UnitExists(unit) or UnitIsDeadOrGhost(unit) or not UnitCanAssist("player", unit) then return false end
    for _, debuff in ipairs(ns.Auras.ReadDebuffs(unit)) do
        if ns.Decision.DispelIndex(spells, debuff.dispelName) or debuff.dispellable == true then
            return true, debuff.icon, debuff.dispelName
        end
    end
    if ns.Compat.AurasSecret() then return ns.Compat.DispellableSecret(unit) end
    return false
end

-- Pour /fb debug : lecture normale et lecture « combat » sur une unité.
function Dispel.Diagnose(unit)
    local normal = false
    if not ns.Compat.AurasSecret() then normal = read(unit) end
    return normal, ns.Compat.DispellableSecret(unit)
end

-- Pour /fb debug : état brut du filtre client et de la case de l'unité (cause d'une case absente).
function Dispel.Dump(unit)
    local filter = "n/a"
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HARMFUL|RAID_PLAYER_DISPELLABLE")
        if not ok then filter = "error: " .. tostring(data)
        elseif data == nil then filter = "nil"
        elseif ns.Compat.IsSecret(data) then filter = "secret"
        else filter = type(data) end
    end
    local slot
    for u, s in pairs(byUnit) do
        if UnitIsUnit(u, unit) then slot = s end
    end
    local state = slot and string.format("slot %s shown=%s visible=%s alpha=%.2f present=%s", tostring(slot.unit),
        tostring(slot:IsShown()), tostring(slot:IsVisible()), slot:GetAlpha(), tostring(slot.present)) or "no slot"
    return string.format("dispel raw: aurasSecret=%s filter=%s fighting=%s frameShown=%s active=%s; %s",
        tostring(ns.Compat.AurasSecret()), filter, tostring(fighting), tostring(frame and frame:IsShown()),
        tostring(active()), state)
end

-- Temporaire (diagnostic) : quelles API d'auras restent utilisables en combat sur ce client.
local lastAura = "none"
function Dispel.Probe(unit)
    local lines = {}
    local function try(label, fn, ...)
        if not fn then lines[#lines + 1] = label .. "=absent" return end
        local ok, a, b = pcall(fn, ...)
        local v = not ok and ("ERR " .. tostring(a):sub(1, 60))
            or (ns.Compat.IsSecret(a) and "secret" or (type(a) == "table" and ("table#" .. #a) or tostring(a)))
        if ok and b ~= nil then v = v .. "," .. (ns.Compat.IsSecret(b) and "secret" or tostring(b)) end
        lines[#lines + 1] = label .. "=" .. v
    end
    local api = C_UnitAuras or {}
    try("idxHarmful", api.GetAuraDataByIndex, unit, 1, "HARMFUL")
    try("instIDs", api.GetUnitAuraInstanceIDs, unit, "HARMFUL|RAID_PLAYER_DISPELLABLE")
    try("slots", api.GetAuraSlots, unit, "HARMFUL|RAID_PLAYER_DISPELLABLE")
    try("unitSlots", UnitAuraSlots, unit, "HARMFUL|RAID_PLAYER_DISPELLABLE")
    try("unitDebuff", UnitDebuff, unit, 1, "RAID")
    local names = {}
    for k in pairs(api) do
        if type(k) == "string" and (k:find("Dispel") or k:find("Instance") or k:find("Secret") or k:find("Filter")) then
            names[#names + 1] = k
        end
    end
    table.sort(names)
    lines[#lines + 1] = "lastUNIT_AURA=" .. lastAura
    lines[#lines + 1] = "api: " .. table.concat(names, " ")
    return lines
end

-- Identifiants d'auras reçus par UNIT_AURA (addedAuras), par GUID, pour tester les API par identifiant.
local seenIds = {}
function Dispel.NoteAura(unit, info)
    if not byUnit[unit] or type(info) ~= "table" then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local ids = seenIds[guid] or {}
    seenIds[guid] = ids
    for _, aura in ipairs(info.addedAuras or {}) do
        local id = aura.auraInstanceID
        if id and not ns.Compat.IsSecret(id) then
            ids[id] = { harmful = aura.isHarmful, dtype = aura.dispelName, icon = aura.icon }
        end
    end
    for _, id in ipairs(info.removedAuraInstanceIDs or {}) do ids[id] = nil end
    local added = info.addedAuras
    local first = added and added[1]
    lastAura = string.format("%s full=%s added=%s firstId=%s", unit, tostring(info.isFullUpdate),
        added and #added or "nil", first and (ns.Compat.IsSecret(first.auraInstanceID) and "secret"
        or tostring(first.auraInstanceID)) or "-")
end

local function show(v)
    if v == nil then return "nil" end
    return ns.Compat.IsSecret(v) and "secret" or tostring(v)
end

-- Pour chaque identifiant connu de l'unité : champs de la charge utile et API par identifiant.
function Dispel.ProbeIds(unit)
    local lines = {}
    local api = C_UnitAuras or {}
    local ids = seenIds[UnitGUID(unit) or ""] or {}
    for id, aura in pairs(ids) do
        local ok1, filtered = pcall(api.IsAuraFilteredOutByInstanceID, unit, id, "HARMFUL|RAID_PLAYER_DISPELLABLE")
        local ok2, data = pcall(api.GetAuraDataByAuraInstanceID, unit, id)
        lines[#lines + 1] = string.format("id %s: harmful=%s dtype=%s icon=%s | filteredOut=%s | byId=%s",
            tostring(id), show(aura.harmful), show(aura.dtype), show(aura.icon),
            ok1 and show(filtered) or ("ERR " .. tostring(filtered):sub(1, 50)),
            ok2 and (data and "table" or "nil") or ("ERR " .. tostring(data):sub(1, 50)))
        if #lines >= 6 then break end
    end
    if #lines == 0 then lines[1] = "no aura id received for this unit" end
    return lines
end

---------------------------------------------------------------------------
-- Affichage
---------------------------------------------------------------------------

-- Joueur simulé (Preview) : mêmes informations que read(), sans API.
local function readFake(fake)
    if not fake.debuff then return false end
    return true, fake.debuff.icon, fake.debuff.type
end

local function paint(slot)
    local unit, fake = slot.unit, slot.fake
    local present, icon, dtype
    if fake then present, icon, dtype = readFake(fake) else present, icon, dtype = read(unit) end
    slot.present = present == true
    slot.dtype = dtype
    if slot.present then
        pcall(slot.icon.SetTexture, slot.icon, icon) -- icône éventuellement secrète : acceptée par SetTexture
        local c = TYPE_COLORS[dtype] or UNKNOWN_COLOR
        slot.border:SetColorTexture(c[1], c[2], c[3], 1)
        local name = fake and fake.name or UnitName(unit)
        if name and not ns.Compat.IsSecret(name) then slot.name:SetText(name) end
        local class = fake and fake.class or select(2, UnitClass(unit))
        if class and not ns.Compat.IsSecret(class) then slot.name:SetTextColor(ns.Compat.ClassColor(class)) end
        slot.name:SetShown(ns.db.dispelNames)
        local far
        if fake then far = fake.far else far = ns.Compat.InRange(spells[1].rank.id, unit) == false end
        slot:SetAlpha(far and OUT_OF_RANGE_ALPHA or 1)
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
    previewing = ns.Preview.Active()
    -- Grille choisie dans les options : joueurs à la suite (ordre des groupes), au plus colonnes × lignes.
    local columns = ns.db.dispelColumns
    local list = previewing and ns.Preview.Layout() or ns.Scanner.GroupLayout(columns)
    table.sort(list, function(a, b) return a.position < b.position end)
    local rows = 1
    for i, slot in ipairs(slots) do
        local entry = i <= columns * ns.db.dispelRows and list[i]
        slot:SetSize(size, size)
        slot.name:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", math.max(8, math.floor(size / 3)), "OUTLINE")
        if entry then
            local index = i - 1
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", frame, "TOPLEFT", (index % columns) * (size + GAP), -math.floor(index / columns) * (size + GAP))
            rows = math.max(rows, math.floor(index / columns) + 1)
            slot.fake = entry.fake
            if entry.fake then
                -- Case simulée : ne lance rien.
                slot.unit = "none"
                slot:SetAttribute("type1", nil)
                slot:SetAttribute("type2", nil)
            else
                slot.unit = entry.unit
                byUnit[entry.unit] = slot
                slot:SetAttribute("type1", "macro")
                slot:SetAttribute("macrotext1", macro(entry.unit, 1))
                slot:SetAttribute("type2", "macro")
                slot:SetAttribute("macrotext2", macro(entry.unit, 2))
            end
        else
            slot.unit, slot.fake = nil, nil
            slot.present = false
            slot:SetAttribute("type1", nil)
            slot:SetAttribute("type2", nil)
            slot:Hide()
        end
    end
    frame:SetSize(math.min(columns, math.max(#list, 1)) * (size + GAP) - GAP, rows * (size + GAP) - GAP)
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
    if not slot.present or not slot.unit or slot.fake then return end
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

local function onEvent(_, event, unit, info)
    if event == "UNIT_AURA" then
        pcall(Dispel.NoteAura, unit, info)
        if byUnit[unit] then dirty = true end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Dernier instant où les cases peuvent encore être montrées : toutes, transparentes si vides.
        ns.Preview.OnCombat()
        if previewing then layout() end
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
