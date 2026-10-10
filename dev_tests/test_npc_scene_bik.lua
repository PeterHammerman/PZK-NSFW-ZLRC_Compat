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
local launched, launchedMode
local SC={}
for _,id in ipairs{"StandingDoggy_StandingDoggy_StandingDoggy_MF","StandingDoggy_StandingDoggy_StandingDoggy_FM","Sex_SubdueCowgirl_FF","Sex_SubdueDoggy_MF","Sex_SubdueDoggy_MM"} do SC[id]={} end
SC["Cowgirl_Cowgirl_Cowgirl_FM"]={exactGenderOnly=true,corpseOnly=true}
SC["Sex_SubdueCowgirl_FM"]={exactGenderOnly=true}
SC["Sex_SubdueDoggy_FM"]={exactGenderOnly=true}
local blocked=false
ZomboRutScene={_active={},_scenes=SC,registerSceneStartCallback=function(f) table.insert(startCbs,f) end,registerSceneEndCallback=function(f) table.insert(endCbs,f) end,
 zombieScenesBlocked=function() return blocked end,
 -- faithful copy of the real _resolveGender semantics (read from ZomboRutScene.lua)
 _resolveGender=function(player,partner,sceneId)
   local pg=player:isFemale() and "F" or "M"
   local zg=partner:isFemale() and "F" or "M"
   local exact=sceneId.."_"..pg..zg; if SC[exact] then return exact end
   local ag=(pg=="F") and "M" or "F"; local assumed=sceneId.."_"..pg..ag
   if SC[assumed] and not SC[assumed].exactGenderOnly then return assumed end
   if SC[sceneId.."_"..pg] then return sceneId.."_"..pg end
   if SC[sceneId] then return sceneId end
   return nil end,
 playSceneFromCorpse=function(p,body,id,opts) launched=id launchedMode="corpse"
   ZomboRutScene._active[p]={sceneId=id,cfg={duration=10,outroDuration=2},body=body,effectiveDuration=10}
   for _,f in ipairs(startCbs) do f(p,ZomboRutScene._active[p]) end return true end,
 playSceneFromAttacker=function(p,att,id) launched=id launchedMode="attacker"
   ZomboRutScene._active[p]={sceneId=id,cfg={duration=10,outroDuration=2},effectiveDuration=10}
   for _,f in ipairs(startCbs) do f(p,ZomboRutScene._active[p]) end return true end}
