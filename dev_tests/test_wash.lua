local ROOT="/mnt/user-data/outputs/ZLRC_Compat/42/media/lua/"
local handlers={}
Events=setmetatable({}, {__index=function(t,k) handlers[k]={} local e={Add=function(f) table.insert(handlers[k],f) end,Remove=function() end}; rawset(t,k,e) return e end})
local function fire(n,...) for _,f in ipairs(handlers[n] or {}) do f(...) end end
local clock=1000000; function getTimestampMs() return clock end
function instanceof(o,c) return type(o)=="table" and o._cls==c end
SandboxVars={ZLRC={}}; local ms={}; ModData={getOrCreate=function(k) ms[k]=ms[k] or {} return ms[k] end}
function ZombRand() return 0 end
function getText(k) return k end
local calls={}
local function Obj(cls,f)
  local o={_cls=cls,_md={},x=0,y=0,z=0,dead=false,female=false,log={}}
  for k,v in pairs(f or {}) do o[k]=v end
  local base={getModData=function(s) return s._md end,isDead=function(s) return s.dead end,isAlive=function(s) return not s.dead end,
   getX=function(s) return s.x end,getY=function(s) return s.y end,getZ=function(s) return s.z end,isFemale=function(s) return s.female end,
   isDraggingCorpse=function() return false end,isOnFloor=function() return false end,isKnockedDown=function() return false end,isCrawling=function() return false end,
   getHumanVisual=function(s) return {copyFrom=function() end} end,becomeCorpseSilently=function(s) return Obj("IsoDeadBody",{x=s.x,y=s.y}) end}
  return setmetatable(o,{__index=function(t,k) if base[k] then return base[k] end return function(s,...) table.insert(t.log,k) end end})
end
local cell={}; local zl={}
cell.getZombieList=function() return {size=function() return #zl end,get=function(_,i) return zl[i+1] end} end
cell.getGridSquare=function(_,x,y,z) return {getX=function() return x end,getY=function() return y end,getZ=function() return z end,
  getMovingObjects=function() return {size=function() return #zl end,get=function(_,i) return zl[i+1] end} end,getDeadBodys=function() return {size=function() return 0 end} end} end
function getCell() return cell end
local player=Obj("IsoPlayer",{female=true,cell=cell}); function getSpecificPlayer() return player end; function getNumActivePlayers() return 1 end
function addZombiesInOutfit() return {size=function() return 1 end,get=function() return Obj("IsoZombie",{}) end} end
local loaded={}
function require(n) if loaded[n] then return loaded[n] end for _,d in ipairs{"shared/","client/"} do local f=io.open(ROOT..d..n..".lua") if f then f:close() loaded[n]=dofile(ROOT..d..n..".lua") or true return loaded[n] end end return true end
local startCbs,endCbs={}, {}
local launched
ZomboRutScene={_active={},registerSceneStartCallback=function(f) table.insert(startCbs,f) end,registerSceneEndCallback=function(f) table.insert(endCbs,f) end,
 _scenes={StandingDoggy_FM={}},get=function(id) return ZomboRutScene._scenes[id] end,
 _resolveGender=function(p,n,base) local id=base.."_"..(p:isFemale() and "F" or "M")..(n:isFemale() and "F" or "M") return ZomboRutScene._scenes[id] and id or nil end,
 playSceneFromCorpse=function(p,body,id,opts) launched=id
   ZomboRutScene._active[p]={sceneId=id,cfg={duration=10,outroDuration=2},body=body,effectiveDuration=10}
   for _,f in ipairs(startCbs) do f(p,ZomboRutScene._active[p]) end return true end}
ProjectALife={ActorRegistry={read=function() return {} end},Talk={stance=function() return "friendly" end}}
ZomboLust={UI={}}
local shown={}
package.loaded["AnimationEvents/AnimationEvents/ZLShowImage"]=function(action,ev,param) table.insert(shown,{action.character,param}) end
local realreq=require; function require(n) if n:find("ZLShowImage") then return package.loaded[n] end return realreq(n) end
ISContextMenu={getNew=function(c) local m={opts={}} m.addOption=function(s,name,t,fn) table.insert(m.opts,{name,fn,t}) return m.opts[#m.opts] end return m end}
ISBaseTimedAction={derive=function(s,n) local c={} c.__index=c setmetatable(c,{__index=ISBaseTimedAction}) return c end,new=function(s,ch) return setmetatable({character=ch},s) end,perform=function() end,stop=function() end}

Fluid={Water="W",TaintedWater="TW"}
luautils={walkAdj=function() return true end}
local queued
ISTimedActionQueue={add=function(a) queued=a end}
local amount=1.0
local water={getFluidContainer=function() return {contains=function(_,f) return f=="W" end,getAmount=function() return amount end,adjustAmount=function(_,v) amount=v end} end,syncItemFields=function() end}
local inv={getFirstEvalRecurse=function(_,pred) if pred(water) then return water end end,containsRecursive=function() return true end}
player.getInventory=function() return inv end
for _,m in ipairs{"ZLRC/ZLRC_Core","ZLRC/ZLRC_CloakGuard","ZLRC/ZLRC_Clean"} do local ok,e=pcall(require,m) if not ok then print("LOAD ERR",m,e) end end
local fails=0; local function T(n,c) print((c and "PASS  " or "FAIL  ")..n) if not c then fails=fails+1 end end
local z=Obj("IsoZombie",{x=1,y=0}); z._md.zrSubdued=true; zl={z}
local free=Obj("IsoZombie",{x=1,y=0}); 
local opts={}; local ctx={addOption=function(s,name,t,fn,...) table.insert(opts,{name,fn,{...}}) return opts[#opts] end}
local wo={ {getSquare=function() return cell:getGridSquare(0,0,0) end} }
fire("OnFillWorldObjectContextMenu",0,ctx,wo,false)
T("Wash offered for subdued zombie", #opts==1 and opts[1][1]=="ContextMenu_ZLRC_Wash")
zl={free}; opts={}; fire("OnFillWorldObjectContextMenu",0,ctx,wo,false)
T("no Wash for free zombie", #opts==0)
zl={z}; opts={}; fire("OnFillWorldObjectContextMenu",0,ctx,wo,false)
opts[1][2](player,table.unpack(opts[1][3]))
T("action queued", queued~=nil and queued.target==z)
T("action valid with water", queued:isValid())
queued:perform()
T("water consumed (0.25)", math.abs(amount-0.75)<1e-9)
T("target marked clean", z._md.zlrcClean==true)
amount=0.1; T("invalid when water too low", not queued:isValid())
print(fails==0 and "ALL PASS" or "FAILURES "..fails)
