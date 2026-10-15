-- ZLRC_Bik  (item 7)
-- ZomboLust shows its Bink (.bik) clips from "ZLShowImage" events embedded in its animation XML. ZomboRut's animations
-- carry no such events, so its scenes play without the window. This module drives the SAME window (ZomboLust.UI) by
-- calling ZomboLust's own ZLShowImage handler, timed against the ZomboRut scene's progress.
--
-- !! The clip choice below is a best guess from the file names (Back_* = seen from behind, Front_* = from the front,
-- !! _2/_3/_4 = increasing intensity). Edit CLIPS / pickClips() if a position shows an unfitting clip.
-- Clips are looked up by ZomboLust as "<prefix><name>" where the prefix depends on the female participant's skin
-- (ZL_Blanc_ / ZL_Brun_ / ... ) or ZL_Zombie_ for a male-only pair, exactly as in ZomboLust.

require "ZLRC/ZLRC_Core"

local ZomboRutScene = ZLRC.ZRS      -- lazy proxy: ZomboRutScene is only reachable through require()

local CLIPS = {
    doggy   = { "Back_Free_Vaginal_2.bik",  "Back_Free_Vaginal_3.bik",  "Back_Free_Vaginal_4.bik"  },
    cowgirl = { "Front_Free_Vaginal_2.bik", "Front_Free_Vaginal_3.bik", "Front_Free_Vaginal_4.bik" },
    oral    = { "Oral_Free_2.bik",          "Oral_Free_3.bik",          "Oral_Free_4.bik"          },
    default = { "Front_Free_Vaginal_2.bik", "Front_Free_Vaginal_3.bik", "Front_Free_Vaginal_4.bik" },
}
-- fraction of the scene's duration at which clip #1/#2/#3 starts
local STAGE_AT = { 0.03, 0.40, 0.70 }

local function pickClips(sceneId, cfg)
    if cfg and (cfg.isUtility or cfg.nonPenetrative or cfg.kind == "utility") then return nil end
    local id = string.lower(tostring(sceneId or ""))
    if id:find("tackle") or id:find("drag") or id:find("footjob") then
        return nil
    end
    if (cfg and cfg.isOral)
        or id:find("bj", 1, true)
        or id:find("oral", 1, true)
        or id:find("facesit", 1, true)
        or id:find("revlotus", 1, true) then
        return CLIPS.oral
    end
    if id:find("doggy", 1, true) or id:find("spooning", 1, true) then return CLIPS.doggy end
    if id:find("cowgirl", 1, true) or id:find("missionary", 1, true) or id:find("holding", 1, true) then
        return CLIPS.cowgirl
    end
    return CLIPS.default
end

local handler, warned
local function getHandler()
    if handler then return handler end
    -- Verified in ZomboDesire_EventsHandler.lua: the framework lazy-loads handlers into this table via
    -- require("AnimationEvents/AnimationEvents/<Event>") and calls them as handler(action, eventName, parameter).
    local ok0, h0 = pcall(function() return ZomboDesire and ZomboDesire.EventMarkerModules and ZomboDesire.EventMarkerModules.ZLShowImage end)
    if ok0 and type(h0) == "function" then handler = h0; return h0 end
    for _, name in ipairs({ "AnimationEvents/AnimationEvents/ZLShowImage", "AnimationEvents/ZLShowImage" }) do
        local ok, h = pcall(require, name)
        if ok and type(h) == "function" then handler = h; return h end
    end
    if not warned then warned = true; ZLRC.warn("ZomboLust ZLShowImage handler not found; bik window disabled") end
    return nil
end

local function show(character, param)
    local h = getHandler()
    if not h or not rawget(_G, "ZomboLust") or not ZomboLust.UI then return end
    local ui = ZomboLust.UI
    local wasOpen = ZLRC.call(ui, "getIsVisible") == true
    local ok, err = pcall(h, { character = character }, "ZLShowImage", param)
    if not ok then ZLRC.log("bik show error: %s", tostring(err)) end
    -- ZomboLust's handler always opens the window. The clip is now loaded in it; unless the player wants the window to pop up by itself
    -- (sandbox bikAutoOpen) it is closed again - hidden, not cleared - so it appears with the current clip when it is opened by hand
    -- (the ZomboLust sidebar button). A window the player already had open stays open.
    if param ~= "Stop" and param ~= "stop" and not wasOpen and ZLRC.sv("bikAutoOpen", false) ~= true then
        ZLRC.call(ui, "setVisible", false)
    end
end

-- the character whose skin picks the clip set: the female participant, else the player (as ZomboLust does)
local function videoCharacter(player, partner)
    if partner ~= nil and not ZLRC.isFemale(player) then
        local ok, f = pcall(function() return partner:isFemale() end)
        if ok and f == true then return partner end
    end
    return player
end

local live = setmetatable({}, { __mode = "k" })               -- [player] = { t0, durMs, clips, idx, char }

ZLRC.whenReady("ZomboRutScene bik callbacks",
    function()
        return ZLRC.zrScene() ~= nil
            and type(ZomboRutScene.registerSceneStartCallback) == "function"
            and type(ZomboRutScene.registerSceneEndCallback) == "function"
    end,
    function()
        ZomboRutScene.registerSceneStartCallback(function(player, active)
            if not (ZLRC.enabled() and ZLRC.sv("showBik", true) == true) or type(active) ~= "table" then return end
            local clips = pickClips(active.sceneId, active.cfg)
            if not clips then return end
            local secs = tonumber(active.effectiveDuration) or tonumber(active.cfg and active.cfg.duration) or 17
            local outro = tonumber(active.cfg and active.cfg.outroDuration) or 0
            live[player] = {
                t0 = getTimestampMs(), durMs = (secs + outro) * 1000, clips = clips, idx = 0,
                char = videoCharacter(player, active.body),
            }
        end)
        ZomboRutScene.registerSceneEndCallback(function(player, _active, _result)
            if live[player] then
                live[player] = nil
                show(player, "Stop")                          -- same "Stop" command ZomboLust's animations end with
            end
        end)
    end)

Events.OnTick.Add(function()
    for player, st in pairs(live) do
        local frac = (getTimestampMs() - st.t0) / st.durMs
        local want = 0
        for i, at in ipairs(STAGE_AT) do if frac >= at then want = i end end
        if want > st.idx and st.clips[want] then
            st.idx = want
            show(st.char, st.clips[want])
        end
    end
end)
