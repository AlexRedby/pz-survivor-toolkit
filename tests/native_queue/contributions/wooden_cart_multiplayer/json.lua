-- Fixture values contain only strings, finite numbers, booleans and tables.
local function encode(value)
 local kind=type(value)
 if kind=='nil' then return 'null' end
 if kind=='boolean' then return tostring(value) end
 if kind=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite fixture number');return tostring(value) end
 if kind=='string' then
  return '"'..value:gsub('[%z\1-\31\\"]',function(char) return string.format('\\u%04x',string.byte(char)) end)..'"'
 end
 assert(kind=='table','Unsupported fixture value')
 local count,maximum,array=0,0,true
 for key in pairs(value) do count=count+1;if type(key)~='number' or key<1 or key%1~=0 then array=false else maximum=math.max(maximum,key) end end
 local parts={}
 if array and count==maximum then for i=1,maximum do parts[#parts+1]=encode(value[i]) end;return '['..table.concat(parts,',')..']' end
 for key,entry in pairs(value) do assert(type(key)=='string','Fixture object key must be text');parts[#parts+1]=encode(key)..':'..encode(entry) end
 return '{'..table.concat(parts,',')..'}'
end
return {encode=encode,emit=function(event) print('[QUEUE_CHECK] '..encode(event)) end}
