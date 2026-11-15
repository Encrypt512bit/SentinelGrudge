-- Sentinel Grudge UI: list window and the on-screen KOS warning. No OnUpdate scripts; the list
-- refreshes on a 3-second ticker only while the window is open.
local _, G = ...
local ROWS, ROW_H, W, H = 18, 18, 640, 470
local f, rows, data, offset, selected, ticker, popup
local view = {filter = "ALL", sort = "attacks", search = ""}

local COLS = {
    {key = "name", label = "Name", x = 10, w = 150},
    {key = "tag", label = "Tag", x = 162, w = 55},
    {key = "class", label = "Class / Lvl", x = 219, w = 90},
    {key = "guild", label = "Guild", x = 311, w = 90},
    {key = "attacks", label = "Atk", x = 403, w = 32},
    {key = "seen", label = "Seen", x = 437, w = 36},
    {key = "last", label = "Last seen", x = 475, w = 60},
    {key = "zone", label = "Zone", x = 537, w = 85},
}

local function age(at)
    if not at or at == 0 then return "-" end
    local s = math.max(0, time() - at)
    if s < 3600 then return math.floor(s / 60) .. "m" elseif s < 86400 then return math.floor(s / 3600) .. "h" end
    return math.floor(s / 86400) .. "d"
end
local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return .85, .85, .85
end

local sorters = {
    attacks = function(a, b)
        if a.attacks ~= b.attacks then return a.attacks > b.attacks end
        if a.seen ~= b.seen then return a.seen > b.seen end
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end,
    seen = function(a, b)
        if a.seen ~= b.seen then return a.seen > b.seen end
        return a.attacks > b.attacks
    end,
    recent = function(a, b) return (a.lastSeen or 0) > (b.lastSeen or 0) end,
    name = function(a, b) return a.name:lower() < b.name:lower() end,
}

local function passes(r)
    local fl = view.filter
    if fl == "ATTACKERS" and r.attacks == 0 then return false end
    if fl == "KOS" and r.tag ~= "KOS" then return false end
    if fl == "FRIEND" and r.tag ~= "FRIEND" then return false end
    if view.search ~= "" then
        local hay = (r.name .. " " .. (r.guild or "") .. " " .. (r.zone or "") .. " " .. (r.class or "")):lower()
        if not hay:find(view.search, 1, true) then return false end
    end
    return true
end

local function render()
    if not f or not f:IsShown() then return end
    local total = #data
    offset = math.max(0, math.min(offset, total - ROWS))
    for i = 1, ROWS do
        local row, r = rows[i], data[i + offset]
        if r then
            row.r = r
            local c = row.cells
            c.name:SetText(r.name); c.name:SetTextColor(classColor(r.class))
            c.tag:SetText(r.tag and (G.TagText[r.tag] .. (r.fromSentinel and "*" or "")) or "")
            c.class:SetText(r.class and G.ClassLabel(r.class, r.level) or (r.level and ("Lvl " .. r.level) or ""))
            c.guild:SetText(r.guild or "")
            c.attacks:SetText(r.attacks > 0 and ("|cffff7755" .. r.attacks .. "|r") or "0")
            c.seen:SetText(r.seen)
            c.last:SetText(age(r.lastSeen))
            c.zone:SetText(r.zone or "")
            row.sel:SetShown(selected ~= nil and selected == (r.key or r.bare))
            row:Show()
        else
            row.r = nil; row:Hide()
        end
    end
    local filterLabel = ({ALL = "All", ATTACKERS = "Attackers", KOS = "KOS", FRIEND = "Friendly"})[view.filter]
    f.status:SetText(string.format("%s | sort: %s | %d-%d of %d%s", filterLabel, view.sort,
        total == 0 and 0 or offset + 1, math.min(total, offset + ROWS), total,
        G.Sentinel() and "" or "  |cffff5555(Sentinel data not loaded)|r"))
    for k, b in pairs(f.filterButtons) do b:SetAlpha(k == view.filter and 1 or .6) end
    for k, b in pairs(f.sortButtons) do b:SetAlpha(k == view.sort and 1 or .6) end
