local ROOT="/mnt/user-data/outputs/ZLRC_Compat/42/media/lua/"
-- ---------- PZ mocks
local handlers={}
local function ev(name) handlers[name]=handlers[name] or {}
  return {Add=function(f) table.insert(handlers[name],f) end, Remove=function(f) for i,g in ipairs(handlers[name]) do if g==f then table.remove(handlers[name],i) return end end end} end
Events=setmetatable({}, {__index=function(t,k) local e=ev(k); rawset(t,k,e); return e end})
local function fire(name,...) for _,f in ipairs(handlers[name] or {}) do f(...) end end
local clock=1000000
function getTimestampMs() return clock end
function instanceof(o,c) return type(o)=="table" and o._cls==c end
SandboxVars={ZLRC={}}
local mdstore={}
ModData={getOrCreate=function(k) mdstore[k]=mdstore[k] or {} return mdstore[k] end}
function ZombRand(n) return 0 end
function getText(k) return k end
local function Obj(cls,f)
  local o={_cls=cls,_md={},x=0,y=0,z=0,dead=false,female=false,dragging=false}
  for k,v in pairs(f or {}) do o[k]=v end
  local m={getModData=function(s) return s._md end,isDead=function(s) return s.dead end,isAlive=function(s) return not s.dead end,
    getX=function(s) return s.x end,getY=function(s) return s.y end,getZ=function(s) return s.z end,isFemale=function(s) return s.female end,
    isDraggingCorpse=function(s) return s.dragging end,getCell=function(s) return s.cell end,
    teleportTo=function(s,x,y,z) s.x,s.y,s.z=x,y,z end,setX=function(s,v) s.x=v end,setY=function(s,v) s.y=v end,setZ=function(s,v) s.z=v end,
    isReanimatedForGrappleOnly=function(s) return s.grapple or false end}
  return setmetatable(o,{__index=function(t,k) if m[k] then return m[k] end return function() end end})
