-- ZLRC_Clean (item 9): right-click a subdued zombie / subdued NPC / corpse -> "Wash" (needs a container with water).
require "ZLRC/ZLRC_Core"
require "ZLRC/ZLRC_Pick"
require "ZLRC/ZLRC_CloakGuard"
require "ZLRC/ISZLRCRinseBody"

local function waterPredicate(cost)
    return function(item)
        local fc = item:getFluidContainer()
        return fc ~= nil and (fc:contains(Fluid.Water) or fc:contains(Fluid.TaintedWater)) and fc:getAmount() >= cost
    end
end

local function onWash(playerObj, target, water, carried)
    if not carried then
        local sq = target:getSquare()
        if sq and ZLRC.distTo(playerObj, target) > 1.6 then
            if not luautils.walkAdj(playerObj, sq, true) then return end
        end
    end
    ISTimedActionQueue.add(ISZLRCRinseBody:new(playerObj, target, water, carried))
end

--- The corpse a player is carrying/dragging is, for the engine, a LIVING zombie flagged reanimated-for-grapple-only (ZomboRut and
--- A-Life both rely on that flag). Living zombies are the one case where every call is proven (ZomboLust edits the live visual list
--- and calls resetModelNextFrame), and the engine builds the corpse back from that data when it is put down.
local function carriedBody(playerObj)
    local cell = getCell()
    local list = cell and cell:getZombieList()
    if not list then return nil end
    local best, bestD
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z and z.isReanimatedForGrappleOnly and z:isReanimatedForGrappleOnly() then
            local d = ZLRC.distTo(playerObj, z)
            if d <= 3 and (not bestD or d < bestD) then best, bestD = z, d end
        end
    end
    return best
end

local function fill(playerNum, context, worldobjects, test)
    if test or not ZLRC.enabled() or ZLRC.sv("cleanEnabled", true) ~= true then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end

    local target, carried
    if playerObj:isDraggingCorpse() then
        target = carriedBody(playerObj)
        carried = target ~= nil
    else
        local picked = ZLRC.pick(worldobjects)
        for _, z in ipairs(picked.zombies) do
            -- only helpless ones: subdued (ZomboRut) bodies, never a free-roaming zombie or active NPC
            if ZLRC.isSubdued(z) and ZLRC.distTo(playerObj, z) < 4 then target = z; break end
        end
        if not target then
            for _, b in ipairs(picked.bodies) do
                if not ZLRC.isHusk(b) and ZLRC.distTo(playerObj, b) < 4 then target = b; break end
            end
        end
    end
    if not target then return end

    local cost = tonumber(ZLRC.sv("cleanWaterCost", 0.25)) or 0.25
    local water = playerObj:getInventory():getFirstEvalRecurse(waterPredicate(cost))
    if water then
        context:addOption(getText("ContextMenu_ZLRC_Wash"), playerObj, onWash, target, water, carried)
    else
        local opt = context:addOption(getText("ContextMenu_ZLRC_WashNoWater"), playerObj, nil)
        opt.notAvailable = true
    end
end

Events.OnFillWorldObjectContextMenu.Add(fill)
