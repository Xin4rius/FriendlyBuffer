-- Bouton de la minicarte (LibDBIcon, reconnu par les addons qui rangent les boutons) :
-- clic gauche = fenêtre, clic droit = options, glisser = le déplacer autour.
local _, ns = ...
local L = ns.L

local Minimap_ = {}
ns.Minimap = Minimap_

local NAME = "FriendlyBuffer"
local icon

function Minimap_.Refresh()
    if not icon then return end
    ns.db.minimapIcon.hide = not ns.db.minimap
    if ns.db.minimap then icon:Show(NAME) else icon:Hide(NAME) end
end

function Minimap_.Create()
    if icon or not LibStub then return end
    local ldb = LibStub("LibDataBroker-1.1", true)
    local dbicon = LibStub("LibDBIcon-1.0", true)
    if not (ldb and dbicon) then return end
    local launcher = ldb:NewDataObject(NAME, {
        type = "launcher",
        text = NAME,
        icon = "Interface\\AddOns\\FriendlyBuffer\\Media\\icon",
        OnClick = function(_, mouse)
            if mouse == "RightButton" then ns.Options.Open() else ns.ToggleWindow() end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(NAME)
            tooltip:AddLine(L["Left click: show / hide the window"], 1, 1, 1)
            tooltip:AddLine(L["Right click: options"], 1, 1, 1)
            tooltip:AddLine(L["Drag: move this button"], 0.6, 0.6, 0.6)
        end,
    })
    icon = dbicon
    icon:Register(NAME, launcher, ns.db.minimapIcon)
    Minimap_.Refresh()
end
