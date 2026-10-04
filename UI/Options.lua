-- Panneau d'options : général, seuils, priorités par classe de cible.
local _, ns = ...

local L = ns.L

local Options = {}
ns.Options = Options

local DISPLAY_LABELS = { minimal = L["Minimal"], info = L["Detailed"] }
local MAX_ENTRIES = 6

local panel, handle
local refreshers = {}
local selectedClass = 1

local function changed()
    for _, refresh in ipairs(refreshers) do refresh() end
    ns.OnSettingsChanged()
end

local function label(parent, text, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetText(text)
    return fs
end

local function smallButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function checkbox(parent, text, key, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    local fs = label(parent, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        changed()
    end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(ns.db[key]) end
    return cb
end

-- Valeur numérique avec boutons - / +.
local function stepper(parent, text, key, x, y, step, min, max, format)
    local fs = label(parent, text)
    fs:SetPoint("TOPLEFT", x, y)
    local minus = smallButton(parent, "-", 24, function()
        ns.db[key] = math.max(min, ns.db[key] - step)
        changed()
    end)
    minus:SetPoint("TOPLEFT", x + 230, y + 3)
    local value = label(parent, "")
    value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    value:SetWidth(50)
    local plus = smallButton(parent, "+", 24, function()
        ns.db[key] = math.min(max, ns.db[key] + step)
        changed()
    end)
    plus:SetPoint("LEFT", value, "RIGHT", 6, 0)
    refreshers[#refreshers + 1] = function() value:SetText(string.format(format, ns.db[key])) end
end

-- Liste déroulante (menu moderne, comme Leatrix Plus sur Forever) pour un choix parmi
-- { {key, label}, ... } ; à défaut, un bouton qui fait défiler les valeurs.
local function selector(parent, list, get, set, width)
    if MenuUtil and MenuUtil.CreateRadioMenu then
        local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown:SetWidth(width)
        local items = {}
        for _, entry in ipairs(list) do items[#items + 1] = { entry.label, entry.key } end
        MenuUtil.CreateRadioMenu(dropdown,
            function(value) return get() == value end,
            function(value) set(value); changed() end,
            unpack(items))
        refreshers[#refreshers + 1] = function()
            if dropdown.GenerateMenu then dropdown:GenerateMenu() end
        end
        return dropdown
    end
    local button = smallButton(parent, "", width, function()
        for i, entry in ipairs(list) do
            if entry.key == get() then
                set(list[i % #list + 1].key)
                break
            end
        end
        changed()
    end)
    refreshers[#refreshers + 1] = function() button:SetText(ns.Config.Find(list, get()).label) end
    return button
end

-- Libellé + liste déroulante liée à un réglage.
local function choice(parent, text, key, list, x, y)
    label(parent, text):SetPoint("TOPLEFT", x, y)
    local widget = selector(parent, list,
        function() return ns.db[key] end,
        function(value) ns.db[key] = value end, 180)
    widget:SetPoint("TOPLEFT", x + 230, y + 5)
end
local function familyLabel(key)
    local fam = ns.classData.families[key]
    local name, icon = ns.Compat.GetSpellInfo(fam.ranks[1].id)
    if icon then return "|T" .. icon .. ":16|t " .. (name or key) end
    return name or key
end

local function buildPriorities(parent, y)
    local header = label(parent, L["Priorities by target class"], "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 16, y)

    if not ns.classData then
        local none = label(parent, L["Your class has no buff supported by FriendlyBuffer."], "GameFontDisable")
        none:SetPoint("TOPLEFT", 16, y - 28)
        return
    end

    local classes = ns.TARGET_CLASSES
    local classList = {}
    for _, cls in ipairs(classes) do
        classList[#classList + 1] = { key = cls, label = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls }
    end
    local classSelector = selector(parent, classList,
        function() return classes[selectedClass] end,
        function(value)
            for i, cls in ipairs(classes) do
                if cls == value then selectedClass = i end
            end
        end, 180)
    classSelector:SetPoint("TOPLEFT", 16, y - 26)
    local reset = smallButton(parent, L["Reset"], 110, function()
        ns.Config.ResetPriorities(ns.db, ns.classData, classes[selectedClass])
        changed()
    end)
    reset:SetPoint("LEFT", classSelector, "RIGHT", 16, 0)

    local rows = {}
    for i = 1, MAX_ENTRIES do
        local rowY = y - 56 - (i - 1) * 26
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 16, rowY)
        local text = label(parent, "")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
        text:SetWidth(220)
        text:SetJustifyH("LEFT")
        local up = smallButton(parent, L["Up"], 50, nil)
        up:SetPoint("TOPLEFT", 270, rowY - 3)
        local down = smallButton(parent, L["Down"], 50, nil)
        down:SetPoint("LEFT", up, "RIGHT", 4, 0)
        rows[i] = { cb = cb, text = text, up = up, down = down }

        local function list() return ns.db.priorities[classes[selectedClass]] end
        local function swap(a, b)
            local l = list()
            l[a], l[b] = l[b], l[a]
            changed()
        end
        cb:SetScript("OnClick", function(self)
            local entry = list()[i]
            if not entry then return end
            entry.enabled = self:GetChecked() and true or false
            changed()
        end)
        up:SetScript("OnClick", function() if i > 1 and i <= #list() then swap(i, i - 1) end end)
        down:SetScript("OnClick", function() if i < #list() then swap(i, i + 1) end end)
    end

    refreshers[#refreshers + 1] = function()
        local cls = classes[selectedClass]
        local list = ns.db.priorities[cls]
        for i, row in ipairs(rows) do
            local entry = list[i]
            local visible = entry ~= nil
            row.cb:SetShown(visible); row.text:SetShown(visible); row.up:SetShown(visible); row.down:SetShown(visible)
            if visible then
                row.cb:SetChecked(entry.enabled)
                row.text:SetText(i .. ". " .. familyLabel(entry.key))
                row.text:SetAlpha(entry.enabled and 1 or 0.5)
                row.up:SetEnabled(i > 1)
                row.down:SetEnabled(i < #list)
            end
        end
    end
end

local CONTENT_WIDTH, CONTENT_HEIGHT = 640, 830

function Options.Create()
    panel = CreateFrame("Frame")
    panel:Hide()

    -- Contenu défilant : le panneau est plus haut que la fenêtre d'options.
    -- ScrollFrameTemplate : modèle moderne présent sur Forever (utilisé aussi par Leatrix Plus).
    local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, CONTENT_HEIGHT)
    scroll:SetScrollChild(content)

    local title = label(content, "FriendlyBuffer", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local sub = label(content, L["Lists nearby players to buff; click a name to cast the buff (Alt + click: select)."], "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

    checkbox(content, L["Use group / greater buffs (left click, group members)"], "groupBuffs", 16, -60)
    checkbox(content, L["Include players outside your group (friendly nameplates, target)"], "includeStrangers", 16, -86)
    local plates = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    plates:SetPoint("TOPLEFT", 40, -112)
    label(content, L["Show friendly nameplates (required to detect strangers)"]):SetPoint("LEFT", plates, "RIGHT", 2, 1)
    plates:SetScript("OnClick", function() ns.ToggleNameplates(); changed() end)
    refreshers[#refreshers + 1] = function() plates:SetChecked(ns.Compat.FriendlyNameplatesShown()) end

    checkbox(content, L["Discreet friendly nameplates (only the name is shown, click-through)"], "hiddenPlates", 40, -138)
    checkbox(content, L["Hide the window when nobody needs a buff"], "autoHide", 16, -164)
    checkbox(content, L["Lock the window position"], "locked", 16, -190)

    local modes = {}
    for _, mode in ipairs(ns.Config.DISPLAY_MODES) do modes[#modes + 1] = { key = mode, label = DISPLAY_LABELS[mode] } end
    choice(content, L["Display mode"], "displayMode", modes, 20, -226)

    stepper(content, L["Maximum number of rows"], "maxRows", 20, -256, 1, 1, 20, "%d")
    stepper(content, L["Expiring soon (5/10 min buffs)"], "thresholdShort", 20, -282, 15, 15, 300, "%d s")
    stepper(content, L["Expiring soon (30/60 min buffs)"], "thresholdLong", 20, -308, 30, 30, 900, "%d s")
    stepper(content, L["Keep buffed players shown as OK for"], "doneDuration", 20, -334, 1, 0, 30, "%d s")

    local namesHeader = label(content, L["Names on discreet nameplates"], "GameFontNormalLarge")
    namesHeader:SetPoint("TOPLEFT", 16, -374)
    choice(content, L["Font"], "plateFont", ns.Config.PLATE_FONTS, 20, -404)
    choice(content, L["Outline"], "plateOutline", ns.Config.PLATE_OUTLINES, 20, -434)
    stepper(content, L["Size"], "plateFontSize", 20, -462, 1, 8, 24, "%d")
    checkbox(content, L["Shadow"], "plateShadow", 16, -484)
    checkbox(content, L["Show the guild under the name"], "plateGuild", 16, -510)

    buildPriorities(content, -556)

    panel:SetScript("OnShow", function()
        for _, refresh in ipairs(refreshers) do refresh() end
    end)
    handle = ns.Compat.RegisterOptions(panel, "FriendlyBuffer")
end
function Options.Open()
    if handle then ns.Compat.OpenOptions(handle) end
end