end

function G.RefreshUI(rebuild)
    if not f or not f:IsShown() then return end
    if rebuild ~= false then
        local list = {}
        for _, r in ipairs(G.BuildRows()) do if passes(r) then list[#list + 1] = r end end
        table.sort(list, sorters[view.sort])
        data = list
    end
    render()
end

local function tagSelected(tag)
    local r
    for _, d in ipairs(data) do if (d.key or d.bare) == selected then r = d break end end
    if not r then G.Print("Select a player in the list first."); return end
    local key = r.tagKey or r.key or r.bare
    if tag then
        if r.tagKey and r.tagKey ~= r.key and r.key then G.db.tags[r.tagKey] = nil; key = r.key end
        G.SetTag(key, r.name, tag)
        G.Print(r.name .. " tagged " .. G.TagText[tag] .. ".")
    else
        if r.tagKey then G.SetTag(r.tagKey, nil, nil); G.Print("Tag removed: " .. r.name)
        elseif r.fromSentinel then G.Print(r.name .. " is on Sentinel's watchlist; remove it there (/fpi) or use /grudge sentinelkos off.")
        else G.Print(r.name .. " has no tag.") end
    end
end

local function button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 20); b:SetText(text); b:SetScript("OnClick", onClick)
    return b
end

local function showPopup(row)
    if not popup then
        popup = CreateFrame("Frame", nil, f)
        popup:SetSize(110, 96); popup:SetFrameStrata("DIALOG")
        local bg = popup:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(.05, .05, .05, .95)
        popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        popup.title:SetPoint("TOP", 0, -4); popup.title:SetWidth(104)
        local items = {{"Tag KOS", "KOS"}, {"Tag Friendly", "FRIEND"}, {"Clear tag", false}}
        for i, it in ipairs(items) do
            local b = button(popup, it[1], 100, function() tagSelected(it[2] or nil); popup:Hide() end)
            b:SetPoint("TOP", 0, -4 - i * 22)
        end
        popup:SetScript("OnHide", nil)
    end
    popup.title:SetText(row.r.name)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 120, 0)
    popup:Show()
end

