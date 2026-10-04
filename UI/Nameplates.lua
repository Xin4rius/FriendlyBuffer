-- Option « barres de nom alliées discrètes » : les barres alliées restent actives (l'addon en a
-- besoin pour voir les inconnus) mais tout leur contenu est masqué, nom de Blizzard compris, et
-- remplacé par notre propre texte « Nom » (+ « <Guilde> »), comme sans Maj+V. Elles laissent
-- passer les clics.
--
-- Les éléments des barres de nom sont des régions « restreintes » : les mesurer (GetPoint,
-- GetWidth…) déclenche une erreur de taint. On ne fait donc que les rendre transparents
-- (SetAlpha) et lire le texte du nom ; tout le style s'applique à nos propres textes.
local _, ns = ...

local Nameplates = {}
ns.Nameplates = Nameplates

local MAX_NAMEPLATES = 40
-- UnitFrame -> { faded = { [élément] = true }, unit }
local hidden = setmetatable({}, { __mode = "k" })

local function unitFrame(unit)
    local plate = ns.Compat.GetNamePlateForUnit(unit)
    return plate and plate.UnitFrame
end

---------------------------------------------------------------------------
-- Polices
---------------------------------------------------------------------------

-- Polices de secours par alphabet : une police latine seule affiche des carrés pour le chinois,
-- le coréen ou le cyrillique. Tous les clients contiennent ces fichiers (cf. LibSharedMedia).
local CYRILLIC = {
    friz = "Fonts\\FRIZQT___CYR.TTF", arial = "Fonts\\ARIALN.TTF",
    skurri = "Fonts\\SKURRI_CYR.TTF", morpheus = "Fonts\\MORPHEUS_CYR.TTF",
}
local KOREAN = "Fonts\\2002.TTF"
local SIMPLIFIED_CHINESE = "Fonts\\ARKai_T.ttf"
local TRADITIONAL_CHINESE = "Fonts\\bLEI00D.ttf"

local families = {}

-- Famille de polices (police choisie + secours par alphabet), créée une fois par combinaison.
local function fontFamily(font, size, flags)
    if not CreateFontFamily then return nil end
    local id = "FriendlyBufferNameFont_" .. font.key .. "_" .. size .. "_" .. (flags ~= "" and flags or "NONE")
    if not families[id] then
        local function member(alphabet, file)
            return { alphabet = alphabet, file = file, height = size, flags = flags }
        end
        families[id] = CreateFontFamily(id, {
            member("roman", font.path),
            member("russian", CYRILLIC[font.key] or font.path),
            member("korean", KOREAN),
            member("simplifiedchinese", SIMPLIFIED_CHINESE),
            member("traditionalchinese", TRADITIONAL_CHINESE),
        })
    end
    return families[id]
end

local function applyFont(fontString)
    local db = ns.db
    local font = ns.Config.Find(ns.Config.PLATE_FONTS, db.plateFont)
    local flags = ns.Config.Find(ns.Config.PLATE_OUTLINES, db.plateOutline).flags
    local family = fontFamily(font, db.plateFontSize, flags)
    if family then
        fontString:SetFontObject(family)
    else
        fontString:SetFont(font.path, db.plateFontSize, flags)
    end
    if db.plateShadow then
        fontString:SetShadowColor(0, 0, 0, 1)
        fontString:SetShadowOffset(1, -1)
    else
        fontString:SetShadowOffset(0, 0)
    end
end

---------------------------------------------------------------------------
-- Texte affiché
---------------------------------------------------------------------------

-- Texte du nom : celui de Blizzard (lisible, contrairement à sa géométrie), sinon UnitName.
local function nameText(frame, unit)
    local blizzard = frame.name or frame.Name
    if blizzard and blizzard.GetText then
        -- pcall : si ce client restreint aussi la lecture du texte, on passe à UnitName.
        local ok, text = pcall(blizzard.GetText, blizzard)
        if ok and text and text ~= "" and not ns.Compat.IsSecret(text) then return text end
    end
    local name, surname = UnitName(unit)
    if not name or ns.Compat.IsSecret(name) or ns.Compat.IsSecret(surname) then return nil end
    if surname and surname ~= "" then return name .. " " .. surname end
    return name
end

-- Couleur comme sans Maj+V : celle que le jeu utilise pour la sélection (bleu allié, vert JcJ…).
local function selectionColor(unit)
    if not UnitSelectionColor then return 1, 1, 1 end
    local r, g, b = UnitSelectionColor(unit, true)
    if r == nil or ns.Compat.IsSecret(r) then return 1, 1, 1 end
    return r, g, b
end