function getTextOrNull(k) return nil end
ProjectALife={ActorRegistry={read=function() return {} end},Talk={stance=function() return "friendly" end}}
ZomboLust={UI={}}
local shown={}
package.loaded["AnimationEvents/AnimationEvents/ZLShowImage"]=function(action,ev,param) table.insert(shown,{action.character,param}) end
local realreq=require; function require(n) if n:find("ZLShowImage") then return package.loaded[n] end return realreq(n) end
ISContextMenu={getNew=function(c) local m={opts={}} m.addOption=function(s,name,t,fn) table.insert(m.opts,{name,fn,t}) return m.opts[#m.opts] end return m end}
ISBaseTimedAction={derive=function(s,n) local c={} c.__index=c setmetatable(c,{__index=ISBaseTimedAction}) return c end,new=function(s,ch) return setmetatable({character=ch},s) end,perform=function() end,stop=function() end}
for _,m in ipairs{"ZLRC/ZLRC_Core","ZLRC/ZLRC_NpcIgnore","ZLRC/ZLRC_CloakGuard","ZLRC/ZLRC_NpcSex","ZLRC/ZLRC_Bik"} do local ok,e=pcall(require,m) if not ok then print("LOAD ERR",m,e) end end
for i=1,70 do fire("OnTick") end
local fails=0; local function T(n,c) print((c and "PASS  " or "FAIL  ")..n) if not c then fails=fails+1 end end
local npc=Obj("IsoZombie",{x=1,y=0}); npc._md.ProjectALifeUID="uidM"; zl={npc}; player.female=true
print("--- item 5 menu / scene resolution (real ZomboRut ids)")
local function menuFor(pFem,nFem,withZrRoot)
  player.female=pFem; npc.female=nFem
  local created={}
  local ctx={options={}}
  ctx.addOption=function(s2,name,t,fn) local o={name=name,fn=fn} table.insert(ctx.options,o) return o end
  ctx.getSubMenu=function(s2,id) return ctx._sub end
  ctx.addSubMenu=function(s2,o,sub) o.subOption=1 ctx._sub=sub end
  local subs={}
  ISContextMenu.getNew=function(c) local m={opts={}} m.addOption=function(s2,name,t,fn) table.insert(m.opts,{name,fn,t}) return m.opts[#m.opts] end
     m.addSubMenu=function(s2,o,sub) o.subOption=2 m._child=sub end table.insert(subs,m) return m end
  if withZrRoot then local zr=ISContextMenu.getNew(ctx); ctx.options[1]={name="ContextMenu_Main",subOption=1}; ctx._sub=zr end
  fire("OnFillWorldObjectContextMenu",0,ctx,{ {getSquare=function() return cell:getGridSquare(0,0,0) end} },false)
  -- find the sex submenu (the last created menu with scene options)
  local labels={} local fns={}
  local root=ctx._sub
  if root and root.opts then for _,o in ipairs(root.opts) do if o[1]=="ContextMenu_ZR_AskForSexMenu" then local child=root._child for _,c in ipairs(child and child.opts or {}) do table.insert(labels,c[1]) fns[c[1]]=c[2] end end end end
  return labels,ctx,fns
end
local function has(t,x) for _,v in ipairs(t) do if v==x then return true end end return false end
local l,ctx1=menuFor(true,false,true)
T("F player + M NPC: Standing Doggy + Cowgirl", #l==2 and has(l,"Standing Doggy") and has(l,"Cowgirl"))
T("entry joined ZomboRut's existing root (no second root)", #ctx1.options==1)
l=menuFor(false,true,true)
T("M player + F NPC: only Standing Doggy", #l==1 and l[1]=="Standing Doggy")
l=menuFor(true,true,true)
T("F + F: only Cowgirl (FF scene exists, no FF doggy)", #l==1 and l[1]=="Cowgirl")
l=menuFor(false,false,true)
T("M + M: nothing", #l==0)
local l2,ctx2=menuFor(true,false,false)
T("no ZomboRut root yet: we create the same root", ctx2.options[1] and ctx2.options[1].name=="ContextMenu_Main")
records_stance="neutral"; ProjectALife.Talk.stance=function() return "neutral" end
l=menuFor(true,false,true); T("neutral NPC: nothing", #l==0)
ProjectALife.Talk.stance=function() return "friendly" end
blocked=true; l=menuFor(true,true,true); T("FF cowgirl hidden when ZR blocks zombie scenes", #l==0); blocked=false
print("--- item 5 friendliness (Jeem-aware)")
local printed={}; local realprint=print; print=function(...) local t={} for i=1,select("#",...) do t[#t+1]=tostring((select(i,...))) end printed[#printed+1]=table.concat(t," ") end
ProjectALife.Talk.stance=function() return "neutral" end
ProjectALifeJimmy={Friendlies={mayOrder=function() return true end}}
l=menuFor(true,false,true); T("A-Life stance neutral but Jeem standing friendly/allied -> offered", #l==2)
ProjectALife.Talk.stance=function() return "hostile" end
l=menuFor(true,false,true); T("A-Life hostile vetoes even if Jeem says friendly", #l==0)
ProjectALife.Talk.stance=function() return "neutral" end
ProjectALifeJimmy.Friendlies.mayOrder=function() return false end
printed={}
l=menuFor(true,false,true); T("neutral + Jeem not friendly -> not offered", #l==0)
T("diagnostic printed WITHOUT debug switch, naming the reason", #printed>=1 and printed[1]:find("%[ZLRC%] Ask%-for%-sex not offered") and printed[1]:find("Jeem standing=not friendly"))
rawset(_G,"getDebug",function() return true end)
local _,ctxd=menuFor(true,false,true)
local found=false for _,o in ipairs(ctxd._sub and ctxd._sub.opts or {}) do if tostring(o[1]):find("unavailable") then found=true end end
T("debug mode: greyed-out '[unavailable: reason]' line inside ZomboRut menu", found)
rawset(_G,"getDebug",nil)
ProjectALifeJimmy=nil
ProjectALife.Talk.stance=function() return "friendly" end
l=menuFor(true,false,true); T("without Jeem: A-Life friendly still works", #l==2)
print=realprint
print("--- item 5 flow (corpse route, F+M)")
local l3,_,fns=menuFor(true,false,true)
fns["Standing Doggy"](player)
T("scene launched with the REAL id via corpse route", launched=="StandingDoggy_StandingDoggy_StandingDoggy_FM" and launchedMode=="corpse")
local act=ZomboRutScene._active[player]
T("live bookkeeping set for ZomboRut restore", act.liveOriginal==npc and act.corpseHusk~=nil and act.partnerIsBandit==false)
T("NPC held (busy + A-Life marker)", npc._md.zlrcBusy==true and npc._md.ProjectALifeCorpseOf=="uidM")
print("--- item 7 bik")
for i=1,13 do clock=clock+1000; fire("OnTick") end
T("bik stages fired (3 clips)", #shown>=3 and shown[1][2]:find("Back_Free_Vaginal_2") and shown[3][2]:find("Vaginal_4"))
T("cloak flag active for NPC scene", ZLRC._noCloakUntil[player]==math.huge)
for _,f in ipairs(endCbs) do f(player,act,"ok") end
T("bik Stop sent at end", shown[#shown][2]=="Stop")
ZomboRutScene._active[player]=nil
clock=clock+2000; fire("OnTick")
T("NPC restored to A-Life baseline", npc._md.zlrcBusy==nil and npc._md.ProjectALifeCorpseOf==nil)
T("session cleared", ZLRC.NpcSex.sessions[player]==nil)
print("--- item 5 flow (attacker route, F+F cowgirl)")
player.female=true; npc.female=true; launched=nil
local _,_,fns2=menuFor(true,true,true)
fns2["Cowgirl"](player)
T("FF cowgirl via playSceneFromAttacker with real id", launched=="Sex_SubdueCowgirl_FF" and launchedMode=="attacker")
T("attacker route: NPC held, no husk of ours", npc._md.zlrcBusy==true and ZLRC.NpcSex.sessions[player].body==nil)
for _,f in ipairs(endCbs) do f(player,ZomboRutScene._active[player],"ok") end
ZomboRutScene._active[player]=nil; clock=clock+2000; fire("OnTick")
T("attacker route: NPC restored", npc._md.zlrcBusy==nil and npc._md.ProjectALifeCorpseOf==nil)
print(fails==0 and "ALL PASS" or ("FAILURES "..fails))
