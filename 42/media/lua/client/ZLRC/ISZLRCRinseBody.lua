-- ISZLRCRinseBody: rinse blood and dirt off a subdued zombie/NPC or a corpse using water from the inventory.
-- (Named "Rinse" on purpose: ZomboRut watches timed actions whose class name contains wash/clean/shower/bath and treats
--  them as the PLAYER washing themselves, which would wipe the player's stains. This is not that.)
--
-- Rule learned from the first in-game test: PZ logs every Java exception even inside pcall(), so nothing here may call a
-- method that might not exist. Every optional method is checked first; corpses (IsoDeadBody) and living zombies
-- (IsoZombie) have different method sets and are handled separately.
require "TimedActions/ISBaseTimedAction"
require "ZLRC/ZLRC_Core"

ISZLRCRinseBody = ISBaseTimedAction:derive("ISZLRCRinseBody")

local function fluidOf(item)
    return item and item:getFluidContainer() or nil
end

function ISZLRCRinseBody:isValid()
    if not self.target then return false end
    if ZLRC.isZombie(self.target) then
        if not ZLRC.alive(self.target) then return false end
    else
        local sq = self.target:getSquare()
        if not sq then return false end
    end
    local fc = fluidOf(self.water)
    return fc ~= nil and fc:getAmount() >= self.cost - 1e-6
        and self.character:getInventory():containsRecursive(self.water)
end

function ISZLRCRinseBody:update()
    if not self.carried and self.character.faceThisObject then self.character:faceThisObject(self.target) end
end

function ISZLRCRinseBody:start()
    -- while carrying a body the character is in its grapple pose; don't override it with a loot animation
    if not self.carried and self.setActionAnim then self:setActionAnim("Loot") end
end

function ISZLRCRinseBody:stop() ISBaseTimedAction.stop(self) end

function ISZLRCRinseBody:getDuration() return self.maxTime end

-- what a body stores, and what we clear ----------------------------------------------------------------------------------
-- Verified from the other mods' code:
--  * a living zombie/NPC: getItemVisuals() is the LIVE visual list (ZomboLust edits it in place, then resetModelNextFrame()).
--  * a corpse keeps its worn clothes as real Clothing items inside body:getContainer(), referenced by body:getWornItems()
--    (Jeem's Corpses.lua says so); it is refreshed with setWornItems(worn) + resetModel + invalidateCorpse (Jeem calls these).
--  * a real Clothing item has per-part blood/dirt of its own (item:setBlood/setDirt, ZomboLust) besides its ItemVisual, plus
--    the totals setBloodLevel/setDirtiness, and synchWithVisual() reconciles item and visual (ZomboRut).
-- A corpse's HumanVisual (skin) and every one of these layers are cleared, then the body is refreshed.
local ALL_PARTS
local function allParts()
    if ALL_PARTS then return ALL_PARTS end
    ALL_PARTS = {}
    if BloodBodyPartType and BloodBodyPartType.MAX then
        for i = 0, BloodBodyPartType.MAX:index() - 1 do ALL_PARTS[#ALL_PARTS + 1] = BloodBodyPartType.FromIndex(i) end
    end
    return ALL_PARTS
end

local function cleanVisual(v, stats)
    if v == nil then return end
    if v.getBlood and v.getDirt then
        for _, p in ipairs(allParts()) do
            stats.blood = stats.blood + (v:getBlood(p) or 0)
            stats.dirt  = stats.dirt  + (v:getDirt(p)  or 0)
        end
    end
    if v.removeBlood then v:removeBlood() end
    if v.removeDirt  then v:removeDirt()  end
    if v.setBlood and v.setDirt then
        for _, p in ipairs(allParts()) do v:setBlood(p, 0); v:setDirt(p, 0) end
    end
end

local function cleanItem(item, stats)
    if item == nil then return end
    if item.getVisual then cleanVisual(item:getVisual(), stats) end
    if instanceof(item, "Clothing") then
        if item.setBlood and item.setDirt then
            for _, p in ipairs(allParts()) do item:setBlood(p, 0); item:setDirt(p, 0) end
        end
        if item.setBloodLevel then item:setBloodLevel(0) end
        if item.setDirtiness  then item:setDirtiness(0)  end
        if item.synchWithVisual then item:synchWithVisual() end
    end
    stats.items = stats.items + 1
end

--- The visual list the model is built from. IsoZombie:getItemVisuals() takes no argument (proven in ZomboRut/ZomboLust);
--- IsoDeadBody:getItemVisuals(list) fills a list (learned from the first test's error).
local function itemVisualsOf(target)
    if ZLRC.isZombie(target) then return target:getItemVisuals() end
    if target.getItemVisuals and ItemVisuals and ItemVisuals.new then
        local list = ItemVisuals.new()
        target:getItemVisuals(list)
        return list
    end
    return nil
end

local function refresh(target, worn)
    local used = {}
    if ZLRC.isZombie(target) then
        if target.resetModelNextFrame then target:resetModelNextFrame(); used[#used + 1] = "resetModelNextFrame" end
        return used
    end
    -- corpse: same sequence Jeem uses after re-dressing one
    if worn and target.setWornItems then target:setWornItems(worn); used[#used + 1] = "setWornItems" end
    for _, m in ipairs({ "resetModel", "invalidateCorpse" }) do
        if target[m] then target[m](target); used[#used + 1] = m end
    end
    return used
end

local PROBE = { "invalidateCorpse", "resetModel", "resetModelNextFrame", "checkClothing", "updateModelTextures",
                 "invalidateRender", "reloadModel", "setWornItems", "getWornItems", "getContainer", "getItemVisuals",
                 "getHumanVisual", "isSkeleton" }

local function sumVisual(v)
    local b, d = 0, 0
    if v and v.getBlood and v.getDirt then
        for _, p in ipairs(allParts()) do b = b + (v:getBlood(p) or 0); d = d + (v:getDirt(p) or 0) end
    end
    return b, d
end

--- what is STILL dirty when we look again (fresh fetch, not our cached references): proves whether the writes stuck
local function readBack(target)
    local sb, sd, vb, vd, n = 0, 0, 0, 0, 0
    if target.getHumanVisual then sb, sd = sumVisual(target:getHumanVisual()) end
    local ivs = itemVisualsOf(target)
    if ivs and ivs.size then
        for i = 0, ivs:size() - 1 do
            local b, d = sumVisual(ivs:get(i)); vb = vb + b; vd = vd + d; n = n + 1
        end
    end
    return sb, sd, vb, vd, n
end

local function rinse(target)
    local stats = { blood = 0, dirt = 0, items = 0, visuals = 0 }
    local isZ = ZLRC.isZombie(target)

    if target.getHumanVisual then cleanVisual(target:getHumanVisual(), stats) end

    local worn = target.getWornItems and target:getWornItems() or nil
    if worn then
        for i = 0, worn:size() - 1 do cleanItem(worn:getItemByIndex(i), stats) end
    end

    if not isZ and target.getContainer then
        local cont = target:getContainer()
        local items = cont and cont:getItems() or nil
        if items then
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if instanceof(it, "Clothing") then cleanItem(it, stats) end
            end
        end
    end

    local ivs = itemVisualsOf(target)
    if ivs and ivs.size then
        for i = 0, ivs:size() - 1 do cleanVisual(ivs:get(i), stats); stats.visuals = stats.visuals + 1 end
    end

    local used = refresh(target, worn)
    local sb, sd, vb, vd, n = readBack(target)

    -- Printed on purpose (player-triggered, rare): console.txt alone must be enough to diagnose "nothing changed".
    local have = {}
    for _, m in ipairs(PROBE) do if target[m] then have[#have + 1] = m end end
    local grappled = isZ and target.isReanimatedForGrappleOnly and target:isReanimatedForGrappleOnly()
    print(string.format("[ZLRC] rinse %s: cleared blood=%.2f dirt=%.2f (%d clothing items, %d visuals); refresh=%s",
        isZ and (grappled and "carried-corpse(zombie)" or "zombie/NPC") or "ground-corpse",
        stats.blood, stats.dirt, stats.items, stats.visuals, #used > 0 and table.concat(used, "+") or "NONE"))
    print(string.format("[ZLRC] rinse read-back (should be 0): skin blood=%.2f dirt=%.2f | %d model visuals blood=%.2f dirt=%.2f",
        sb, sd, n, vb, vd))
    print("[ZLRC] rinse target has methods: " .. table.concat(have, ","))
end

function ISZLRCRinseBody:perform()
    if not self.done then
        self.done = true
        local fc = fluidOf(self.water)
        if fc and fc:getAmount() >= self.cost - 1e-6 then
            fc:adjustAmount(fc:getAmount() - self.cost)
            if self.water.syncItemFields then self.water:syncItemFields() end
            rinse(self.target)
            if ZLRC.markClean then ZLRC.markClean(self.target) end
            ZLRC.log("rinsed %s", tostring(self.target))
        end
    end
    ISBaseTimedAction.perform(self)
end

function ISZLRCRinseBody:complete() return true end

function ISZLRCRinseBody:new(character, target, water, carried)
    local o = ISBaseTimedAction.new(self, character)
    o.target = target
    o.carried = carried == true
    o.water = water
    o.cost = tonumber(ZLRC.sv("cleanWaterCost", 0.25)) or 0.25
    o.stopOnWalk, o.stopOnRun = not o.carried, not o.carried
    o.maxTime = 180
    return o
end
