-- Actual native ModOptions, file readers and approved Peek a View JAR. Only the
-- before/partial file images are controlled fixture inputs.
local M={}
function M.verify()
 local options=PZAPI.ModOptions
 local peek=assert(options:getOptions('PeekAView'),'Peek a View options missing')
 assert(peek:getOption('treeFadeActiveInVehicle'):getValue()==false,'vehicle tree preset missing')
 assert(peek:getOption('fixB42Adjacency'):getValue()==false,'adjacency preset missing')
 assert(PeekAView and PeekAView.javaReady and not PeekAView.lastJavaError,'Peek a View Java settings failed')
 local cart=assert(options:getOptions('SaucedCarts'),'Cart options missing')
 assert(cart:getOption('PushCart'):getValue()==Keyboard.KEY_E,'restored Cart preference did not migrate')
 local input=assert(getFileReader('ModOptions.ini',false));local rows={}
 while true do local line=input:readLine();if line==nil then break end;rows[line]=true end
 input:close()
 for _,line in ipairs({'tickbox|PeekAView|treeFadeActiveInVehicle|false',
  'tickbox|PeekAView|fixB42Adjacency|false','keybind|SaucedCarts|PushCart|'..tostring(Keyboard.KEY_E),
  'textentry|ToolkitRecoveryProbe|Note|retained','tickbox|AbsentRecoveryProbe|Enabled|false'})do
  assert(rows[line],'recovered/preserved native preference missing: '..line)
 end
 for _,path in ipairs({'PZSurvivorToolkitPeekAView.ini','PZSurvivorToolkitCartControls.ini'})do
  local file=assert(getFileReader(path,false),'consumer marker missing: '..path);file:close()
 end
 print('[STARTUP_TEST] RECOVERY_READY preferences=true java=true cart=true')
end
return M
