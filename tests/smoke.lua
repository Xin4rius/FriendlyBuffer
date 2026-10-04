-- Test de fumée : charge l'addon complet (ordre du .toc) avec une API WoW simulée,
-- puis rejoue connexion, scan, clics, combat et options. `lua tests/smoke.lua`
local noop = function() end
local created = {}

local methods = {}
local function newObject(name)
    local o = { scripts = {}, attrs = {}, shown = true, text = "", hooks = {}, events = {}, frameName = name or "" }
    created[#created + 1] = o
    -- Méthodes (Majuscule) : no-op par défaut ; champs (minuscule) : nil.
    return setmetatable(o, { __index = function(_, k)
        if methods[k] then return methods[k] end
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(v) self.shown = v and true or false end
function methods:IsShown() return self.shown end
function methods:SetScript(k, f) self.scripts[k] = f end
function methods:HookScript(k, f) self.hooks[k] = f end
function methods:SetAttribute(k, v) self.attrs[k] = v end
function methods:GetAttribute(k) return self.attrs[k] end
function methods:CreateFontString() return newObject() end
function methods:CreateTexture() return newObject() end
function methods:SetText(t) self.text = t end
function methods:GetText() return self.text end
function methods:GetChecked() return false end
function methods:IsMouseOver() return false end
function methods:GetPoint() return "CENTER", nil, "CENTER", 10, 20 end
function methods:RegisterEvent(e) self.events[e] = true end
function methods:GetID() return 42 end
function methods:SetAlpha(a) self.alpha = a end
function methods:SetTextColor(r, g, b) self.color = { r, g, b } end
function methods:GetTextColor() local c = rawget(self, "color") or { 1, 1, 1 }; return c[1], c[2], c[3] end
function methods:SetFont(path, size, flags) self.font = { path, size, flags } end
function methods:GetFont() local f = rawget(self, "font") or { "Fonts\\ORIG.TTF", 9, "OUTLINE" }; return f[1], f[2], f[3] end
function methods:SetShadowOffset(x, y) self.shadow = { x, y } end
function methods:GetShadowOffset() local s = rawget(self, "shadow") or { 0, 0 }; return s[1], s[2] end
function methods:GetShadowColor() return 0, 0, 0, 1 end
function methods:SetFontObject(o) self.fontObject = o end
function methods:GetFontObject() return rawget(self, "fontObject") or "ORIG_OBJ" end
methods.SetVertexColor = methods.SetTextColor
methods.GetVertexColor = methods.GetTextColor
function methods:GetChildren() return unpack(rawget(self, "children") or {}) end
function methods:GetRegions() return unpack(rawget(self, "regions") or {}) end
function methods:GetParent() return rawget(self, "parent") end

-- Monde simulé ---------------------------------------------------------------
local inCombat = false
local now = 1000
local units = {
    player  = { name = "Moi", class = "PRIEST", level = 60, guid = "G0", buffs = {} },
    party1  = { name = "Garrosh", class = "WARRIOR", level = 60, guid = "G1", buffs = {} },
    party2  = { name = "Jaina", class = "MAGE", level = 60, guid = "G2",
                buffs = { { spellId = 10938, name = "Robustesse", sourceUnit = "player", duration = 1800, expirationTime = 2500 } } },
    nameplate1 = { name = "Valeera", surname = "Sanguinar", class = "ROGUE", level = 58, guid = "G3", buffs = {}, stranger = true },
    nameplate3 = { name = "Loin", class = "WARRIOR", level = 60, guid = "G7", buffs = {}, stranger = true, far = true },
}
local function U(unit) return units[unit] end

_G.CreateFrame = function(_, name)
    local o = newObject(name)
    if name then _G[name] = o end
    return o
end
_G.UIParent = newObject("UIParent")
_G.GameTooltip = newObject("GameTooltip")
_G.GameTooltip_Hide = noop
_G.SlashCmdList = {}
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.GetTime = function() return now end
_G.InCombatLockdown = function() return inCombat end
_G.IsInRaid = function() return false end
_G.IsInGroup = function() return true end
_G.GetNumSubgroupMembers = function() return 2 end
_G.GetNumGroupMembers = function() return 3 end
_G.UnitExists = function(u) return U(u) ~= nil end
_G.UnitIsPlayer = function(u) return U(u) ~= nil end
_G.UnitIsConnected = function() return true end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitCanAssist = function() return true end
_G.UnitInParty = function(u) return U(u) ~= nil and not U(u).stranger end
_G.UnitInRaid = function() return nil end
_G.UnitIsUnit = function(a, b) return a == b end
_G.UnitIsPVP = function() return false end
_G.UnitCanAttack = function() return false end
_G.IsAltKeyDown = function() return false end
_G.UnitSelectionColor = function() return 0, 0, 1 end
_G.MenuUtil = {
    CreateRadioMenu = function(dropdown, isSelected, setSelected, ...)
        dropdown.radio = { isSelected = isSelected, setSelected = setSelected, items = { ... } }
    end,
}
_G.CreateFontFamily = function(name, members) return { name = name, members = members } end
_G.GetGuildInfo = function(u) if u == "nameplate1" then return "Les Gardiens" end end
local blizzardHooks = {}
_G.hooksecurefunc = function(name, fn) blizzardHooks[name] = fn end
_G.CompactUnitFrame_UpdateName = function(f) f.name:SetVertexColor(1, 1, 1) end
_G.UnitName = function(u) if U(u) then return U(u).name, U(u).surname end end
_G.UnitGUID = function(u) return U(u) and U(u).guid end
_G.UnitLevel = function(u) return U(u) and U(u).level end
_G.UnitClass = function(u) return U(u) and U(u).class, U(u) and U(u).class end
_G.IsSpellKnown = function() return true end
_G.C_UnitAuras = { GetBuffDataByIndex = function(u, i) return U(u) and U(u).buffs[i] end }
_G.C_Spell = {
    GetSpellInfo = function(id) return { name = "Sort" .. id, iconID = 1 } end,
    GetSpellSubtext = function() return "Rang 1" end,
    IsSpellInRange = function(_, u) return not (U(u) and U(u).far) end,
}
_G.C_Item = { GetItemCount = function() return 5 end }
_G.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
_G.LOCALIZED_CLASS_NAMES_MALE = {}
local cvars = { nameplateShowFriends = "0" }
local plates, clickThrough = {}, nil
_G.C_NamePlate = {
    GetNamePlateForUnit = function(u) return plates[u] end,
    SetNamePlateFriendlyClickThrough = function(v) clickThrough = v end,
}
_G.C_CVar = { GetCVar = function(k) return cvars[k] end, SetCVar = function(k, v) cvars[k] = tostring(v) end }
local optionsPanel
_G.Settings = {
    RegisterCanvasLayoutCategory = function(panel) optionsPanel = panel; return newObject() end,
    RegisterAddOnCategory = noop,
    OpenToCategory = noop,
}
local printed = {}
_G.SPELL_FAILED_LINE_OF_SIGHT = "La cible n'est pas en vue"
_G.print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

-- Chargement dans l'ordre du .toc ---------------------------------------------
local ns = {}
for line in io.lines("FriendlyBuffer.toc") do
    if line:match("%.lua$") then
        assert(loadfile((line:gsub("\\", "/"))))("FriendlyBuffer", ns)
    end
end

local function eventFrame()
    for _, o in ipairs(created) do
        if o.events.PLAYER_LOGIN then return o end
    end
end
local ev = eventFrame()
local function fire(event, ...) ev.scripts.OnEvent(ev, event, ...) end
local function tick() ev.scripts.OnUpdate(ev, 1.1) end

local failures = 0
local function check(cond, msg)
    if not cond then failures = failures + 1; io.stdout:write("ECHEC  " .. msg .. "\n") end
end

-- Connexion + premier scan ----------------------------------------------------
fire("PLAYER_LOGIN")
local function printedMatch(pattern)
    for _, line in ipairs(printed) do if line:match(pattern) then return true end end
    return false
end
check(printedMatch("chargé"), "message de chargement")
check(printedMatch("barres de nom alliées"), "avertissement barres de nom désactivées")
local row = function(i) return _G["FriendlyBufferRow" .. i] end
check(row(1).row and row(1).row.name == "Garrosh", "ligne 1 = Garrosh")
check(row(2).row and row(2).row.name == "Jaina" and row(2).row.need.family == "spirit", "ligne 2 = Jaina / esprit")
check(row(3).row and row(3).row.name == "Moi", "ligne 3 = soi-même")
check(row(4).row and row(4).row.name == "Valeera Sanguinar", "ligne 4 = inconnu, prénom + nom séparés par un espace")
check(row(5).shown == false, "ligne 5 masquée (joueur hors de portée exclu)")
check(row(1).attrs.type1 == "macro" and row(1).attrs.macrotext1 == "/cast [@party1] Sort10938(Rang 1)", "groupe : /cast [@unité], sans ciblage")
local STRANGER = "/cleartarget\n/targetexact Valeera Sanguinar\n/cast [@target,help,nodead] Sort10938(Rang 1)\n"
check(row(4).attrs.type1 == "macro" and row(4).attrs.macrotext1 == STRANGER .. "/targetlasttarget", "inconnu : ciblage par prénom nom")
check(FriendlyBufferFrame.shown, "fenêtre visible")
check(row(1).attrs["alt-type1"] == "macro" and row(1).attrs["alt-macrotext1"] == "/target party1", "Alt+clic : sélectionne un membre du groupe")
check(row(4).attrs["alt-macrotext1"] == "/targetexact Valeera Sanguinar", "Alt+clic : sélectionne un inconnu")

-- Obstacle : clic sur Valeera puis erreur « pas en vue » -> grisée et en bas de liste
row(4).scripts.PostClick(row(4), "LeftButton")
fire("UI_ERROR_MESSAGE", 0, SPELL_FAILED_LINE_OF_SIGHT)
tick()
check(row(4).row.name == "Valeera Sanguinar" and row(4).row.blocked == true and row(4).alpha < 1, "obstacle : ligne grisée")
now = now + 6
tick()
check(row(4).row.blocked ~= true and row(4).alpha == 1, "obstacle : levé après quelques secondes")

-- PreClick sans cible -> on ne revient pas à une ancienne cible
row(4).scripts.PreClick(row(4), "LeftButton")
check(row(4).attrs.macrotext1 == STRANGER .. "/cleartarget", "PreClick sans cible : /cleartarget")

-- PreClick : l'unité de groupe a changé de joueur -> on la recale
units.party1, units.party2 = units.party2, units.party1
row(1).scripts.PreClick(row(1), "LeftButton")
check(row(1).attrs.macrotext1 == "/cast [@party2] Sort10938(Rang 1)", "PreClick : unité de groupe recalée sur le bon GUID")
units.party1, units.party2 = units.party2, units.party1
tick()

-- Combat : les inconnus restent cliquables (ciblage par nom)
fire("PLAYER_REGEN_DISABLED")
inCombat = true
check(row(4).attrs.type1 == "macro" and row(4).done == false, "combat : inconnu toujours actif")-- Combat : Garrosh reçoit le buff, attributs figés, ligne marquée faite
units.party1.buffs = { { spellId = 10938, sourceUnit = "player", duration = 1800, expirationTime = 2700 } }
tick()
check(row(1).done == true and row(1).attrs.macrotext1 == "/cast [@party1] Sort10938(Rang 1)", "combat : ligne faite, attributs inchangés")

-- Fin de combat : reconstruction
inCombat = false
fire("PLAYER_REGEN_ENABLED")
check(row(1).row.name == "Jaina" and row(1).done == false, "après combat : Jaina en tête")
check(row(3).row.name == "Valeera Sanguinar" and row(4).shown == false, "après combat : 3 lignes")

-- Groupe : option buffs de groupe
ns.db.groupBuffs = true
ns.OnSettingsChanged()
check(row(1).attrs.macrotext1:match("Sort27681") and row(1).attrs.macrotext2:match("Sort27841"), "clic gauche groupe / clic droit individuel")

-- Options : affichage puis tous les boutons/cases cliqués deux fois
optionsPanel.scripts.OnShow(optionsPanel)
for _ = 1, 2 do
    for _, o in ipairs(created) do
        if o.scripts.OnClick and not o.frameName:match("^FriendlyBufferRow") then o.scripts.OnClick(o, "LeftButton") end
    end
end
-- Listes déroulantes : on choisit la dernière valeur de chacune
local dropdowns = 0
for _, o in ipairs(created) do
    local radio = rawget(o, "radio")
    if radio then
        dropdowns = dropdowns + 1
        local last = radio.items[#radio.items][2]
        radio.setSelected(last)
        check(radio.isSelected(last), "liste déroulante : valeur choisie sélectionnée")
    end
end
check(dropdowns == 4, "4 listes déroulantes (affichage, police, contour, classe)")
check(ns.db.displayMode == "info" and ns.db.plateFont == "morpheus" and ns.db.plateOutline == "thick", "options : choix appliqués")
ns.db.plateFont, ns.db.plateFontSize, ns.db.plateOutline, ns.db.plateShadow, ns.db.plateGuild = "friz", 12, "none", true, true
for i = 1, 4 do if row(i).scripts.OnEnter then row(i).scripts.OnEnter(row(i)) end end

-- Barres de nom invisibles
local uf = newObject()
uf.healthBar = newObject(); uf.name = newObject(); uf.border = newObject()
uf.children = { uf.healthBar }; uf.regions = { uf.name, uf.border }; uf.name.parent = uf
plates.nameplate1 = { UnitFrame = uf }
ns.db.hiddenPlates = true
ns.OnSettingsChanged()
check(cvars.nameplateShowFriends == "1" and clickThrough == true, "barres invisibles : CVar + clic traversant")
check(uf.healthBar.alpha == 0 and uf.border.alpha == 0 and uf.name.alpha ~= 0 and uf.alpha ~= 0, "barres invisibles : barre masquée, nom visible")
check(uf.name.color and uf.name.color[3] == 1 and uf.name.color[1] == 0, "nom coloré comme sans Maj+V (UnitSelectionColor)")
local fo = uf.name.fontObject
check(type(fo) == "table" and fo.members[1].file == "Fonts\\FRIZQT__.TTF" and fo.members[1].height == 12 and fo.members[1].flags == "" and uf.name.shadow[1] == 1, "style par défaut : Friz 12, sans contour, ombre")
check(type(fo) == "table" and fo.members[4].alphabet == "simplifiedchinese" and fo.members[4].file == "Fonts\\ARKai_T.ttf", "police de secours pour le chinois")
check(uf.friendlyBufferGuild and uf.friendlyBufferGuild.text == "<Les Gardiens>" and uf.friendlyBufferGuild.shown, "guilde affichée sous le nom")
ns.db.plateOutline, ns.db.plateFontSize, ns.db.plateShadow, ns.db.plateFont = "thick", 14, false, "arial"
ns.OnSettingsChanged()
fo = uf.name.fontObject
check(fo.members[1].file == "Fonts\\ARIALN.TTF" and fo.members[1].height == 14 and fo.members[1].flags == "THICKOUTLINE" and uf.name.shadow[1] == 0, "style personnalisé appliqué")
CompactUnitFrame_UpdateName(uf); if blizzardHooks.CompactUnitFrame_UpdateName then blizzardHooks.CompactUnitFrame_UpdateName(uf) end
check(uf.name.color[1] == 0, "couleur réappliquée après une mise à jour de Blizzard")
fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
check(uf.healthBar.alpha == 1 and uf.border.alpha == 1 and uf.name.color[1] == 1, "barre recyclée : visibilité et couleur d'origine rendues")
check(uf.name.fontObject == "ORIG_OBJ" and uf.friendlyBufferGuild.shown == false, "barre recyclée : police d'origine rendue, guilde masquée")
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(uf.healthBar.alpha == 0 and uf.name.alpha ~= 0, "nouvelle barre alliée : barre masquée, nom visible")
ns.db.hiddenPlates = false
ns.OnSettingsChanged()
check(uf.healthBar.alpha == 1 and clickThrough == false, "option coupée : barres restaurées")

-- Commandes
printed = {}
SlashCmdList.FRIENDLYBUFFER("debug")
check(printedMatch("candidats"), "/fb debug affiche le bilan du scan")
cvars.nameplateShowFriends = "0"
SlashCmdList.FRIENDLYBUFFER("plaques")
check(cvars.nameplateShowFriends == "1", "/fb plaques active les barres de nom alliées")
SlashCmdList.FRIENDLYBUFFER("options")
SlashCmdList.FRIENDLYBUFFER("reset")
SlashCmdList.FRIENDLYBUFFER("")
check(ns.db.hidden == true and FriendlyBufferFrame.shown == false, "/fb masque la fenêtre")
SlashCmdList.FRIENDLYBUFFER("")
check(ns.db.hidden == false, "/fb réaffiche")

print = io.write
if failures == 0 then io.stdout:write("smoke : OK\n") else io.stdout:write("smoke : " .. failures .. " échec(s)\n"); os.exit(1) end
