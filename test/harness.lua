local function stub()
  local o = {}
  local scripts = {}
  setmetatable(o, {__index = function(t, k)
    if k == "SetScript" then return function(self, n, fn) scripts[n] = fn end end
    if k == "GetScript" then return function(self, n) return scripts[n] end end
    if k == "IsShown" then return function(self) return self._shown end end
    if k == "Show" then return function(self) self._shown = true; if scripts.OnShow then scripts.OnShow(self) end end end
    if k == "Hide" then return function(self) local was=self._shown; self._shown = false; if was and scripts.OnHide then scripts.OnHide(self) end end end
    if k == "GetFont" then return function() return "font" end end
    if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 200 end end
    if k == "GetText" then return function() return "" end end
    if k == "_scripts" then return scripts end
    return function(self, ...) local s = stub(); return s end
  end})
  return o
end
frames = {}
function CreateFrame(kind, name) local f = stub(); frames[#frames+1]=f; if name then _G[name]=f end; return f end
UIParent = stub(); Minimap = stub(); rawset(Minimap,"GetWidth",function() return 140 end); rawset(Minimap,"GetCenter",function() return 50, 50 end); rawset(Minimap,"GetEffectiveScale",function() return 1 end); function GetCursorPosition() return 100, 100 end; GameTooltip = stub(); UISpecialFrames = {}; DEFAULT_CHAT_FRAME = {AddMessage=function(_,m) print("CHAT", m) end}
RAID_CLASS_COLORS = {ROGUE={r=1,g=1,b=0}}
SlashCmdList = {}
C_Timer = {NewTicker=function() return {Cancel=function() end} end, After=function() end}
function PlaySound(id) print("SOUND", id) end
function GetRealmName() return "Ashforge" end
date = os.date; time = os.time; tinsert = table.insert
bit = {band=function(a,b) return 0 end}
units = {}
function UnitIsPlayer(u) return units[u] ~= nil end
inCombat = false
function InCombatLockdown() return inCombat end
function UnitAffectingCombat(u) return true end
function UnitIsUnit(u, v) if v == "player" and units[u] == "ME" then return true end return u == v end
function UnitFullName(u) local x = units[u]; if x then return x.name, x.realm end end
function UnitName(u) return UnitFullName(u) end
function UnitGUID(u) local x = units[u]; return x and x.guid end
function UnitCanAttack(a, u) local x = units[u]; return x and x.hostile end
function UnitClass(u) local x = units[u]; return x and x.class, x and x.class end
function UnitLevel(u) local x = units[u]; return x and x.level end
function GetGuildInfo(u) local x = units[u]; return x and x.guild end
ForeverPvPIntelDB = { players = {
  ["Player-1-A"] = {name="Ms-Agraw", encounters=5, class="PALADIN", level=40, lastSeen=time()-100, zone="Riverglades"},
  ["Player-1-B"] = {name="Gaussy-Hericium", encounters=2, class="ROGUE", level=41, lastSeen=time()-5000, kos=true},
}, worldHistory = {
  {at=time()-200, ended=time()-190, deaths=1, zone="Riverglades", enemies={{guid="Player-1-A", name="Ms-Agraw", targetedYou=true},{guid="Player-1-C", name="Malpractice-Lifetouch", class="PRIEST", level=41, targetedYou=true}}},
  {at=time()-900, ended=time()-890, deaths=0, zone="Riverglades", enemies={{guid="Player-1-A", name="Ms-Agraw", targetedYou=true}}},
}}
local G = {}
for _, f in ipairs({"Core.lua","UI.lua","Minimap.lua"}) do
  local chunk = assert(loadfile("/workspace/sentinel-grudge/SentinelGrudge/"..f))
  chunk("SentinelGrudge", G)
end
-- fire ADDON_LOADED on the event frame (first frame created by Core)
frames[1]._scripts.OnEvent(frames[1], "ADDON_LOADED", "SentinelGrudge")
local cmd = SlashCmdList.SENTINELGRUDGE
cmd("help")
for _, r in ipairs(G.BuildRows()) do print("ROW", r.name, r.key, r.attacks, r.deaths, r.seen, r.tag) end
units.target = {name="Ms", realm=nil, guid="Player-1-A", hostile=true, class="PALADIN", level=40, guild="Bad Guys"}
cmd("kos")
frames[1]._scripts.OnEvent(frames[1], "PLAYER_TARGET_CHANGED")
frames[1]._scripts.OnEvent(frames[1], "PLAYER_TARGET_CHANGED") -- throttled
cmd("friend Malpractice")
cmd("kos Unknownguy")
units.nameplate1 = {name="Unknownguy", realm="Sim", guid="Player-9-Z", hostile=true, class="MAGE", level=30}
frames[1]._scripts.OnEvent(frames[1], "NAME_PLATE_UNIT_ADDED", "nameplate1")
for k,v in pairs(SentinelGrudgeDB.tags) do print("TAG", k, v.tag, v.name) end
units.mouseover = {name="Malpractice", realm="Lifetouch", guid="Player-1-C", hostile=true, class="PRIEST", level=41}
frames[1]._scripts.OnEvent(frames[1], "UPDATE_MOUSEOVER_UNIT")
units.focus = {name="Gaussy", realm="Hericium", guid="Player-1-B", hostile=true, class="ROGUE", level=41}
frames[1]._scripts.OnEvent(frames[1], "PLAYER_FOCUS_CHANGED")
cmd("") -- open window
G.RefreshUI(true)
cmd("alert test"); cmd("alert unlock"); cmd("alert lock"); cmd("sound off"); cmd("clear Ms-Agraw")
cmd("reset"); cmd("bogus")
for _, r in ipairs(G.BuildRows()) do print("ROW2", r.name, r.attacks, r.seen, r.tag, r.guild) end
local mb = SentinelGrudgeMinimapButton
mb._scripts.OnClick(mb, "RightButton"); mb._scripts.OnClick(mb, "LeftButton"); mb._scripts.OnEnter(mb)
mb._scripts.OnDragStart(mb); mb._scripts.OnDragStop(mb)
cmd("minimap off"); cmd("minimap on"); cmd("minimap")
print("angle", SentinelGrudgeDB.settings.minimapAngle, "hide", SentinelGrudgeDB.settings.minimapHide, "alert", SentinelGrudgeDB.settings.alert)
print("--- autountag tests")
-- old fight before tag time must not untag; baseline already set at load
print("baseline", SentinelGrudgeDB.lastFightScan ~= nil)
table.insert(ForeverPvPIntelDB.worldHistory, 1, {at=time()+5, ended=time()+10, deaths=0, enemies={{guid="Player-1-C", name="Malpractice-Lifetouch", targetedYou=true}}})
G.ScanSentinelFights()
print("malpractice tag", SentinelGrudgeDB.tags["malpractice-lifetouch"])
G.ScanSentinelFights() -- no double processing
cmd("friend Pal-Sim")
units.nameplate3 = {name="Pal", realm="Sim", guid="Player-9-Q", hostile=true, class="PALADIN", level=50}
units["nameplate3target"] = "ME"
frames[1]._scripts.OnEvent(frames[1], "UNIT_TARGET", "nameplate3") -- not in combat: no untag
print("pal tag (out of combat)", SentinelGrudgeDB.tags["pal-sim"] and SentinelGrudgeDB.tags["pal-sim"].tag)
inCombat = true
frames[1]._scripts.OnEvent(frames[1], "UNIT_TARGET", "nameplate3")
print("pal tag (in combat)", SentinelGrudgeDB.tags["pal-sim"])
cmd("autountag off"); cmd("friend Pal-Sim")
frames[1]._scripts.OnEvent(frames[1], "UNIT_TARGET", "nameplate3")
print("pal tag (option off)", SentinelGrudgeDB.tags["pal-sim"] and SentinelGrudgeDB.tags["pal-sim"].tag)
cmd("autountag on")
local mb = SentinelGrudgeMinimapButton; mb._scripts.OnEnter(mb)
print("DONE")
