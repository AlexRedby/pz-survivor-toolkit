-- Disposable fixture objects only. A native transmit is attempted at most once:
-- its square-index packet is not idempotent and its return is not a delivery ACK.
-- Keep the fixture generation frozen until existing peer absence gates finish.
local W={}
local privateToken={}
local lists={'getObjects','getSpecialObjects','getWorldObjects'}
local function dense(entries)
 assert(type(entries)=='table'and getmetatable(entries)==nil,'world cleanup entries must be a plain array')
 local count=0
 for key in pairs(entries)do
  assert(type(key)=='number'and key%1==0 and key>=1 and key<=#entries,'world cleanup entries must be a dense array')
  count=count+1
 end
 assert(count==#entries,'world cleanup entries must be a dense array')
end
local function floorView(container)
 return container==nil or container:getType()=='floor'and container:getParent()==nil and container:getContainingItem()==nil
end
local function state(j)
 assert(type(j)=='table'and getmetatable(j)=='fixture world cleanup journal','invalid world cleanup journal')
 local s=j[privateToken]
 assert(type(s)=='table'and s.handle==j,'invalid world cleanup journal');return s
end
local function values(square,name)
 local source=square[name](square);assert(source,'world cleanup square list missing')
 local result,seen={},{}
 for i=0,source:size()-1 do
  local object=source:get(i)
  assert(object and not seen[object],'world cleanup duplicate square member')
  seen[object]=true;result[#result+1]=object
 end
 return result,seen
end
local function loaded(square)
 if not square then return false end
 local cell=getCell()
 return cell and cell:getGridSquare(square:getX(),square:getY(),square:getZ())==square
end
local function member(square,object)
 for _,name in ipairs(lists)do
  local _,present=values(square,name)
  if present[object]then return true end
 end
 return false
end
function W.absent(square,object,item)
 if not loaded(square)then return false,'world cleanup square unloaded/replaced'end
 if not object then return false,'world cleanup object missing'end
 local actual=object:getSquare()
 if actual~=nil and actual~=square then return false,'world cleanup object moved'end
 if member(square,object)then return false,'world cleanup object still present'end
 if not item and type(object.getItem)=='function'then item=object:getItem()end
 if item then
  if object:getItem()~=item then return false,'world cleanup ground identity rebound'end
  local world=item:getWorldItem()
  if world~=nil and world~=object then return false,'world cleanup ground item moved'end
  -- Inventory pages can keep this item in their virtual floor view after the
  -- world object disappears. That view is not a physical storage endpoint.
  if not floorView(item:getContainer())then return false,'world cleanup ground item attached'end
 end
 -- Native removal may retain both getSquare() and item:getWorldItem(). Exact
 -- absence from the original loaded lists, not nil pointers, is the boundary.
 return true
end
local function containers(object)
 local result={}
 if type(object.getContainerCount)=='function'then
  for i=0,object:getContainerCount()-1 do result[#result+1]=assert(object:getContainerByIndex(i))end
 else
  local container=object:getContainer();if container then result[1]=container end
 end
 return result
end
function W.new(entries,opts)
 dense(entries)
 assert(type(opts)=='table'and getmetatable(opts)==nil and type(opts.server)=='boolean'
  and type(opts.guard)=='function','world cleanup entries/lease/server missing')
 local j={};local s={handle=j,guard=opts.guard,server=opts.server,entries={},byObject={},squares={},
  publicationAttempts=0,removedObjects=0,recoveries={},localFailures=0,uncertain=false}
 for _,entry in ipairs(entries)do
  assert(type(entry)=='table'and getmetatable(entry)==nil,'world cleanup entry must be a plain table')
  local object=assert(entry.object,'world cleanup object missing')
  local square=entry.square or object:getSquare()
  assert(loaded(square)and object:getSquare()==square,'world cleanup square unloaded/replaced or object moved')
  assert(not s.byObject[object],'duplicate world cleanup object')
  local snapshot=s.squares[square]
  if not snapshot then
   snapshot={square=square,x=square:getX(),y=square:getY(),z=square:getZ(),lists={},order=#s.entries+1}
   for _,name in ipairs(lists)do snapshot.lists[name]=values(square,name)end
   s.squares[square]=snapshot
  end
  local index
  for i,value in ipairs(snapshot.lists.getObjects)do if value==object then index=i-1 end end
  assert(index~=nil and object:getObjectIndex()==index,'world cleanup object/index missing')
  local record={object=object,square=square,index=index,order=snapshot.order,status='pending',containers=containers(object),item=entry.item}
  if not record.item and type(object.getItem)=='function'then record.item=object:getItem()end
  if record.item then
   record.endpoint=record.item:getContainer()
   assert(object:getItem()==record.item and record.item:getWorldItem()==object and floorView(record.endpoint),
    'world cleanup ground identity/pointer differs')
   record.id,record.ft=record.item:getID(),record.item:getFullType()
   assert(type(record.id)=='number'and record.id%1==0 and record.id>=-2147483648 and record.id<=2147483647
    and type(record.ft)=='string'and record.ft~='','world cleanup ground ID/type missing')
  end
  s.entries[#s.entries+1]=record;s.byObject[object]=record
 end
 table.sort(s.entries,function(a,b)if a.order==b.order then return a.index>b.index end;return a.order<b.order end)
 setmetatable(j,{__index=function(_,key)if key==privateToken then return s end end,
  __newindex=function()error('opaque world cleanup journal')end,__metatable='fixture world cleanup journal'})
 -- The caller binds its generation to this handle before the first W.run.
 return j
end
function W.removed(j,object)
 local entry=state(j).byObject[object];return entry~=nil and entry.removed==true
end
function W.receipt(j)
 local s=state(j);local result={publicationAttempts=s.publicationAttempts,removedObjects=s.removedObjects,
  publicationUncertain=s.uncertain,recoveries={},states={}}
 for _,entry in ipairs(s.entries)do
  result.states[#result.states+1]={index=entry.index,status=entry.status}
 end
 for _,row in ipairs(s.recoveries)do local copy={};for k,v in pairs(row)do copy[k]=v end;result.recoveries[#result.recoveries+1]=copy end
 return result
end
local function validate(j,s)
 for square,snapshot in pairs(s.squares)do
  assert(loaded(square)and square:getX()==snapshot.x and square:getY()==snapshot.y and square:getZ()==snapshot.z,
   'world cleanup square unloaded/replaced')
  for _,name in ipairs(lists)do
   local current,present=values(square,name);local expected={}
   for _,object in ipairs(snapshot.lists[name])do
    local owned=s.byObject[object]
    if present[object]then expected[#expected+1]=object
    else assert(owned and owned.status~='pending','world cleanup foreign/pending neighbor disappeared')end
   end
   assert(#current==#expected,'world cleanup square acquired foreign/reappeared members')
   for i,object in ipairs(current)do assert(object==expected[i],'world cleanup neighbor order changed')end
  end
 end
 for _,entry in ipairs(s.entries)do
  local object,square=entry.object,entry.square
  assert(object:getSquare()==nil or object:getSquare()==square,'world cleanup owned object moved')
  local actual=containers(object)
  assert(#actual==#entry.containers,'world cleanup container identity changed')
  for i,container in ipairs(actual)do
   assert(container==entry.containers[i]and container:getItems():size()==0,'world cleanup foreign contents/container rebound')
  end
  if entry.item then
   assert(object:getItem()==entry.item and entry.item:getID()==entry.id and entry.item:getFullType()==entry.ft,
    'world cleanup ground identity/type rebound')
   local endpoint=entry.item:getContainer()
   assert(floorView(endpoint)and(endpoint==entry.endpoint or endpoint==nil and not member(square,object))
    and(entry.item:getWorldItem()==nil or entry.item:getWorldItem()==object),
    'world cleanup ground item moved/attached')
  end
  local absent=not member(square,object)
  if entry.removed then assert(absent,'removed world cleanup object reappeared')
  elseif absent then
   assert(entry.status~='pending','world cleanup object disappeared before attempt')
   entry.removed=true;s.removedObjects=s.removedObjects+1
   if entry.status~='uncertain'then entry.status='removed'end
  else
   assert(object:getSquare()==square,'world cleanup present object lost square pointer')
   if entry.item then assert(entry.item:getWorldItem()==object,'world cleanup present ground item lost pointer')end
  end
 end
 assert(s.guard(j)~=false,'world cleanup lease refused');assert(not s.poisoned,'reentrant world cleanup')
end
local function preflight(j,s)
 local ok,problem=pcall(validate,j,s)
 if not ok then s.poisoned=true;error(problem,0)end
end
local function run(j,s)
 assert(not s.uncertain,'world cleanup publication remains uncertain; native retransmission forbidden')
 assert(s.localFailures<3,'world cleanup local failure limit reached')
 preflight(j,s)
 for _,entry in ipairs(s.entries)do
  if not entry.removed then
   if entry.status=='pending'then
    entry.status='publishing';s.publicationAttempts=s.publicationAttempts+1
    local ok,problem=pcall(function()entry.square:transmitRemoveItemFromSquare(entry.object,false)end)
    if not ok then
     entry.status='uncertain';s.uncertain=true
     s.recoveries[#s.recoveries+1]={operation='transmit',index=entry.index,error=tostring(problem),publicationUncertain=true}
     preflight(j,s);error('world cleanup publication uncertain: '..tostring(problem),0)
    end
    entry.status='published';preflight(j,s)
   end
   if not entry.removed then
    -- Publication was already attempted. These exact-reference local methods
    -- never publish a second square-index packet, even after partial effects.
    local ok,problem=pcall(function()
     if not entry.localWorldDone then entry.object:removeFromWorld();entry.localWorldDone=true end
     if member(entry.square,entry.object)then entry.object:removeFromSquare()end
    end)
    if not ok then
     s.localFailures=s.localFailures+1
     s.recoveries[#s.recoveries+1]={operation='local-remove',index=entry.index,error=tostring(problem),
      failure=s.localFailures,publicationUncertain=false}
     preflight(j,s);error('world cleanup local removal failed: '..tostring(problem),0)
    end
    preflight(j,s)
    if not entry.removed then
     s.localFailures=s.localFailures+1
     s.recoveries[#s.recoveries+1]={operation='local-remove',index=entry.index,
      error='local removal left exact object present',failure=s.localFailures,publicationUncertain=false}
     error('world cleanup local removal failed: exact object still present',0)
    end
   end
  end
 end
 return W.receipt(j)
end
function W.run(j)
 local s=state(j)
 if s.running then s.poisoned=true;error('reentrant world cleanup')end
 assert(not s.poisoned,'world cleanup lease invalidated')
 s.running=true;local ok,result=pcall(run,j,s);s.running=false
 if not ok then error(result,0)end;return result
end
return W
