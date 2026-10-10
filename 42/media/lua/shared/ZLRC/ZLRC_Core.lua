-- ZLRC_Core: shared helpers for the A-Life x ZomboRut/ZomboLust compatibility patch.
-- Written from scratch against the public behaviour of the three mods. No code copied from them.
--
-- Design rule: this file never captures another mod's globals at load time. Everything that
-- needs another mod is installed through ZLRC.whenReady(), which polls until the target exists
-- (load order across mods is not something we can rely on).

ZLRC = ZLRC or {}
ZLRC.pending  = ZLRC.pending  or {}
ZLRC._wrapped = ZLRC._wrapped or setmetatable({}, { __mode = "k" })

-- ---------------------------------------------------------------- sandbox / logging
function ZLRC.sv(name, default)
    local t = SandboxVars and SandboxVars.ZLRC
    if t and t[name] ~= nil then return t[name] end
    return default
end

function ZLRC.enabled()
    return ZLRC.sv("enableMod", true) == true
end

function ZLRC.log(fmt, ...)
    if ZLRC.sv("debug", false) ~= true then return end
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    print("[ZLRC] " .. (ok and msg or tostring(fmt)))
end

function ZLRC.warn(fmt, ...)
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    print("[ZLRC][WARN] " .. (ok and msg or tostring(fmt)))
end

-- ---------------------------------------------------------------- object helpers
local function md(obj)
    if obj == nil then return nil end
    local ok, data = pcall(function() return obj:getModData() end)
    if ok and type(data) == "table" then return data end
    return nil
end
ZLRC.md = md

local function isZombie(obj)
    if obj == nil then return false end
    local ok, r = pcall(instanceof, obj, "IsoZombie")
    return ok and r == true
end
ZLRC.isZombie = isZombie

local function alive(obj)
    if obj == nil then return false end
    local ok, dead = pcall(function() return obj:isDead() end)
    return ok and dead ~= true
end
ZLRC.alive = alive

--- A-Life NPC uid (string) or nil. A-Life stamps ProjectALifeUID on every shell it owns.
--- NOTE: ZomboRut sets ProjectALifeOwned=true on plain subdued zombies too, so Owned alone is NOT
--- proof of an NPC; the UID is.
function ZLRC.npcUid(obj)
    if not isZombie(obj) then return nil end
    local d = md(obj)
    local uid = d and d.ProjectALifeUID
    if type(uid) == "string" and uid ~= "" then return uid end
    return nil
end

function ZLRC.isNpc(obj)
    return ZLRC.npcUid(obj) ~= nil
end

function ZLRC.isSubdued(obj)
    local d = md(obj)
    return d ~= nil and d.zrSubdued == true
end

function ZLRC.isHusk(obj)
    local d = md(obj)
    return d ~= nil and d._zrHusk == true
end

function ZLRC.isFemale(obj)
    local ok, f = pcall(function() return obj:isFemale() end)
    return ok and f == true
end

-- ---------------------------------------------------------------- A-Life relations (server API; SP / host)
--- Returns "hostile" | "careful" | "neutral" | "friendly" | nil (nil = could not be determined,
--- e.g. a pure MP client that has no ProjectALife server modules).
function ZLRC.stance(npc, player)
    local uid = ZLRC.npcUid(npc)
    if not uid then return nil end
    local PA = rawget(_G, "ProjectALife")
    if not (PA and PA.ActorRegistry and PA.Talk and PA.Talk.stance) then return nil end
    local ok, rec = pcall(PA.ActorRegistry.read, uid)
    if not ok or type(rec) ~= "table" then return nil end
    local ok2, st = pcall(PA.Talk.stance, rec, player)
    if ok2 and type(st) == "string" then return st end
    return nil
end

--- A-Life actor record of an NPC shell (server API; SP / host), or nil.
function ZLRC.record(npc)
    local uid = ZLRC.npcUid(npc)
    local PA = rawget(_G, "ProjectALife")
    if not (uid and PA and PA.ActorRegistry and PA.ActorRegistry.read) then return nil end
    local ok, rec = pcall(PA.ActorRegistry.read, uid)
    if ok and type(rec) == "table" then return rec end
    return nil
end

