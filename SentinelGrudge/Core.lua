-- Sentinel Grudge: reads Forever Sentinel PVP's own records (ForeverPvPIntelDB) for sightings and
-- world PvP fights, and adds KOS/Friendly tags, guild capture and on-screen KOS warnings.
-- Sentinel's data is only ever READ here; tags live in SentinelGrudgeDB (account-wide).
local ADDON, G = ...
G.version = "1.2.0"

local defaults = {
    alert = true,          -- big on-screen KOS warning
    sound = true,          -- warning sound with the KOS warning
    chat = true,           -- chat line with KOS warning
    attackerAlert = true,  -- chat line when a past attacker (not KOS) is seen again
    sentinelKos = true,    -- treat Sentinel's own watchlist (KoS) entries as KOS
    tooltip = true,
    raidNotice = false,
    autoUntag = true,      -- remove a Friendly tag when that player attacks you    -- also show the text in the standard raid-warning area
    kosThrottle = 60,      -- seconds between KOS warnings for the same player
    attackerThrottle = 300,
}

-- Safe API access (this client can return restricted "secret" values) ---------------------------
local function pub(v)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return pub(a), pub(b), pub(c), pub(d)
end
G.pub, G.safe = pub, safe

function G.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Grudge:|r " .. tostring(msg))
end
function G.Now() return time() end
function G.Sentinel()
    local s = _G.ForeverPvPIntelDB
    if type(s) == "table" and type(s.players) == "table" then return s end
end

-- Identity keys: "name-realm", lowercase, spaces removed. Bare "name" when the realm is unknown.
local function ownRealm()
    local r = safe(GetRealmName)
    return type(r) == "string" and r or ""
end
function G.KeyFromParts(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) ~= "string" or realm == "" then realm = ownRealm() end
    local key = (name .. "-" .. realm):gsub("%s", ""):lower()
    return key, (name:lower())
end
-- "Name-Realm Name" -> key, bare. A name with no realm is returned bare (key=nil).
function G.KeyFromFull(full)
    if type(full) ~= "string" or full == "" then return nil end
    full = full:gsub("^%s+", ""):gsub("%s+$", "")
    local n, r = full:match("^([^%-]+)%-(.+)$")
    if n then
        local key = (n .. "-" .. r):gsub("%s", ""):lower()
        return key, n:lower()
    end
    return nil, full:lower()
end
function G.UnitIdentity(unit)
    local name, realm = safe(UnitFullName, unit)
    if type(name) ~= "string" or name == "" then name, realm = safe(UnitName, unit) end
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) ~= "string" or realm == "" then realm = ownRealm() end
    local key, bare = G.KeyFromParts(name, realm)
    local guid = safe(UnitGUID, unit)
    if type(guid) ~= "string" or not guid:match("^Player%-") then guid = nil end
    -- Prefer Sentinel's stored name for this GUID so keys always match its records.
    local s = guid and G.Sentinel()
    local p = s and s.players[guid]
    if p and type(p.name) == "string" then
        local k2, b2 = G.KeyFromFull(p.name)
        if k2 then return k2, b2, p.name, guid end
    end
    return key, bare, name .. "-" .. realm, guid
end

