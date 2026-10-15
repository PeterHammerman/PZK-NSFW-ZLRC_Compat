-- ZLRC_CloakGuard  (item 10)
-- ZomboRut grants a "stench of the dead" cloak (zombie scent moodle) after scenes. It must NOT be granted
--   * after a scene with an A-Life NPC (they are people, not corpses), and
--   * after a scene with a body the player has washed (no stench left on it).
--
-- ZomboRut's scene-end cloak listener calls ZR_ZombieCloak.accumulate(player) through the global table, and the
-- encounter-settle path does the same, so wrapping accumulate/activate with a per-player suppression window covers
-- both. The window opens at scene start (before ZomboRut's end listener runs) and closes a few seconds after the
-- scene ends (our end listener is registered after ZomboRut's, so it runs after theirs).

require "ZLRC/ZLRC_Core"

local ZomboRutScene = ZLRC.ZRS      -- lazy proxy: ZomboRutScene is only reachable through require()

ZLRC._npcScene     = ZLRC._npcScene     or setmetatable({}, { __mode = "k" }) -- [player] = true, set by ZLRC_NpcSex just before launch
ZLRC._noCloakUntil = ZLRC._noCloakUntil or setmetatable({}, { __mode = "k" }) -- [player] = ms deadline, or math.huge while running
local chainCloakSuppressed = setmetatable({}, { __mode = "k" })

local GRACE_MS    = 20000
local CHAIN_GRACE_MS = 120000
local CLEAN_KEEPS = 30 * 60 * 1000
local CLEAN_RADIUS = 1.6         -- a body picked up for a scene is still within ~1-2 tiles of where it was rinsed
local MAX_CLEAN_RECORDS = 24

local function now() return getTimestampMs() end

local function pos(obj)
    local ok, x, y, z = pcall(function() return obj:getX(), obj:getY(), obj:getZ() end)
    if ok and x then return x, y, z end
    return nil
end

--- called by ISZLRCRinseBody after a successful rinse
function ZLRC.markClean(obj)
    local d = ZLRC.md(obj)
    if d then d.zlrcClean = true end
    local x, y, z = pos(obj)
    if x then
        local list = ZLRC._cleanList
        list[#list + 1] = { x = x, y = y, z = math.floor(z), t = now() }
        while #list > MAX_CLEAN_RECORDS do table.remove(list, 1) end
    end
end
ZLRC._cleanList = ZLRC._cleanList or {}

--- true if this object (a body or a live partner) is a rinsed one: flagged itself, or standing where one was rinsed recently
local function isClean(obj)
    if obj == nil then return false end
    local d = ZLRC.md(obj)
    if d and d.zlrcClean == true then return true end
    local x, y, z = pos(obj)
    if not x then return false end
    local t = now()
    for _, r in ipairs(ZLRC._cleanList) do
        if (t - r.t) < CLEAN_KEEPS and math.floor(z) == r.z then
            local dx, dy = x - r.x, y - r.y
            if dx * dx + dy * dy <= CLEAN_RADIUS * CLEAN_RADIUS then return true end
        end
    end
    return false
end

--- fallback for scene launchers whose `active` table has no body field (e.g. subdued-zombie scenes): a rinsed body near the player
local function rinsedBodyNear(player, radius)
    local x, y, z = pos(player)
    if not x then return false end
    local t = now()
    for _, r in ipairs(ZLRC._cleanList) do
        if (t - r.t) < CLEAN_KEEPS and math.floor(z) == r.z then
            local dx, dy = x - r.x, y - r.y
            if dx * dx + dy * dy <= radius * radius then return true end
        end
    end
    return false
end

local function suppress(player, active)
    if not ZLRC.enabled() or ZLRC.sv("noCloakAfterNpc", true) ~= true then return false end
    if ZLRC._npcScene[player] then return true end
    if type(active) == "table" then
        if active.zlrcNpcScene then return true end
        if isClean(active.body) or isClean(active.liveOriginal) then return true end
        if active.liveOriginal and ZLRC.isNpc(active.liveOriginal) then return true end
    end
    return rinsedBodyNear(player, 2.5)
end

local function blocked(player)
    local encounter = ZLRC.Enc and ZLRC.Enc.sessions and ZLRC.Enc.sessions[player]
    if encounter and encounter.kind == "surrender" then
        chainCloakSuppressed[player] = true
        return true
    end
    if chainCloakSuppressed[player] then
        chainCloakSuppressed[player] = nil
        ZLRC._noCloakUntil[player] = now() + CHAIN_GRACE_MS
        return true
    end
    local t = ZLRC._noCloakUntil[player]
    return t ~= nil and now() < t
end

ZLRC.whenReady("ZR_ZombieCloak wrappers",
    function() return rawget(_G, "ZR_ZombieCloak") and type(ZR_ZombieCloak.accumulate) == "function" end,
    function()
        ZLRC.wrap(ZR_ZombieCloak, "accumulate", function(orig)
            return function(player, ...)
                if blocked(player) then ZLRC.log("cloak accumulate suppressed"); return end
                return orig(player, ...)
            end
        end)
        if type(ZR_ZombieCloak.activate) == "function" then
            ZLRC.wrap(ZR_ZombieCloak, "activate", function(orig)
                return function(player, ...)
                    if blocked(player) then ZLRC.log("cloak activate suppressed"); return end
                    return orig(player, ...)
                end
            end)
        end
    end)

ZLRC.whenReady("ZomboRutScene cloak callbacks",
    function()
        return ZLRC.zrScene() ~= nil
            and type(ZomboRutScene.registerSceneStartCallback) == "function"
            and type(ZomboRutScene.registerSceneEndCallback) == "function"
    end,
    function()
        ZomboRutScene.registerSceneStartCallback(function(player, active)
            if suppress(player, active) then
                ZLRC._noCloakUntil[player] = math.huge
                if type(active) == "table" then
                    active.zlrcNoCloak = true
                    local encounter = ZLRC.Enc and ZLRC.Enc.sessions and ZLRC.Enc.sessions[player]
                    if encounter and encounter.kind == "surrender" then
                        active.zlrcNoCloakChain = true
                        chainCloakSuppressed[player] = true
                    end
                end
            end
        end)
        ZomboRutScene.registerSceneEndCallback(function(player, active, _result)
            if type(active) == "table" and active.zlrcNoCloak then
                if active.zlrcNoCloakChain then
                    chainCloakSuppressed[player] = true
                    ZLRC._noCloakUntil[player] = math.huge
                else
                    ZLRC._noCloakUntil[player] = now() + GRACE_MS
                end
            end
        end)
    end)
