-- Panneau d'options : général, seuils, priorités par classe de cible.
local _, ns = ...

local Options = {}
ns.Options = Options

local DISPLAY_LABELS = { minimal = "Minimaliste", info = "Informatif", range = "Informatif + portée" }
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
    local classText = label(parent, "", "GameFontNormal")
    local prev = smallButton(parent, "<", 24, function()
        selectedClass = (selectedClass - 2) % #classes + 1
        changed()
    end)
    prev:SetPoint("TOPLEFT", 16, y - 28)
    classText:SetPoint("LEFT", prev, "RIGHT", 8, 0)
    classText:SetWidth(120)
    local nextButton = smallButton(parent, ">", 24, function()
        selectedClass = selectedClass % #classes + 1
        changed()
    end)
    nextButton:SetPoint("LEFT", classText, "RIGHT", 8, 0)
    local reset = smallButton(parent, "Réinitialiser", 110, function()
        ns.Config.ResetPriorities(ns.db, ns.classData, classes[selectedClass])
        changed()
    end)
    reset:SetPoint("LEFT", nextButton, "RIGHT", 16, 0)

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
        local r, g, b = ns.Compat.ClassColor(cls)
        classText:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls)
        classText:SetTextColor(r, g, b)
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

function Options.Create()
    panel = CreateFrame("Frame")
    panel:Hide()

    local title = label(panel, "FriendlyBuffer", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local sub = label(panel, "Liste les joueurs proches à buffer ; cliquez sur un nom pour lancer le buff.", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

    checkbox(panel, "Utiliser les buffs de groupe / supérieurs (clic gauche, membres du groupe)", "groupBuffs", 16, -60)
    checkbox(panel, "Inclure les joueurs hors groupe (barres de nom alliées, cible, survol)", "includeStrangers", 16, -86)
    checkbox(panel, "Masquer la fenêtre quand personne n'a besoin de buff", "autoHide", 16, -112)
    checkbox(panel, "Verrouiller la position de la fenêtre", "locked", 16, -138)

    local modeLabel = label(panel, "Mode d'affichage")
    modeLabel:SetPoint("TOPLEFT", 20, -174)
    local modeButton = smallButton(panel, "", 160, function()
        local modes = ns.Config.DISPLAY_MODES
        for i, m in ipairs(modes) do
            if m == ns.db.displayMode then
                ns.db.displayMode = modes[i % #modes + 1]
                break
            end
        end
        changed()
    end)
    modeButton:SetPoint("TOPLEFT", 250, -171)
    refreshers[#refreshers + 1] = function() modeButton:SetText(DISPLAY_LABELS[ns.db.displayMode]) end

    stepper(panel, "Nombre de lignes maximum", "maxRows", 20, -204, 1, 1, 20, "%d")
    stepper(panel, "Expire bientôt (buffs de 5/10 min)", "thresholdShort", 20, -230, 15, 15, 300, "%d s")
    stepper(panel, "Expire bientôt (buffs 30/60 min)", "thresholdLong", 20, -256, 30, 30, 900, "%d s")

    buildPriorities(panel, -296)

    panel:SetScript("OnShow", function()
        for _, refresh in ipairs(refreshers) do refresh() end
    end)
    handle = ns.Compat.RegisterOptions(panel, "FriendlyBuffer")
end

function Options.Open()
    if handle then ns.Compat.OpenOptions(handle) end
end
