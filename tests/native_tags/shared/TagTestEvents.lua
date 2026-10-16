-- Deliberately small JSON writer: fixture event values contain no cycles or game objects.
local function json(value)
 local kind=type(value)
 if kind=='nil' then return 'null' end
 if kind=='boolean' or kind=='number' then return tostring(value) end
 if kind=='string' then
  return '"'..value:gsub('[%z\1-\31\\"]',function(char)
   if char=='"' then return '\\"' elseif char=='\\' then return '\\\\' end
   return string.format('\\u%04x',string.byte(char))
  end)..'"'
 end
 assert(kind=='table','unsupported medical event value')
 local count,maximum,array=0,0,true
 for key in pairs(value) do count=count+1;if type(key)~='number' or key<1 or key%1~=0 then array=false else maximum=math.max(maximum,key) end end
 local parts={}
 if array and count==maximum then for i=1,maximum do parts[#parts+1]=json(value[i]) end;return '['..table.concat(parts,',')..']' end
 for key,entry in pairs(value) do assert(type(key)=='string','event object key must be text');parts[#parts+1]=json(key)..':'..json(entry) end
 return '{'..table.concat(parts,',')..'}'
end
return {encode=json,emit=function(event) print('[QUEUE_CHECK] '..json(event)) end}