function G.BuildUI()
    f = CreateFrame("Frame", "SentinelGrudgeFrame", UIParent)
    f:SetSize(W, H); f:SetPoint("CENTER"); f:SetFrameStrata("HIGH")
    f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "SentinelGrudgeFrame")
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, .88)
    local top = f:CreateTexture(nil, "BORDER"); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(24)
    top:SetColorTexture(.35, .05, .05, .9)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -6); title:SetText("Sentinel Grudge  |cffaaaaaa(attackers & sightings from Sentinel PvP)|r")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)

    -- Filters
    f.filterButtons = {}
    local x = 10
    for _, fl in ipairs({{"ALL", "All"}, {"ATTACKERS", "Attackers"}, {"KOS", "KOS"}, {"FRIEND", "Friendly"}}) do
        local b = button(f, fl[2], 74, function() view.filter = fl[1]; offset = 0; G.RefreshUI(true) end)
        b:SetPoint("TOPLEFT", x, -30); x = x + 76
        f.filterButtons[fl[1]] = b
    end
    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(140, 20); search:SetPoint("TOPRIGHT", -14, -30); search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self) view.search = (self:GetText() or ""):lower(); offset = 0; G.RefreshUI(true) end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local sl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); sl:SetPoint("RIGHT", search, "LEFT", -8, 0); sl:SetText("Search")

    -- Sort
    f.sortButtons = {}
    x = 10
    local sortLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    for _, s in ipairs({{"attacks", "Attacks"}, {"seen", "Seen"}, {"recent", "Recent"}, {"name", "Name"}}) do
        local b = button(f, s[2], 74, function() view.sort = s[1]; offset = 0; G.RefreshUI(true) end)
        b:SetPoint("TOPLEFT", x, -54); x = x + 76
        f.sortButtons[s[1]] = b
    end
    sortLabel:SetPoint("LEFT", f.sortButtons.name, "RIGHT", 8, 0); sortLabel:SetText("<- sort")

    -- Header
    for _, c in ipairs(COLS) do
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", c.x, -82); h:SetWidth(c.w); h:SetJustifyH("LEFT"); h:SetText(c.label)
    end

    -- Rows
    rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(W - 16, ROW_H); row:SetPoint("TOPLEFT", 6, -96 - (i - 1) * ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, .08)
        row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints(); row.sel:SetColorTexture(.8, .2, .2, .25); row.sel:Hide()
        if i % 2 == 0 then local z = row:CreateTexture(nil, "BACKGROUND", nil, -1); z:SetAllPoints(); z:SetColorTexture(1, 1, 1, .03) end
        row.cells = {}
        for _, c in ipairs(COLS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", c.x - 4, 0); fs:SetWidth(c.w); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
            row.cells[c.key] = fs
        end
        row:SetScript("OnClick", function(self, btn)
            if not self.r then return end
            selected = self.r.key or self.r.bare
            render()
            if btn == "RightButton" then showPopup(self) elseif popup then popup:Hide() end
        end)
        row:SetScript("OnEnter", function(self)
            local r = self.r; if not r then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.name, classColor(r.class))
            if r.race or r.class then GameTooltip:AddLine(((r.race or "") .. " " .. G.ClassLabel(r.class, r.level)), 1, 1, 1) end
            if r.guild then GameTooltip:AddLine("<" .. r.guild .. ">", .6, 1, .6) end
            GameTooltip:AddLine(string.format("Attacked you in %d fight%s (you died in %d)", r.attacks, r.attacks == 1 and "" or "s", r.deaths), 1, .6, .4)
            GameTooltip:AddLine("Seen " .. r.seen .. " times (Sentinel encounters)", .8, .8, .8)
            if r.firstSeen then GameTooltip:AddLine("First seen " .. date("%Y-%m-%d %H:%M", r.firstSeen), .7, .7, .7) end
            if r.lastSeen then GameTooltip:AddLine("Last seen " .. date("%Y-%m-%d %H:%M", r.lastSeen) .. (r.zone and (" in " .. r.zone) or ""), .7, .7, .7) end
            if r.kills and r.kills > 0 then GameTooltip:AddLine("You killed them " .. r.kills .. "x", .4, 1, .4) end
            if r.note and r.note ~= "" then GameTooltip:AddLine("Sentinel note: " .. r.note, .8, .8, .5, true) end
            if r.fromSentinel then GameTooltip:AddLine("KOS from Sentinel watchlist", 1, .8, .4) end
            GameTooltip:AddLine("Right-click: tag KOS / Friendly / clear", .5, .5, .5)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = row
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 3; render() end)

    -- Bottom bar
    local by = 12
    local b1 = button(f, "KOS", 60, function() tagSelected("KOS") end); b1:SetPoint("BOTTOMLEFT", 10, by)
    local b2 = button(f, "Friendly", 70, function() tagSelected("FRIEND") end); b2:SetPoint("LEFT", b1, "RIGHT", 4, 0)
    local b3 = button(f, "Clear tag", 70, function() tagSelected(nil) end); b3:SetPoint("LEFT", b2, "RIGHT", 4, 0)
    local b4 = button(f, "Target -> KOS", 100, function() SlashCmdList.SENTINELGRUDGE("kos") end); b4:SetPoint("LEFT", b3, "RIGHT", 12, 0)
    local up = button(f, "Up", 40, function() offset = offset - ROWS; render() end); up:SetPoint("BOTTOMRIGHT", -56, by)
    local dn = button(f, "Down", 46, function() offset = offset + ROWS; render() end); dn:SetPoint("LEFT", up, "RIGHT", 2, 0)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 10, by + 24)

    data, offset = {}, 0
    f:SetScript("OnShow", function()
        G.RefreshUI(true)
        if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(3, function() G.RefreshUI(true) end) end
    end)
    f:SetScript("OnHide", function()
        if ticker then ticker:Cancel(); ticker = nil end
        if popup then popup:Hide() end
    end)
    G.BuildWarning()
