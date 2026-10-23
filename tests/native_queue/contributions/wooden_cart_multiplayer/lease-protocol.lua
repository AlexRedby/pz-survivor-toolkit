-- Test-only admission reference. Native adapters supply authority; wire data cannot create it.
local P = {}
local MAX = 2147483647
local function integer(v, low, high)
 return type(v)=='number' and v==math.floor(v) and v>=low and v<=high
end
local function text(v, limit) return type(v)=='string' and #v>0 and #v<=limit end
local function options(o)
 o=o or {};local max=o.maxCounter or MAX;local limit=o.limit or 128
 assert(integer(max,1,MAX) and integer(limit,1,1024),'Invalid admission limits')
 return max,limit
end
local function binding(b)
 if b==nil then return nil end
 assert(type(b)=='table' and (b.mode=='motion' or b.mode=='action') and b.item~=nil
  and integer(b.cart,-2147483648,2147483647) and (b.mode~='action' or b.action~=nil),'Native binding required')
 return {mode=b.mode,cart=b.cart,item=b.item,action=b.mode=='action' and b.action or nil}
end
local function same(a,b)
 return a==nil and b==nil or a~=nil and b~=nil and a.mode==b.mode and a.cart==b.cart
  and a.item==b.item and a.action==b.action
end
local function copy(s)
 local result={};for k,v in pairs(s or {}) do if k~='binding' and k~='pending' then result[k]=v end end
 return result
end
local function envelope(e,max)
 return type(e)=='table' and text(e.session,80) and integer(e.grant,1,max) and integer(e.lease,1,max)
  and integer(e.seq,1,max) and (e.op=='OPEN' or e.op=='UPDATE' or e.op=='END')
  and (e.mode=='motion' or e.mode=='action') and integer(e.cart,-2147483648,2147483647)
  and (e.op=='END' and (e.body==nil or e.body=='') or e.op~='END' and text(e.body,300))
end
local Server={};Server.__index=Server
function P.server(session,o)
 assert(text(session,80),'Server session required');local max,limit=options(o)
 return setmetatable({session=session,max=max,limit=limit,count=0,nextGrant=0,actors={}},Server)
end
function Server:observe(id,connection,actor,b)
 assert(integer(id,0,32767) and connection~=nil and actor~=nil,'Native actor binding required')
 b=binding(b);local s=self.actors[id]
 if not s then
  if self.count>=self.limit then return false end -- Never evict an ordering fence.
  self.count=self.count+1;s={grant=0,lease=0,seq=0,open=false};self.actors[id]=s
 end
 if s.connection~=connection or s.actor~=actor then
  if self.nextGrant>=self.max then s.disabled=true;s.open=false;return false end
  self.nextGrant=self.nextGrant+1
  s={connection=connection,actor=actor,grant=self.nextGrant,lease=0,seq=0,open=false}
  self.actors[id]=s
 end
 if s.disabled then return false end
 if not same(s.binding,b) then
  s.open=false;s.body=nil;s.received=nil
  if b then
   if s.lease>=self.max then s.disabled=true;return false end
   s.lease=s.lease+1;s.seq=0;s.open=true
  end
  s.binding=b
 end
 return true
end
function Server:reply(request,recipientConnection)
 if recipientConnection==nil or type(request)~='table' or not integer(request.actor,0,32767) or not text(request.nonce,120) then return nil end
 local s=self.actors[request.actor];if not s then return nil end
 local b=s.binding
 return {actor=request.actor,nonce=request.nonce,session=self.session,grant=s.grant,lease=s.lease,
  mode=b and b.mode,cart=b and b.cart,open=s.open and not s.disabled}
end
function Server:accept(id,connection,actor,e,now)
 local s=self.actors[id]
 if not s or s.disabled or s.connection~=connection or s.actor~=actor or not s.open or not envelope(e,self.max)
  or e.session~=self.session or e.grant~=s.grant or e.lease~=s.lease or e.seq<=s.seq
  or e.mode~=s.binding.mode or e.cart~=s.binding.cart or not integer(now,0,9007199254740991)
  or s.received and now<s.received then return false end
 s.seq=e.seq
 if e.op=='END' then s.open=false;s.body=nil;s.received=nil
 else s.body=e.body;s.received=now end
 return true
end
function Server:snapshot(id)
 local s=copy(self.actors[id]);s.session=self.session;s.count=self.count;s.nextGrant=self.nextGrant
 return s
end
local Receiver={};Receiver.__index=Receiver
function P.receiver(id,seed,o)
 assert(integer(id,0,32767) and text(seed,80),'Receiver actor/nonce seed required')
 local max=options(o)
 return setmetatable({id=id,seed=seed,max=max,challengeSerial=0,revision=0,grant=0,lease=0,seq=0,open=false,visible=false},Receiver)
end
function Receiver:native(connection,actor,b)
 assert(connection~=nil and actor~=nil,'Exact native receiver binding required');b=binding(b)
 if self.connection==connection and self.actor==actor and same(self.binding,b) then return false end
 if self.connection~=connection then
  self.session=nil;self.grant=0;self.lease=0;self.seq=0
 end
 self.connection=connection;self.actor=actor;self.binding=b;self.revision=self.revision+1
 self.pending=nil;self.open=false;self.visible=false;self.body=nil;self.received=nil
 -- Same-connection actor/item transitions retain the comparable grant/lease floor.
 return true
end
function Receiver:challenge()
 if not self.binding or self.challengeSerial>=self.max then return nil end
 self.challengeSerial=self.challengeSerial+1
 local request={actor=self.id,nonce=self.seed..':'..self.challengeSerial}
 self.pending={nonce=request.nonce,revision=self.revision}
 return request
end
function Receiver:reply(reply,ingressConnection)
 local pending=self.pending
 if type(reply)~='table' or not pending or not self.binding or ingressConnection~=self.connection
  or pending.revision~=self.revision or reply.actor~=self.id or reply.nonce~=pending.nonce
  or not text(reply.session,80) or not integer(reply.grant,1,self.max) or not integer(reply.lease,0,self.max)
  or type(reply.open)~='boolean' or reply.open and (reply.lease==0 or reply.mode~=self.binding.mode or reply.cart~=self.binding.cart)
  or self.session~=nil and self.session~=reply.session or reply.grant<self.grant
  or reply.grant==self.grant and (reply.lease<self.lease or reply.lease==self.lease and not self.open and reply.open) then return false end
 self.pending=nil
 local sameLease=reply.grant==self.grant and reply.lease==self.lease
 self.session=reply.session;self.grant=reply.grant;self.lease=reply.lease
 self.open=reply.open
 if not sameLease or not reply.open then self.seq=0;self.visible=false;self.body=nil;self.received=nil end
 return true
end
function Receiver:receive(e,now)
 if not self.binding or not self.open or not envelope(e,self.max) or e.session~=self.session
  or e.grant~=self.grant or e.lease~=self.lease or e.seq<=self.seq
  or e.mode~=self.binding.mode or e.cart~=self.binding.cart or not integer(now,0,9007199254740991)
  or self.received and now<self.received then return false end
 self.seq=e.seq
 if e.op=='END' then self.open=false;self.visible=false;self.body=nil;self.received=nil
 else self.body=e.body;self.received=now;self.visible=true end
 return true
end
function Receiver:suspend() self.visible=false end
function Receiver:snapshot() return copy(self) end
return P
