local ROOT="/mnt/user-data/outputs/ZLRC_Compat/42/media/lua/"
local printed={}
Events=setmetatable({}, {__index=function(t,k) local e={Add=function() end,Remove=function() end} rawset(t,k,e) return e end})
function getTimestampMs() return 1 end
function instanceof(o,c) return type(o)=="table" and o._cls==c end
SandboxVars={ZLRC={}}; ModData={getOrCreate=function() return {} end}
local realprint=print
function print(...) local t={} for i=1,select("#",...) do t[#t+1]=tostring((select(i,...))) end printed[#printed+1]=table.concat(t," ") end
BloodBodyPartType={MAX={index=function() return 3 end},FromIndex=function(i) return i end}
ItemVisuals={new=function() return {items={},size=function(s) return #s.items end,get=function(s,i) return s.items[i+1] end} end}
local function visual() local v={b={4,4,4},d={2,2,2}}
  v.getBlood=function(s,p) return s.b[p+1] end v.getDirt=function(s,p) return s.d[p+1] end
  v.setBlood=function(s,p,x) s.b[p+1]=x end v.setDirt=function(s,p,x) s.d[p+1]=x end return v end
local function clothing() local it={_cls="Clothing",vis=visual(),b={5,5,5},d={5,5,5},bl=80,dl=80,synced=0}
  it.getVisual=function(s) return s.vis end
  it.setBlood=function(s,p,x) s.b[p+1]=x end it.setDirt=function(s,p,x) s.d[p+1]=x end
  it.setBloodLevel=function(s,x) s.bl=x end it.setDirtiness=function(s,x) s.dl=x end it.synchWithVisual=function(s) s.synced=s.synced+1 end return it end
local function sum(t) local n=0 for _,v in ipairs(t) do n=n+v end return n end
local function wornList(items) return {size=function() return #items end,getItemByIndex=function(_,i) return items[i+1] end} end

-- corpse: clothes in container + worn refs; getItemVisuals needs an out-list; NO resetModel*; invalidateCorpse present
local worn1=clothing(); local loose=clothing(); local ivEntry=visual()
local wl=wornList({worn1})
local calls={}
local corpse={_cls="IsoDeadBody",_md={},hv=visual(),
  getModData=function(s) return s._md end,getSquare=function() return {} end,
  getHumanVisual=function(s) return s.hv end,
  getWornItems=function() return wl end,
  getContainer=function() return {getItems=function() return {size=function() return 2 end,get=function(_,i) return ({worn1,loose})[i+1] end} end} end,
  getItemVisuals=function(s,list) if list==nil then error("expected 1 argument, got 0") end table.insert(list.items,ivEntry) end,
  setWornItems=function(s,w) table.insert(calls,"setWornItems") end,
  invalidateCorpse=function() table.insert(calls,"invalidateCorpse") end}
-- corpse2: no refresh methods at all
local corpse2={_cls="IsoDeadBody",_md={},hv=visual(),getModData=function(s) return s._md end,getSquare=function() return {} end,getHumanVisual=function(s) return s.hv end,
  getWornItems=function() return wornList({}) end,getContainer=function() return nil end,getItemVisuals=function(s,l) if l==nil then error("expected 1 argument") end end}
-- living zombie
local zworn=clothing(); local zlive=visual()
local zombie={_cls="IsoZombie",_md={},hv=visual(),resets=0,dead=false,
  getModData=function(s) return s._md end,isDead=function(s) return s.dead end,getSquare=function() return {} end,
  getHumanVisual=function(s) return s.hv end,getWornItems=function() return wornList({zworn}) end,
  getItemVisuals=function(s,extra) if extra~=nil then error("zombie takes no argument") end local l=ItemVisuals.new() table.insert(l.items,zlive) return l end,
  resetModelNextFrame=function(s) s.resets=s.resets+1 end}
local loaded={}
function require(n) if loaded[n] then return loaded[n] end for _,d in ipairs{"shared/","client/"} do local f=io.open(ROOT..d..n..".lua") if f then f:close() loaded[n]=dofile(ROOT..d..n..".lua") or true return loaded[n] end end return true end
ISBaseTimedAction={derive=function(s,n) local c={} c.__index=c setmetatable(c,{__index=ISBaseTimedAction}) return c end,new=function(s,ch) return setmetatable({character=ch},s) end,perform=function() end,stop=function() end}
for _,m in ipairs{"ZLRC/ZLRC_Core","ZLRC/ZLRC_CloakGuard","ZLRC/ISZLRCRinseBody"} do assert(pcall(require,m)) end
local amount=1
local water={getFluidContainer=function() return {getAmount=function() return amount end,adjustAmount=function(_,v) amount=v end} end,syncItemFields=function() end}
local player={getInventory=function() return {containsRecursive=function() return true end} end}
local fails=0; local function T(n,c) realprint((c and "PASS  " or "FAIL  ")..n) if not c then fails=fails+1 end end
local function run(target) local a=ISZLRCRinseBody:new(player,target,water) local ok,err=pcall(function() a:perform() end) return ok,err end

local ok,err=run(corpse)
T("corpse: no error"..(ok and "" or (" ("..tostring(err)..")")), ok)
T("corpse: skin visual zeroed", sum(corpse.hv.b)==0 and sum(corpse.hv.d)==0)
T("corpse: worn clothing ItemVisual zeroed", sum(worn1.vis.b)==0 and sum(worn1.vis.d)==0)
T("corpse: worn clothing ITEM-level blood/dirt + levels zeroed", sum(worn1.b)==0 and sum(worn1.d)==0 and worn1.bl==0 and worn1.dl==0)
T("corpse: clothing only in container also cleaned", sum(loose.b)==0 and loose.bl==0 and loose.vis.b[1]==0)
T("corpse: model visual list entries zeroed", sum(ivEntry.b)==0)
T("corpse: items re-synced with visuals", worn1.synced>=1)
T("corpse: refreshed with setWornItems + invalidateCorpse (Jeem's sequence, resetModel absent)", table.concat(calls,"+")=="setWornItems+invalidateCorpse")
T("corpse: marked clean", corpse._md.zlrcClean==true)
local line=printed[#printed] or ""
T("summary line printed with totals + refresh methods", line:find("corpse") and line:find("setWornItems%+invalidateCorpse") and line:find("blood=") ~= nil)
local ok2,err2=run(corpse2)
T("corpse without any refresh method: no error, reports NONE", ok2 and (printed[#printed] or ""):find("refresh=NONE")~=nil)
local ok3,err3=run(zombie)
T("zombie: no error"..(ok3 and "" or (" ("..tostring(err3)..")")), ok3)
T("zombie: skin, worn item, live visual list all zeroed", sum(zombie.hv.b)==0 and sum(zworn.b)==0 and sum(zlive.b)==0)
T("zombie: resetModelNextFrame called", zombie.resets==1)
T("water consumed 3x0.25", math.abs(amount-0.25)<1e-9)
T("class name not caught by ZomboRut wash hook", not (("iszlrcrinsebody"):find("wash") or ("iszlrcrinsebody"):find("clean") or ("iszlrcrinsebody"):find("shower") or ("iszlrcrinsebody"):find("bath")))
realprint(fails==0 and "ALL PASS" or "FAILURES")
