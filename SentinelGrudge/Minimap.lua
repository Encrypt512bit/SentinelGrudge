-- Sentinel Grudge minimap button: self-contained (no LibDBIcon). Left-click: list window.
-- Right-click: toggle KOS on-screen alerts. Drag to move around the minimap edge.
local _, G = ...
local btn
local ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local FALLBACK = "Interface\\Icons\\Spell_Shadow_DeathScream"

local function place()
    if not btn then return end
    local angle = math.rad(G.db.settings.minimapAngle or 200)
    local radius = (Minimap:GetWidth() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function counts()
    local kos, friend = 0, 0
    for _, t in pairs(G.db.tags) do
        if t.tag == "KOS" then kos = kos + 1 elseif t.tag == "FRIEND" then friend = friend + 1 end
    end
    return kos, friend
end

local function dragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local deg = math.deg(math.atan2(cy - my, cx - mx)) % 360
    G.db.settings.minimapAngle = deg
    place()
end

function G.BuildMinimap()
    if btn or not Minimap then return end
    btn = CreateFrame("Button", "SentinelGrudgeMinimapButton", Minimap)
    btn:SetSize(31, 31); btn:SetFrameStrata("MEDIUM"); btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp"); btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background"); bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20); icon:SetPoint("TOPLEFT", 7, -5)
    if icon:SetTexture(ICON) == false then icon:SetTexture(FALLBACK) end
    icon:SetTexCoord(.08, .92, .08, .92)
    -- Circular mask where supported (modern API); harmless to skip on older clients.
    pcall(function()
        local mask = btn:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon); icon:AddMaskTexture(mask)
    end)
    btn.icon = icon
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(53, 53); border:SetPoint("TOPLEFT")

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            G.db.settings.alert = not G.db.settings.alert
            G.Print("On-screen KOS warning: " .. (G.db.settings.alert and "ON" or "OFF"))
            if btn.icon.SetDesaturated then btn.icon:SetDesaturated(not G.db.settings.alert) end
        else
            G.ToggleUI()
        end
    end)
    btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragUpdate) end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnEnter", function(self)
        local kos, friend = counts()
        if btn.icon.SetDesaturated then btn.icon:SetDesaturated(not G.db.settings.alert) end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Sentinel Grudge", 1, .35, .35)
        GameTooltip:AddLine("KOS tagged: " .. kos, 1, .4, .4)
        GameTooltip:AddLine("Friendly tagged: " .. friend, .4, 1, .5)
        GameTooltip:AddLine("KOS alerts: " .. (G.db.settings.alert and "|cff33ff33ON|r" or "|cffff3333OFF|r"), 1, 1, 1)
        GameTooltip:AddLine("Auto-untag Friendly on attack: " .. (G.db.settings.autoUntag and "|cff33ff33ON|r" or "|cffff3333OFF|r"), 1, 1, 1)
        GameTooltip:AddLine("Left-click: open list", .7, .7, .7)
        GameTooltip:AddLine("Right-click: toggle KOS alerts", .7, .7, .7)
        GameTooltip:AddLine("Drag: move around minimap", .7, .7, .7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if btn.icon.SetDesaturated then btn.icon:SetDesaturated(not G.db.settings.alert) end
    place()
    if G.db.settings.minimapHide then btn:Hide() end
end

function G.SetMinimap(show)
    G.db.settings.minimapHide = not show
    if show and not btn then G.BuildMinimap() end
    if btn then if show then btn:Show(); place() else btn:Hide() end end
    G.Print("Minimap button " .. (show and "shown" or "hidden (/grudge minimap on to restore)") .. ".")
end