end
local zlist
local cell={getZombieList=function() return {size=function() return #zlist end,get=function(_,i) return zlist[i+1] end} end}
function getCell() return cell end
local player=Obj("IsoPlayer",{cell=cell})
function getSpecificPlayer(i) return player end
function getNumActivePlayers() return 1 end
-- require shim
local loaded={}
function require(n) if loaded[n] then return loaded[n] end
  for _,d in ipairs{"shared/","client/"} do local f=io.open(ROOT..d..n..".lua") if f then f:close() loaded[n]=dofile(ROOT..d..n..".lua") or true return loaded[n] end end
  return true end
local function tick(n) for i=1,n do fire("OnTick") end end
local fails=0
local function T(name,cond) print((cond and "PASS  " or "FAIL  ")..name) if not cond then fails=fails+1 end end

-- ---------- fake A-Life / Jeem / Zombo tables
local records={uidF={memory={}},uidH={memory={}}}
ProjectALife={ActorRegistry={read=function(u) return records[u] end},
  Talk={stance=function(rec,p) return rec.stance end},
  TargetPolicy={canAttack=function(t) return true,"ok" end},
  Health={tick=function(shell,data,now) end},
  Watchdog={bind=function(uid,gen,shell) return true end},
  AIFence={proneFirstMs=setmetatable({}, {__mode="k"})}}
records.uidF.stance="friendly"; records.uidH.stance="hostile"
local jz={}
ProjectALifeJimmy={Residents={sweep={liveZombies=function() local o={} for _,z in ipairs(jz) do o[#o+1]={x=z.x,y=z.y,obj=z} end return o end},
  bodies={bodyOn=function(sq) return sq.body end}}}
local stripped=0
ZomboLust_ClothingStrip={attemptStripping=function(z,t,n) stripped=stripped+1 return true end,stripTarget=function() return true end,removeOneClothing=function() return true end}
ZomboLust_ClothingStripForZombHuman={stripZombHuman=function() stripped=stripped+1 end}
ZomboLust_SexualIntentSystem={scanProximity=function() stripped=stripped+100 end}
local collided=0
ZomboDesire={}
local exc=0
ZomboLust_ExcitationSystem={getExcitation=function() return exc end,setExcitation=function(p,v) exc=v end,PheromoneRadius=2,HordeRadius=5}
local cloakCalls=0
ZR_ZombieCloak={accumulate=function() cloakCalls=cloakCalls+1 end,activate=function() cloakCalls=cloakCalls+1 end}
local startCbs,endCbs={}, {}
ZomboRutScene={_active={},registerSceneStartCallback=function(f) table.insert(startCbs,f) end,registerSceneEndCallback=function(f) table.insert(endCbs,f) end}
local zrReg={}
local released=0
ZR_Subdued={release=function(z) released=released+1 z._md.ProjectALifeOwned=false z._md.zrSubdued=nil end,getBinding=function() return nil end,enforce=function() end}

-- ---------- load modules
for _,m in ipairs{"ZLRC/ZLRC_Core","ZLRC/ZLRC_NpcIgnore","ZLRC/ZLRC_ExcitationPre","ZLRC/ZLRC_StripGuard","ZLRC/ZLRC_Excitation","ZLRC/ZLRC_CloakGuard","ZLRC/ZLRC_Captives"} do
  local ok,err=pcall(require,m) if not ok then print("LOAD ERR",m,err) fails=fails+1 end end
tick(70)   -- let poller install wrappers

local function Z(f) return Obj("IsoZombie",f) end
local plain=Z{x=1,y=1}
local sub=Z{x=2,y=2}; sub._md.zrSubdued=true
local npcF=Z{x=1,y=0}; npcF._md.ProjectALifeUID="uidF"
local npcH=Z{x=0,y=1}; npcH._md.ProjectALifeUID="uidH"
local subNpc=Z{x=3,y=3}; subNpc._md.ProjectALifeUID="uidF"; subNpc._md.zrSubdued=true
local busy=Z{}; busy._md.zlrcBusy=true
local TP=ProjectALife.TargetPolicy
print("--- items 2/3/4")
T("canAttack plain zombie allowed", TP.canAttack(plain)==true)
T("canAttack subdued zombie refused", TP.canAttack(sub)==false)
T("canAttack subdued NPC refused", TP.canAttack(subNpc)==false)
T("canAttack busy NPC refused", TP.canAttack(busy)==false)
T("canAttack free NPC unchanged", TP.canAttack(npcH)==true)
jz={plain,sub,Z{x=5,y=5}}
T("Jeem sweep drops subdued", #ProjectALifeJimmy.Residents.sweep.liveZombies()==2)
local husk=Obj("IsoDeadBody",{x=9,y=9}); husk._md._zrHusk=true
local norm=Obj("IsoDeadBody",{x=9,y=9})
T("Jeem bodyOn skips husk", ProjectALifeJimmy.Residents.bodies.bodyOn({body=husk})==nil)
T("Jeem bodyOn keeps normal corpse", ProjectALifeJimmy.Residents.bodies.bodyOn({body=norm})==norm)
player.dragging=true; player.x,player.y=9.5,9.5
T("Jeem bodyOn skips corpse being dragged", ProjectALifeJimmy.Residents.bodies.bodyOn({body=norm})==nil)
player.dragging=false
-- bleed-out
local d=subNpc._md; d.ProjectALifeBleedOutAtMs=5
ProjectALife.Health.tick(subNpc,d,1)
T("captive bleed-out timer cleared", d.ProjectALifeBleedOutAtMs==nil)
local d2=npcH._md; d2.ProjectALifeBleedOutAtMs=5; ProjectALife.Health.tick(npcH,d2,1)
T("normal NPC bleed-out untouched", d2.ProjectALifeBleedOutAtMs==5)

print("--- item 1")
player.x,player.y=0,0
zlist={npcF,npcH,plain}
tick(6)
T("friendly NPC gets ZomboDesire opt-out flag", npcF._md.isBandit==true)
T("hostile NPC not flagged", npcH._md.isBandit==nil)
T("plain zombie not flagged", plain._md.isBandit==nil)
zlist={npcF,npcH,plain}
tick(6)
T("flag set with zlist visible", npcF._md.isBandit==true and npcH._md.isBandit==nil)
records.uidF.stance="hostile"; tick(6)
T("flag removed when NPC turns hostile", npcF._md.isBandit==nil)
records.uidF.stance="friendly"; tick(6)
T("flag restored when friendly again", npcF._md.isBandit==true)
local own=Z{x=1,y=1}; own._md.ProjectALifeUID="uidF"; own._md.isBandit=true; zlist={own}; records.uidF.stance="hostile"; tick(6)
T("never clears a flag it did not set", own._md.isBandit==true)
records.uidF.stance="friendly"; zlist={npcF}
SandboxVars.ZLRC.stripGuard=false; tick(6)
T("option off -> flag removed", npcF._md.isBandit==nil)
SandboxVars.ZLRC.stripGuard=true; tick(6)
local far=Z{x=500,y=500}; far._md.ProjectALifeUID="uidF"; zlist={far}; tick(6)
T("far NPC not scanned", far._md.isBandit==nil)
ZomboLust_ClothingStrip.attemptStripping(npcF,player,1); T("attemptStripping blocked for friendly NPC", stripped==0)
ZomboLust_ClothingStrip.attemptStripping(plain,player,1); T("attemptStripping passes for zombie", stripped==1)
ZomboLust_ClothingStripForZombHuman.stripZombHuman(npcF); T("stripZombHuman blocked", stripped==1)
ZomboLust_SexualIntentSystem.scanProximity(player,npcF); T("intent scan blocked", stripped==1)
SandboxVars.ZLRC.stripGuard=false
ZomboLust_ClothingStrip.attemptStripping(npcF,player,1); T("guard off -> strip passes", stripped==2)
SandboxVars.ZLRC.stripGuard=true

print("--- item 8")
-- 2 npcs + 2 zombies in radius 2 of player
zlist={Z{x=1,y=0},Z{x=0,y=1},Z{x=-1,y=0},Z{x=0,y=-1}}
zlist[1]._md.ProjectALifeUID="a"; zlist[2]._md.ProjectALifeUID="b"
local function frame(gain) exc=10; fire("OnPlayerUpdate",player) ; exc=exc+gain ; -- pre ran first, then "ZomboLust"
  -- note: handlers order = pre(shared), post(client); emulate ZL between them by splitting
end
-- emulate precise ordering: pre handler, ZL gain, post handler
local pre,post=handlers.OnPlayerUpdate[1],handlers.OnPlayerUpdate[2]
local function run(mode,gain) SandboxVars.ZLRC.excitationSource=mode; exc=10; pre(player); exc=exc+gain; post(player); return exc end
T("mode1 both: unchanged", math.abs(run(1,4)-14)<1e-9)
T("mode2 zombies only: half", math.abs(run(2,4)-12)<1e-9)
T("mode3 NPCs only: half", math.abs(run(3,4)-12)<1e-9)
T("mode4 none: reverted", math.abs(run(4,4)-10)<1e-9)
zlist={}
T("no bodies near: untouched", math.abs(run(4,4)-14)<1e-9)

print("--- item 10")
local active={sceneId="X",body=Obj("IsoDeadBody",{}),zlrcNpcScene=true}
ZLRC._npcScene[player]=true; for _,f in ipairs(startCbs) do f(player,active) end; ZLRC._npcScene[player]=nil
ZR_ZombieCloak.accumulate(player); T("cloak suppressed during NPC scene", cloakCalls==0)
for _,f in ipairs(endCbs) do f(player,active,"ok") end
ZR_ZombieCloak.accumulate(player); T("cloak still suppressed in grace window", cloakCalls==0)
clock=clock+25000
ZR_ZombieCloak.accumulate(player); T("cloak works again after grace", cloakCalls==1)
local clean=Obj("IsoDeadBody",{x=4,y=4}); ZLRC.markClean(clean)
local a2={sceneId="Y",body=clean}; for _,f in ipairs(startCbs) do f(player,a2) end
ZR_ZombieCloak.accumulate(player); T("cloak suppressed for washed body", cloakCalls==1)
for _,f in ipairs(endCbs) do f(player,a2,"ok") end; clock=clock+25000
local a3={sceneId="Z",body=Obj("IsoDeadBody",{x=50,y=50})}; for _,f in ipairs(startCbs) do f(player,a3) end
ZR_ZombieCloak.accumulate(player); T("cloak normal for ordinary corpse scene", cloakCalls==2)
for _,f in ipairs(endCbs) do f(player,a3,"ok") end; clock=clock+25000

print("--- item 6")
local pmd=player._md; pmd.zr_subduedRegistry={cap1={onFront=true,binding={"rope"}}}
subNpc._md.zrSubduedKey="cap1"; zlist={subNpc,plain,sub}
tick(30)
local store=ZLRC.store().captives
T("NPC captured into ZLRC store", store.uidF~=nil and store.uidF.binding~=nil)
T("ZR registry entry removed for real NPC", pmd.zr_subduedRegistry.cap1==nil)
T("downed hold set far in future", subNpc._md.ProjectALifeDownedUntilMs>clock)
T("plain subdued zombie not captured", next(store)=="uidF" and next(store,"uidF")==nil)
T("getBinding falls back to stored", ZR_Subdued.getBinding(subNpc)~=nil)
-- chunk reload: old shell gone, A-Life binds a fresh shell far from the captive spot
local fresh=Z{x=40,y=40}; fresh._md.ProjectALifeUID="uidF"; fresh._md.ProjectALifeOwned=true
store.uidF.x,store.uidF.y,store.uidF.z=3,3,0
ProjectALife.Watchdog.bind("uidF",1,fresh)
T("fresh shell re-captured on bind", fresh._md.zrSubdued==true and fresh.x==3 and fresh.y==3)
local fresh2=Z{x=41,y=41}; fresh2._md.ProjectALifeUID="uidF"; zlist={fresh2}
tick(30)
T("scan also re-applies captive", fresh2._md.zrSubdued==true and fresh2.x==3)
ZR_Subdued.release(fresh2)
T("release returns NPC to A-Life", fresh2._md.ProjectALifeOwned==true and store.uidF==nil)
print(fails==0 and "\nALL PASS" or ("\nFAILURES: "..fails))
