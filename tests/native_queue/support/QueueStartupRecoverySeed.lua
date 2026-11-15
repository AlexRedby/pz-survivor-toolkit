-- Disposable input created by the last fixture mod before OnGameBoot. This
-- deliberately exercises late recovery after production file-load handlers;
-- process-start recovery is covered separately. No gameplay profile is involved.
local config=require 'QueueStartupRecoveryConfig'
local function read(path)
 local input=getFileReader(path,false)
 if not input then return nil end
 local lines={}
 while true do local line=input:readLine();if line==nil then break end;lines[#lines+1]=line end
 input:close();return table.concat(lines,'\n')
end
assert(read('queue-scenario.txt')=='startup'and read('smoke-user.txt')=='client1','recovery probe requires its owned startup cache')
if read('QueueStartupRecoverySeeded.ini')=='seeded'then return end
local function write(path,text)
 local output=assert(getFileWriter(path,true,false));output:write(text);output:close()
 assert(read(path)==text:gsub('\r',''):gsub('\n$',''),'recovery probe seed write failed: '..path)
end
write('ModOptions.ini',config.partial)
write('PZSurvivorToolkitModOptionsRecovery.ini',config.recovery)
write('QueueStartupRecoverySeeded.ini','seeded\n')