end

function G.ToggleUI()
    if not f then return end
    if f:IsShown() then f:Hide() else f:Show() end
end

-- On-screen KOS warning (movable, fades via an animation, no OnUpdate) ----------------------------
local warn, anim
function G.PlaceWarning()
    if not warn then return end
    warn:ClearAllPoints()
    local p = G.db and G.db.settings.alertPos
    if type(p) == "table" and p[1] then warn:SetPoint(p[1], UIParent, p[1], p[2] or 0, p[3] or 0)
    else warn:SetPoint("CENTER", UIParent, "CENTER", 0, 220) end
end
function G.BuildWarning()
    warn = CreateFrame("Frame", "SentinelGrudgeWarning", UIParent)
    warn:SetSize(700, 70); warn:SetFrameStrata("HIGH"); warn:SetMovable(true); warn:SetClampedToScreen(true)
    warn:RegisterForDrag("LeftButton"); warn:Hide()
    warn.bg = warn:CreateTexture(nil, "BACKGROUND"); warn.bg:SetAllPoints(); warn.bg:SetColorTexture(.3, 0, 0, .5); warn.bg:Hide()
    warn.text = warn:CreateFontString(nil, "OVERLAY")
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    pcall(warn.text.SetFont, warn.text, font, 30, "THICKOUTLINE")
    if not warn.text:GetFont() then warn.text:SetFontObject("GameFontNormalHuge") end
    warn.text:SetPoint("TOP", 0, -4); warn.text:SetTextColor(1, .15, .15)
    warn.sub = warn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    warn.sub:SetPoint("TOP", warn.text, "BOTTOM", 0, -4); warn.sub:SetTextColor(1, .8, .8)
    warn:SetScript("OnDragStart", warn.StartMoving)
    warn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        G.db.settings.alertPos = {point, x, y}
    end)
    G.PlaceWarning()
    local ok = pcall(function()
        anim = warn:CreateAnimationGroup()
        local a = anim:CreateAnimation("Alpha")
        a:SetFromAlpha(1); a:SetToAlpha(0); a:SetStartDelay(4); a:SetDuration(1.5)
        anim:SetScript("OnFinished", function() if not warn.unlocked then warn:Hide() end; warn:SetAlpha(1) end)
    end)
    if not ok then anim = nil end
end
function G.ShowWarning(headline, detail)
    if not warn then return end
    warn.text:SetText(headline); warn.sub:SetText(detail or "")
    warn:SetAlpha(1); warn:Show()
    if anim then anim:Stop(); anim:Play()
    elseif C_Timer and C_Timer.After then
        warn.token = (warn.token or 0) + 1
        local t = warn.token
        C_Timer.After(5, function() if warn.token == t and not warn.unlocked then warn:Hide() end end)
    end
    -- Also flash it in the standard raid-warning area if available.
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING and G.db.settings.raidNotice then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, headline, ChatTypeInfo.RAID_WARNING)
    end
end
function G.UnlockWarning(unlock)
    if not warn then return end
    warn.unlocked = unlock
    warn:EnableMouse(unlock)
    if unlock then
        if anim then anim:Stop() end
        warn.text:SetText("KOS WARNING - drag me"); warn.sub:SetText("/grudge alert lock when done")
        warn.bg:Show(); warn:SetAlpha(1); warn:Show()
        G.Print("Warning unlocked: drag it, then /grudge alert lock.")
    else
        warn.bg:Hide(); warn:Hide()
        G.Print("Warning position locked.")
    end
end
