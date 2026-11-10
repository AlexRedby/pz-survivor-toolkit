-- Shared initial-placement gate. It never moves the authority or repairs state.
local P=require 'QueueEnergyPlacement';local JSON=require 'QueueHealthEvents'
local Placement={}
function Placement.authority(player,case,trial,target,proof)
 assert(not isClient(),'Fire fixture preparation requires authority')
 assert(type(case)=='string'and type(trial)=='number'and trial%1==0 and trial>0,'Fire placement case/trial missing')
 target=P.target(target)
 local remote=isServer()
 assert(type(proof)=='table'and proof.mode==(remote and'replica'or'local')and proof.centered==true
  and proof.teleports==(remote and 0 or 1)and proof.centers==(remote and 0 or 1),'Fire centered authority proof missing')
 local observed=P.target(proof.target)
 assert(observed.x==target.x and observed.y==target.y and observed.z==target.z and P.atCentered(player,target),
  'Fire authority left final centered placement')
 print('[FIRE_TEST] AUTHORITY_PLACEMENT '..JSON.encode({case=case,trial=trial,actor='client1',target=target,proof=proof}))
 return target
end
return Placement