-- Init ------------------------------------------------------------------------------------------
function G.Init()
    if type(SentinelGrudgeDB) ~= "table" then SentinelGrudgeDB = {} end
    G.db = SentinelGrudgeDB
    for _, k in ipairs({"settings", "tags", "extra"}) do
        if type(G.db[k]) ~= "table" then G.db[k] = {} end
    end
    for k, v in pairs(defaults) do
        if type(G.db.settings[k]) ~= type(v) then G.db.settings[k] = v end
    end
    -- Keep the guild cache small: drop the oldest entries beyond 3000.
    local list = {}
    for k, e in pairs(G.db.extra) do
        if type(e) ~= "table" then G.db.extra[k] = nil else list[#list + 1] = {k = k, t = e.t or 0} end
    end
    if #list > 3000 then
        table.sort(list, function(a, b) return a.t < b.t end)
        for i = 1, #list - 3000 do G.db.extra[list[i].k] = nil end
    end
end

-- Tags --------------------------------------------------------------------------------------------
-- Returns tag record ("KOS"/"FRIEND") for a key/bare name, migrating bare tags to full keys.
function G.GetTag(key, bare, fullName)
    local T = G.db and G.db.tags
    if not T then return nil end
    if key and T[key] then return T[key] end
    if bare and T[bare] then
        local t = T[bare]
        if key and fullName then
            T[bare] = nil; T[key] = t; t.name = fullName
        end
        return t
    end
end
function G.SetTag(key, name, tag)
    if not key then return end
    if tag then
        G.db.tags[key] = {tag = tag, name = name, at = G.Now()}
    else
        G.db.tags[key] = nil
    end
    G.alerted[key] = nil
    if G.RefreshUI then G.RefreshUI(true) end
end
local TAGNAMES = {KOS = "|cffff3333KOS|r", FRIEND = "|cff33ff66Friendly|r"}
G.TagText = TAGNAMES

-- Sentinel data aggregation ---------------------------------------------------------------------
-- "Attacked you" = a recorded Sentinel world PvP fight in which this enemy targeted you while you
-- were in combat (enemy.targetedYou). Sentinel cannot attribute damage (no combat log on this
-- client), so this is the best attack signal it records. "Died" = that fight also had your death.
local attack = {sig = nil, byGuid = {}}
local function historySig(h)
    if type(h) ~= "table" then return "none" end
    local first = h[1]
    return #h .. ":" .. tostring(first and first.at) .. ":" .. tostring(first and first.ended)
end
function G.AttackData()
    local s = G.Sentinel()
    local h = s and s.worldHistory
    local sig = historySig(h)
    if sig == attack.sig then return attack.byGuid end
    local by = {}
    if type(h) == "table" then
        for _, rec in ipairs(h) do
            if type(rec) == "table" and type(rec.enemies) == "table" then
                for _, e in ipairs(rec.enemies) do
                    if type(e) == "table" and e.targetedYou and type(e.guid) == "string" then
                        local a = by[e.guid]
                        if not a then
                            a = {attacks = 0, deaths = 0, last = 0, name = e.name, class = e.class, level = e.level, race = e.race}
                            by[e.guid] = a
                        end
                        a.attacks = a.attacks + 1
                        if (rec.deaths or 0) > 0 then a.deaths = a.deaths + 1 end
                        if (rec.at or 0) > a.last then a.last = rec.at or 0; a.zone = rec.zone end
                    end
                end
            end
        end
    end
    attack.sig, attack.byGuid = sig, by
    return by
end

-- Stats for a single player (tooltip/alerts). guid may be nil.
function G.Stats(guid, key)
    local s = G.Sentinel()
    local p = s and guid and s.players[guid]
    if not p and s and key then p = s.players["LocalName:" .. key] end
    local a = guid and G.AttackData()[guid]
    return {
        seen = p and p.encounters or 0,
        attacks = a and a.attacks or 0,
        deaths = a and a.deaths or 0,
        lastSeen = p and p.lastSeen,
        zone = p and p.zone,
        sentinelKos = p and p.kos or false,
        class = p and p.class or (a and a.class),
        level = p and p.level or (a and a.level),
    }
end

-- Full list for the window: Sentinel players + attackers + tags.
function G.BuildRows()
    local rows, byGuid, byKey, byBare = {}, {}, {}, {}
    local s = G.Sentinel()
    local function add(key, bare, guid)
        local r = {key = key, bare = bare, guid = guid, seen = 0, attacks = 0, deaths = 0}
        rows[#rows + 1] = r
        if guid then byGuid[guid] = r end
        if key then byKey[key] = r end
        if bare and not byBare[bare] then byBare[bare] = r end
        return r
    end
    if s then
        for guid, p in pairs(s.players) do
            if type(p) == "table" and type(p.name) == "string" then
                local key, bare = G.KeyFromFull(p.name)
                local r = add(key, bare, guid)
                r.name, r.class, r.level, r.race = p.name, p.class, p.level, p.race
                r.seen, r.firstSeen, r.lastSeen, r.zone = p.encounters or 0, p.firstSeen, p.lastSeen, p.zone
                r.kills, r.sentinelKos, r.note = p.kills, p.kos, p.note
            end
        end
    end
    for guid, a in pairs(G.AttackData()) do
        local r = byGuid[guid]
        if not r then
            local key, bare = G.KeyFromFull(a.name)
            r = byKey[key or ""] or add(key, bare, guid)
            r.name = r.name or a.name; r.class = r.class or a.class; r.level = r.level or a.level
            r.race = r.race or a.race; r.zone = r.zone or a.zone
        end
        r.attacks, r.deaths, r.lastAttack = a.attacks, a.deaths, a.last
        if not r.lastSeen or a.last > r.lastSeen then r.lastSeen = a.last end
    end
    for k, t in pairs(G.db.tags) do
        local r = byKey[k] or byBare[k]
        if not r then
            local key, bare = G.KeyFromFull(t.name)
            r = add(key or k, bare or k, nil)
            r.name = t.name or k
        end
        r.tag = t.tag; r.tagKey = k
    end
    for _, r in ipairs(rows) do
        local e = r.key and G.db.extra[r.key]
        if e then r.guild = e.g end
        if not r.tag and r.sentinelKos and G.db.settings.sentinelKos then r.tag = "KOS"; r.fromSentinel = true end
        r.name = r.name or r.key or "?"
    end
    return rows
end

-- Detection / alerts ------------------------------------------------------------------------------
G.alerted, G.attackerAlerted, G.lastCheck = {}, {}, {}
local function classLabel(class, level)
    local c = type(class) == "string" and (class:sub(1, 1) .. class:sub(2):lower()) or "?"
    return c .. " " .. (level and tostring(level) or "?")
end
G.ClassLabel = classLabel

function G.CheckUnit(unit, source)
    if not G.db or type(unit) ~= "string" then return end
    if safe(UnitIsPlayer, unit) ~= true then return end
    if safe(UnitIsUnit, unit, "player") == true then return end
    local key, bare, full, guid = G.UnitIdentity(unit)
    if not key then return end
    local now = G.Now()
    if G.lastCheck[key] and now - G.lastCheck[key] < 2 then return end
    G.lastCheck[key] = now
    local hostile = safe(UnitCanAttack, "player", unit) == true
    -- Guild is something Sentinel does not store: remember it for hostile or tagged players.
    local tag = G.GetTag(key, bare, full)
    if hostile or tag then
        local guild = safe(GetGuildInfo, unit)
        local e = G.db.extra[key]
        if type(guild) == "string" and guild ~= "" then
            G.db.extra[key] = {g = guild, t = now}
        elseif e then e.t = now end
    end
    local st = G.Stats(guid, key)
    local isKos = (tag and tag.tag == "KOS") or (not tag and st.sentinelKos and G.db.settings.sentinelKos)
    if isKos then
        if not G.alerted[key] or now - G.alerted[key] >= G.db.settings.kosThrottle then
            G.alerted[key] = now
            local _, class = safe(UnitClass, unit)
            local level = safe(UnitLevel, unit)
            if type(level) == "number" and level <= 0 then level = "??" end
            G.KosWarning(full, class or st.class, level or st.level, st, source)
        end
    elseif hostile and st.attacks > 0 and G.db.settings.attackerAlert and not (tag and tag.tag == "FRIEND") then
        if not G.attackerAlerted[key] or now - G.attackerAlerted[key] >= G.db.settings.attackerThrottle then
            G.attackerAlerted[key] = now
            G.Print(string.format("|cffffaa33%s|r (attacked you %dx, seen %dx) spotted.", full, st.attacks, st.seen))
        end
    end
end

function G.KosWarning(full, class, level, st, source)
    local s = G.db.settings
    local headline = "KOS: " .. full .. " (" .. classLabel(class, level) .. ")"
    local detail = string.format("attacked you %dx | seen %dx", st and st.attacks or 0, st and st.seen or 0)
    if s.alert and G.ShowWarning then G.ShowWarning(headline, detail) end
    if s.sound then
        local id = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
        safe(PlaySound, id, "Master")
    end
    if s.chat then G.Print("|cffff3333" .. headline .. "|r " .. detail .. (source and (" [" .. source .. "]") or "")) end
end

-- Friendly-tag auto removal ---------------------------------------------------------------------
-- Removes a Friendly tag (never adds KOS) when that player attacks you. Signals: new Sentinel
-- world PvP fights where they targeted you in combat, the combat log (only if the client has
-- one) and a hostile Friendly-tagged unit in combat targeting you while you are in combat.
function G.FriendAttacked(key, bare, fullName, via, at)
    if not G.db or not G.db.settings.autoUntag then return end
    local T = G.db.tags
    local k = (key and T[key]) and key or ((bare and T[bare]) and bare or nil)
    local t = k and T[k]
    if not t or t.tag ~= "FRIEND" then return end
    -- Ignore fights that happened before the player was tagged Friendly.
    if at and t.at and at < t.at then return end
    G.SetTag(k, nil, nil)
    G.Print("|cffffaa33" .. (t.name or fullName or k) .. "|r attacked you, Friendly tag removed. (" .. via .. ")")
end

-- Sentinel fight records: process fights newer than the last scan (newest are at index 1).
function G.ScanSentinelFights()
    local s = G.Sentinel()
    local h = s and s.worldHistory
    if not G.db or type(h) ~= "table" then return end
    local newest = h[1] and h[1].at
    local last = G.db.lastFightScan
    if last then
        for _, rec in ipairs(h) do
            if type(rec) ~= "table" or (rec.at or 0) <= last then break end
            for _, e in ipairs(type(rec.enemies) == "table" and rec.enemies or {}) do
                if type(e) == "table" and e.targetedYou and type(e.name) == "string" then
                    local key, bare = G.KeyFromFull(e.name)
                    G.FriendAttacked(key, bare, e.name, "Sentinel fight record", rec.at)
                end
            end
        end
    end
    if newest and (not last or newest > last) then G.db.lastFightScan = newest
    elseif not last then G.db.lastFightScan = G.Now() end
end

-- A hostile Friendly-tagged unit, in combat, targeting you while you are in combat.
local targetThrottle = {}
function G.CheckFriendTargeting(unit)
    if not G.db or not G.db.settings.autoUntag or type(unit) ~= "string" then return end
    if not (InCombatLockdown and InCombatLockdown()) then return end
    if safe(UnitIsPlayer, unit) ~= true or safe(UnitCanAttack, "player", unit) ~= true then return end
    if safe(UnitIsUnit, unit .. "target", "player") ~= true then return end
    if safe(UnitAffectingCombat, unit) == false then return end
    local key, bare, full = G.UnitIdentity(unit)
    if not key then return end
    local now = G.Now()
    if targetThrottle[key] and now - targetThrottle[key] < 2 then return end
    targetThrottle[key] = now
    G.FriendAttacked(key, bare, full, "targeted you in combat")
end

-- Tooltip ---------------------------------------------------------------------------------------
local function addTooltip(tt)
    if not G.db or not G.db.settings.tooltip or tt ~= GameTooltip then return end
    local _, unit = safe(tt.GetUnit, tt)
    if type(unit) ~= "string" or safe(UnitIsPlayer, unit) ~= true then return end
    if safe(UnitIsUnit, unit, "player") == true then return end
    local key, bare, full, guid = G.UnitIdentity(unit)
    if not key then return end
    local tag = G.GetTag(key, bare, full)
    local hostile = safe(UnitCanAttack, "player", unit) == true
    if not tag and not hostile then return end
    local st = G.Stats(guid, key)
    local parts = {}
    if tag then parts[#parts + 1] = TAGNAMES[tag.tag] or tag.tag
    elseif st.sentinelKos and G.db.settings.sentinelKos then parts[#parts + 1] = TAGNAMES.KOS end
    parts[#parts + 1] = string.format("Attacked you %d time%s, seen %d time%s",
        st.attacks, st.attacks == 1 and "" or "s", st.seen, st.seen == 1 and "" or "s")
    if st.deaths > 0 then parts[#parts + 1] = "you died in " .. st.deaths end
    tt:AddLine("|cffff5555Grudge:|r " .. table.concat(parts, " | "), 1, 1, 1, true)
    return true
end
local hooked = false
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt) pcall(addTooltip, tt) end)
end
if not hooked and GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt)
        local ok, added = pcall(addTooltip, tt)
        if ok and added then tt:Show() end
    end)
end

-- Slash commands --------------------------------------------------------------------------------
local function resolveName(arg)
    -- Returns key, displayName. With no name, uses the current target.
    if not arg or arg == "" then
        if safe(UnitIsPlayer, "target") ~= true then return nil end
        local key, _, full = G.UnitIdentity("target")
        return key, full
    end
    local key, bare = G.KeyFromFull(arg)
    if key then return key, arg end
    -- Bare name: find it in Sentinel's records (most recently seen wins).
    local best, bestSeen, count = nil, -1, 0
    for _, r in ipairs(G.BuildRows()) do
        if r.bare == bare and r.key then
            count = count + 1
            if (r.lastSeen or 0) > bestSeen then best, bestSeen = r, r.lastSeen or 0 end
        end
    end
    if best then
        if count > 1 then G.Print("Several players named " .. arg .. "; using " .. best.name .. ". Use Name-Realm to pick another.") end
        return best.key, best.name
    end
    -- Unknown realm: store bare; it upgrades to Name-Realm the first time the player is seen.
    local nice = arg:sub(1, 1):upper() .. arg:sub(2):lower()
    return bare, nice
end

local HELP = {
    "/grudge  - open/close the list (sort by attacks, seen, recent; filter by tag)",
    "/grudge kos [name]  - tag KOS (no name = current target)",
    "/grudge friend [name]  - tag Friendly (no name = current target)",
    "/grudge clear [name]  - remove tag (no name = current target)",
    "/grudge alert on|off|test|unlock|lock|reset  - on-screen KOS warning",
    "/grudge sound on|off  - KOS warning sound",
    "/grudge chat on|off  - KOS chat line",
    "/grudge attacker on|off  - chat note when a past attacker is seen again",
    "/grudge sentinelkos on|off  - treat Sentinel watchlist as KOS",
    "/grudge tooltip on|off",
    "/grudge autountag on|off  - remove Friendly tag if that player attacks you (default ON)",
    "/grudge minimap on|off  - show/hide the minimap button",
    "/grudge raidwarn on|off  - also show KOS text in the raid-warning area",
    "/grudge reset confirm  - delete Grudge tags/guild cache (Sentinel data untouched)",
}
local function onoff(arg, key, label)
    local a = (arg or ""):lower()
    if a == "on" then G.db.settings[key] = true
    elseif a == "off" then G.db.settings[key] = false
    else G.db.settings[key] = not G.db.settings[key] end
    G.Print(label .. ": " .. (G.db.settings[key] and "ON" or "OFF"))
end
local function command(msg)
    if not G.db then return end
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "show" then
        G.ToggleUI()
    elseif cmd == "help" then
        for _, l in ipairs(HELP) do G.Print(l) end
        if not G.Sentinel() then G.Print("Forever Sentinel PVP data not found; attack/seen counts will be 0.") end
    elseif cmd == "kos" or cmd == "friend" or cmd == "friendly" or cmd == "clear" then
        local key, name = resolveName(arg)
        if not key then G.Print("Target a player or give a name, e.g. /grudge " .. cmd .. " Name-Realm"); return end
        if cmd == "clear" then
            local had = G.db.tags[key]
            G.SetTag(key, nil, nil)
            G.Print(had and ("Tag removed: " .. (had.name or name)) or ("No tag on " .. name))
        else
            local tag = cmd == "kos" and "KOS" or "FRIEND"
            G.SetTag(key, name, tag)
            G.Print(name .. " tagged " .. TAGNAMES[tag] .. ".")
        end
    elseif cmd == "alert" then
        local a = arg:lower()
        if a == "test" then
            G.KosWarning("Testplayer-" .. ownRealm(), "ROGUE", 60, {attacks = 3, seen = 7}, "test")
        elseif a == "unlock" then G.UnlockWarning(true)
        elseif a == "lock" then G.UnlockWarning(false)
        elseif a == "reset" then G.db.settings.alertPos = nil; G.PlaceWarning(); G.Print("Warning position reset.")
        else onoff(a, "alert", "On-screen KOS warning") end
    elseif cmd == "sound" then onoff(arg, "sound", "KOS sound")
    elseif cmd == "chat" then onoff(arg, "chat", "KOS chat line")
    elseif cmd == "attacker" then onoff(arg, "attackerAlert", "Past-attacker chat note")
    elseif cmd == "sentinelkos" then onoff(arg, "sentinelKos", "Sentinel watchlist counts as KOS")
    elseif cmd == "tooltip" then onoff(arg, "tooltip", "Tooltip line")
    elseif cmd == "minimap" then
        local a = arg:lower()
        G.SetMinimap(a == "on" or (a ~= "off" and G.db.settings.minimapHide == true))
    elseif cmd == "autountag" then onoff(arg, "autoUntag", "Remove Friendly tag when they attack you")
    elseif cmd == "raidwarn" then onoff(arg, "raidNotice", "Also use raid-warning area")
    elseif cmd == "reset" then
        if arg == "confirm" then
            G.db.tags, G.db.extra = {}, {}
            G.alerted, G.attackerAlerted = {}, {}
            G.Print("Grudge tags and guild cache cleared. Sentinel's records were not touched.")
            if G.RefreshUI then G.RefreshUI(true) end
        else
            G.Print("This deletes all KOS/Friendly tags. Type /grudge reset confirm")
        end
    else
        G.Print("Unknown command. /grudge help")
    end
end

-- Events ----------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local function reg(e) pcall(frame.RegisterEvent, frame, e) end
local myGUID
local HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40
local band = bit and bit.band
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        G.Init()
        if G.BuildUI then G.BuildUI() end
        if G.BuildMinimap then G.BuildMinimap() end
        SLASH_SENTINELGRUDGE1 = "/grudge"
        SLASH_SENTINELGRUDGE2 = "/sgrudge"
        SlashCmdList.SENTINELGRUDGE = command
        for _, e in ipairs({"NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
                            "PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "UNIT_TARGET"}) do reg(e) end
        G.ScanSentinelFights()
        -- Sentinel reports the combat log is unavailable on Forever; use it only if it exists.
        if type(CombatLogGetCurrentEventInfo) == "function" and band then reg("COMBAT_LOG_EVENT_UNFILTERED") end
        frame:UnregisterEvent("ADDON_LOADED")
        G.Print("v" .. G.version .. " loaded" .. (G.Sentinel() and " (using Sentinel data)" or " (Sentinel data not found)") .. ". /grudge help")
    elseif not G.db then return
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = pub(arg1)
        if type(unit) == "string" then G.CheckUnit(unit, "nameplate"); G.CheckFriendTargeting(unit) end
    elseif event == "UNIT_TARGET" then
        local unit = pub(arg1)
        if type(unit) == "string" and unit ~= "player" then G.CheckFriendTargeting(unit) end
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_DEAD" then
        -- Sentinel saves a fight ~6s after combat ends; scan after that.
        if C_Timer and C_Timer.After then C_Timer.After(9, G.ScanSentinelFights) end
    elseif event == "PLAYER_TARGET_CHANGED" then G.CheckUnit("target", "target"); G.CheckFriendTargeting("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then G.CheckUnit("mouseover", "mouseover")
    elseif event == "PLAYER_FOCUS_CHANGED" then G.CheckUnit("focus", "focus")
    elseif event == "PLAYER_ENTERING_WORLD" then
        G.lastCheck = {}
        myGUID = safe(UnitGUID, "player")
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local ok, _, sub, _, sGUID, sName, sFlags, _, dGUID = pcall(CombatLogGetCurrentEventInfo)
        if not ok or type(sGUID) ~= "string" or type(sName) ~= "string" or type(sFlags) ~= "number" then return end
        if sGUID == myGUID or not sGUID:match("^Player%-") or band(sFlags, HOSTILE) == 0 then return end
        local key, bare = G.KeyFromFull(sName)
        if not key then key = G.KeyFromParts(sName, nil) end
        local tag = G.GetTag(key, bare)
        if not tag then return end
        if tag.tag == "FRIEND" then
            if dGUID == myGUID and type(sub) == "string" and (sub:find("_DAMAGE$") or sub:find("_MISSED$")) then
                G.FriendAttacked(key, bare, sName, "combat log")
            end
            return
        end
        if tag.tag ~= "KOS" then return end
        local now = G.Now()
        if G.alerted[key] and now - G.alerted[key] < G.db.settings.kosThrottle then return end
        G.alerted[key] = now
        local st = G.Stats(sGUID, key)
        G.KosWarning(tag.name or sName, st.class, st.level, st, "combat log")
    end
end)
reg("ADDON_LOADED")
