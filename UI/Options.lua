-- Panneau d'options : général, seuils, priorités par classe de cible.
local _, ns = ...

local Options = {}
ns.Options = Options

local DISPLAY_LABELS = { minimal = "Minimaliste", info = "Informatif" }
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
    local header = label(parent, "Priorités par classe de cible", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 16, y)

    if not ns.classData then
        local none = label(parent, "Votre classe n'a aucun buff géré par FriendlyBuffer.", "GameFontDisable")
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
    local reset = smallButton(parent, "Réinitialiser", 110, function()
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
        local up = smallButton(parent, "Haut", 50, nil)
        up:SetPoint("TOPLEFT", 270, rowY - 3)
        local down = smallButton(parent, "Bas", 50, nil)
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

local CONTENT_WIDTH, CONTENT_HEIGHT = 640, 800

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
    local sub = label(content, "Liste les joueurs proches à buffer ; cliquez sur un nom pour lancer le buff (Alt + clic : sélectionner).", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

    checkbox(content, "Utiliser les buffs de groupe / supérieurs (clic gauche, membres du groupe)", "groupBuffs", 16, -60)
    checkbox(content, "Inclure les joueurs hors groupe (barres de nom alliées, cible)", "includeStrangers", 16, -86)
    local plates = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    plates:SetPoint("TOPLEFT", 40, -112)
    label(content, "Afficher les barres de nom alliées (nécessaire pour détecter les inconnus)"):SetPoint("LEFT", plates, "RIGHT", 2, 1)
    plates:SetScript("OnClick", function() ns.ToggleNameplates(); changed() end)
    refreshers[#refreshers + 1] = function() plates:SetChecked(ns.Compat.FriendlyNameplatesShown()) end

    checkbox(content, "Barres de nom alliées discrètes (seul le nom reste affiché, non cliquables)", "hiddenPlates", 40, -138)
    checkbox(content, "Masquer la fenêtre quand personne n'a besoin de buff", "autoHide", 16, -164)
    checkbox(content, "Verrouiller la position de la fenêtre", "locked", 16, -190)

    local modes = {}
    for _, mode in ipairs(ns.Config.DISPLAY_MODES) do modes[#modes + 1] = { key = mode, label = DISPLAY_LABELS[mode] } end
    choice(content, "Mode d'affichage", "displayMode", modes, 20, -226)

    stepper(content, "Nombre de lignes maximum", "maxRows", 20, -256, 1, 1, 20, "%d")
    stepper(content, "Expire bientôt (buffs de 5/10 min)", "thresholdShort", 20, -282, 15, 15, 300, "%d s")
    stepper(content, "Expire bientôt (buffs 30/60 min)", "thresholdLong", 20, -308, 30, 30, 900, "%d s")

    local namesHeader = label(content, "Noms des barres de nom discrètes", "GameFontNormalLarge")
    namesHeader:SetPoint("TOPLEFT", 16, -348)
    choice(content, "Police", "plateFont", ns.Config.PLATE_FONTS, 20, -378)
    choice(content, "Contour", "plateOutline", ns.Config.PLATE_OUTLINES, 20, -408)
    stepper(content, "Taille", "plateFontSize", 20, -436, 1, 8, 24, "%d")
    checkbox(content, "Ombre", "plateShadow", 16, -458)
    checkbox(content, "Afficher la guilde sous le nom", "plateGuild", 16, -484)

    buildPriorities(content, -530)

    panel:SetScript("OnShow", function()
        for _, refresh in ipairs(refreshers) do refresh() end
    end)
    handle = ns.Compat.RegisterOptions(panel, "FriendlyBuffer")
end
function Options.Open()
    if handle then ns.Compat.OpenOptions(handle) end
end