local function guildName(unit)
    if not ns.db.plateGuild or not GetGuildInfo then return nil end
    local guild = GetGuildInfo(unit)
    if not guild or guild == "" or ns.Compat.IsSecret(guild) then return nil end
    return guild
end

-- Nos textes, créés une fois par barre (les barres sont recyclées). Un seul point d'ancrage :
-- la largeur suit le texte, le nom n'est jamais tronqué.
local function ownTexts(frame)
    if not frame.friendlyBufferName then
        local name = frame:CreateFontString(nil, "OVERLAY")
        name:SetPoint("CENTER", frame, "CENTER", 0, 0)
        name:SetWordWrap(false)
        local guild = frame:CreateFontString(nil, "OVERLAY")
        guild:SetPoint("TOP", name, "BOTTOM", 0, -1)
        guild:SetWordWrap(false)
        frame.friendlyBufferName, frame.friendlyBufferGuild = name, guild
    end
    return frame.friendlyBufferName, frame.friendlyBufferGuild
end

local function isOwn(frame, object)
    return object == frame.friendlyBufferName or object == frame.friendlyBufferGuild
end

---------------------------------------------------------------------------
-- Masquer / rendre
---------------------------------------------------------------------------

-- Rend transparent tout le contenu de la barre sauf nos textes. Refait à chaque passage :
-- Blizzard peut réafficher un élément ou en créer un nouveau.
local function fadeAll(frame, state)
    local parts = { frame:GetRegions() }
    for _, child in ipairs({ frame:GetChildren() }) do parts[#parts + 1] = child end
    for _, object in ipairs(parts) do
        if not isOwn(frame, object) then
            object:SetAlpha(0)
            state.faded[object] = true
        end
    end
end

local function keepOnlyName(frame, unit)
    local text = nameText(frame, unit)
    -- Nom illisible (valeur secrète) : on laisse la barre telle quelle plutôt que de tout masquer.
    if not text then return end

    local state = hidden[frame]
    if not state then
        state = { faded = {} }
        hidden[frame] = state
    end
    state.unit = unit
    fadeAll(frame, state)

    local name, guildLine = ownTexts(frame)
    local r, g, b = selectionColor(unit)
    applyFont(name)
    name:SetText(text)
    name:SetTextColor(r, g, b)
    name:Show()

    local guild = guildName(unit)
    if guild then
        applyFont(guildLine)
        guildLine:SetText("<" .. guild .. ">")
        guildLine:SetTextColor(r, g, b)
        guildLine:Show()
    else
        guildLine:Hide()
    end
end

local function restore(frame)
    local state = frame and hidden[frame]
    if not state then return end
    for object in pairs(state.faded) do object:SetAlpha(1) end
    if frame.friendlyBufferName then frame.friendlyBufferName:Hide() end
    if frame.friendlyBufferGuild then frame.friendlyBufferGuild:Hide() end
    hidden[frame] = nil
end

-- Blizzard met à jour le nom (changement de nom, de cible…) : on suit le texte.
if hooksecurefunc and CompactUnitFrame_UpdateName then
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        local state = hidden[frame]
        if state then keepOnlyName(frame, state.unit) end
    end)
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

-- Applique l'état voulu à la barre d'une unité (les barres sont recyclées entre alliés et ennemis).
function Nameplates.Update(unit)
    local frame = unitFrame(unit)
    if not frame then return end
    if ns.db.hiddenPlates and UnitExists(unit) and not UnitCanAttack("player", unit) then
        keepOnlyName(frame, unit)
    else
        restore(frame)
    end
end

-- Réapplique l'état à toutes les barres (guilde connue plus tard, options modifiées…).
function Nameplates.Refresh()
    for i = 1, MAX_NAMEPLATES do Nameplates.Update("nameplate" .. i) end
end

function Nameplates.Removed(unit)
    restore(unitFrame(unit))
end

-- Active ou retire le mode discret (hors combat : la CVar est protégée en combat).
function Nameplates.Apply()
    if InCombatLockdown() then return end
    if ns.db.hiddenPlates then
        if not ns.Compat.FriendlyNameplatesShown() then
            ns.Compat.SetFriendlyNameplates(true)
            ns.db.platesEnabledByAddon = true
        end
        ns.Compat.SetFriendlyClickThrough(true)
        ns.db.clickThroughByAddon = true
    else
        if ns.db.clickThroughByAddon then
            ns.Compat.SetFriendlyClickThrough(false)
            ns.db.clickThroughByAddon = nil
        end
        if ns.db.platesEnabledByAddon then
            ns.Compat.SetFriendlyNameplates(false)
            ns.db.platesEnabledByAddon = nil
        end
    end
    Nameplates.Refresh()
end
