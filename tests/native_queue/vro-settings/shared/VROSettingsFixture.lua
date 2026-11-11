local JSON=require 'QueueHealthEvents'
local F={}
function F.emit(event,row) print('[VRO_SETTINGS] '..event..' '..JSON.encode(row)) end
function F.observe(role)
 local options=getSandboxOptions()
 local enabled=assert(options:getOptionByName('VSO_EnableFullVehicleSalvaging'),'missing declared VSO enable option'):getValue()
 local time=assert(options:getOptionByName('VSO_SalvageTime_Doors'),'missing declared VSO door time'):getValue()
 local recipe=assert(ScriptManager.instance:getCraftRecipe('Salvage Vehicle Doors'),'missing real door recipe')
 local row={role=role,optionEnabled=enabled,optionTime=time,
  luaEnabled=SandboxVars.VSO_EnableFullVehicleSalvaging,luaTime=SandboxVars.VSO_SalvageTime_Doors,
  legacyAbsent=SandboxVars.VRO_EnableFullVehicleSalvaging==nil and SandboxVars.VRO_SalvageTime_Doors==nil,
  effectiveEnabled=VRO.IsFullVehicleSalvagingEnabled(),effectiveTime=VRO.GetSalvageTime('VRO_SalvageTime_Doors',600),
  recipeTime=recipe:getTime()}
 F.verify(row,role);F.emit('OBSERVE',row);return row
end
function F.verify(row,role)
 assert(row.role==role and row.optionEnabled==false and row.optionTime==120
  and row.luaEnabled==false and row.luaTime==120 and row.legacyAbsent==true
  and row.effectiveEnabled==false and row.effectiveTime==120 and row.recipeTime==120,
  'declared VSO settings did not govern native salvage readers and recipe initialization')
end
return F