--- "Friendly or allied", in the sense A-Life + Jeem use. Returns ok(boolean), reason(string, for logs/diagnostics).
--- Jeem (when installed) keeps its own standing ladder hostile < careful < neutral < friendly < allied, and its Friendlies
--- feature asks Friendlies.mayOrder(player, record) "is this player liked enough by the NPC's faction". We use that same
--- test, then fall back to A-Life's own stance. A-Life's "hostile" (grudge / raid / hostile faction) always vetoes.
function ZLRC.friendlyOrAllied(npc, player)
    local rec = ZLRC.record(npc)
    if not rec then return false, "no A-Life record (server API not reachable)" end
    local PA = rawget(_G, "ProjectALife")
    local stance = "neutral"
    if PA.Talk and PA.Talk.stance then
        local ok, st = pcall(PA.Talk.stance, rec, player)
        if ok and type(st) == "string" then stance = st end
    end
    if stance == "hostile" then return false, "A-Life stance=hostile" end
    local J = rawget(_G, "ProjectALifeJimmy")
    local jeemSaid
    if J and J.Friendlies and type(J.Friendlies.mayOrder) == "function" then
        local ok, may = pcall(J.Friendlies.mayOrder, player, rec)
        if ok then
            jeemSaid = may and "yes" or "no"
            if may then return true, "Jeem standing friendly/allied (A-Life stance=" .. stance .. ")" end
        end
    end
    if stance == "friendly" then return true, "A-Life stance=friendly" end
    return false, "A-Life stance=" .. stance .. (jeemSaid and (", Jeem standing=not friendly") or " (Jeem not installed)")
end

--- True only when we positively know the NPC is hostile to this player.
function ZLRC.isKnownHostile(npc, player)
    return ZLRC.stance(npc, player) == "hostile"
end

-- ---------------------------------------------------------------- ZomboRut's scene module
--- ZomboRutScene is NOT a global (verified in the sources: every ZomboRut file does `require "ZomboRut/ZomboRutScene"`),
--- so it has to be fetched the same way. (ZR_ZombieCloak, ZR_Subdued and ZR_API ARE globals.)
function ZLRC.zrScene()
    if ZLRC._zrs then return ZLRC._zrs end
    local ok, m = pcall(require, "ZomboRut/ZomboRutScene")
    if ok and type(m) == "table" then ZLRC._zrs = m; return m end
    return nil
end

--- Lazy proxy so call sites can keep writing  ZRS.playSceneFromCorpse(...)  /  ZRS._active  without caring about timing.
ZLRC.ZRS = setmetatable({}, { __index = function(_, k)
    local m = ZLRC.zrScene()
    return m and m[k] or nil
end })

-- ---------------------------------------------------------------- safe wrapping
--- Replace tbl[field] with makeWrapper(orig). Idempotent (never double-wraps our own wrapper).
function ZLRC.wrap(tbl, field, makeWrapper)
    if type(tbl) ~= "table" then return false end
    local orig = tbl[field]
    if type(orig) ~= "function" then return false end
    if ZLRC._wrapped[orig] then return true end
    local w = makeWrapper(orig)
    ZLRC._wrapped[w] = true
    tbl[field] = w
    return true
end

-- ---------------------------------------------------------------- deferred installation
--- probe():  returns true when the target exists.   install(): performs the patch (pcall-protected).
function ZLRC.whenReady(name, probe, install)
    ZLRC.pending[#ZLRC.pending + 1] = { name = name, probe = probe, install = install, done = false, tries = 0 }
end

local tickN = 0
local function poll()
    tickN = tickN + 1
    if tickN % 60 ~= 0 then return end
    for _, e in ipairs(ZLRC.pending) do
        if not e.done then
            e.tries = e.tries + 1
            local okp, ready = pcall(e.probe)
            if okp and ready then
                local oki, err = pcall(e.install)
                if oki then
                    e.done = true
                    ZLRC.log("installed: %s", e.name)
                else
                    e.fails = (e.fails or 0) + 1
                    if e.fails >= 5 then
                        e.done = true
                        ZLRC.warn("giving up on %s: %s", e.name, tostring(err))
                    end
                end
            elseif e.tries > 600 then
                -- ~10 minutes of polling: the target mod is simply not loaded in this session.
                e.done = true
                ZLRC.log("target not present, skipped: %s", e.name)
            end
        end
    end
end
Events.OnTick.Add(poll)

--- Players list helper (SP => 1 player).
function ZLRC.eachPlayer(fn)
    local n = 1
    pcall(function() n = getNumActivePlayers() end)
    for i = 0, (n or 1) - 1 do
        local p
        pcall(function() p = getSpecificPlayer(i) end)
        if p then fn(p) end
    end
end

--- Persistent store (survives save/load, shared by all modules).
function ZLRC.store()
    local ok, t = pcall(function() return ModData.getOrCreate("ZLRC_Store") end)
    if ok and type(t) == "table" then
        t.captives = t.captives or {}
        return t
    end
    ZLRC._fallbackStore = ZLRC._fallbackStore or { captives = {} }
    return ZLRC._fallbackStore
end

return ZLRC
