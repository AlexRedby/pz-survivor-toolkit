local function finite(value)return type(value)=='number'and value==value and value>-math.huge and value<math.huge end
local function list(items)return {size=function()return #items end,get=function(_,index)return items[index+1]end}end
local function impure()error('weight inspection must not create ingredient prototypes or call an affected aggregate getter')end
local function encloses(upper,lower,expected,slack)
    assert(finite(upper)and finite(lower)and lower<=expected and upper>=expected,
        'weight interval must enclose the independent native formula: '..tostring(expected))
    assert(upper-expected<(slack or .0001),'reviewed weight bound must retain useful carried capacity')
end
local function setup()
    PZSurvivorToolkit={}
    instanceof=function(value,kind)
        return type(value)=='table'and (value.class==kind or kind=='InventoryItem'and
            (value.class=='Food'or value.class=='InventoryContainer'))
    end
    getClassSimpleName=function(value)return value.nativeName or value.class end
    ItemTag={LIGHT_WHEN_ATTACHED='light'}
    ZomboidGlobals={EquippedOrWornEncumbranceMultiplier=17} -- deliberately differs from loaded Java state
    InventoryItemFactory={CreateItem=impure}
    local s={nativeMultiplier=.3,scripts={}}
    ScriptManager={instance={getItem=function(_,kind)return s.scripts[kind]end}}
    local function item(w)
        local value={class='InventoryItem',nativeName='ComboItem',raw=w,slot=-1}
        value.getActualWeightUnmodded=function(self)return self.raw end
        value.getUnequippedWeight=function(self)return self.raw end
        value.getEquippedWeight=function(self)return self.raw*s.nativeMultiplier end
        value.getHotbarEquippedWeight=function(self)return self.raw*(self.light and s.nativeMultiplier or .7)end
        value.getAttachedSlot=function(self)return self.slot end
        value.isFakeEquipped=function(self)return self.fake or false end
        value.getContainer=function(self)return self.container end
        value.getWorldItem=function(self)return self.world end
        value.getFluidContainer=function(self)return self.fluid end
        value.getAmmoType=function(self)return self.ammo end
        value.hasTag=function(self,tag)return tag==ItemTag.LIGHT_WHEN_ATTACHED and self.light or false end
        return value
    end
    local function container(owner)
        local value={class='ItemContainer',items={},owner=owner}
        value.getItems=function(self)return list(self.items)end
        value.getContainingItem=function(self)return self.owner end
        value.getParent=function(self)return self.parent end
        value.getAcceptItemFunction=function(self)return self.callback end
        value.getOnlyAcceptCategory=function(self)return self.category end
        value.getCapacityWeight=function(self)return self.nativeLoad or 0 end
        return value
    end
    s.actor={class='IsoPlayer'};s.root=container();s.root.parent=s.actor
    s.actor.getInventory=function()return s.root end
    s.actor.isEquipped=function(_,value)return value.equipped or false end
    s.add=function(value,where)value.container=where;where.items[#where.items+1]=value;return value end
    s.item=item;s.container=container
    s.bag=function(where)
        local value=item(2);value.class='InventoryContainer';value.nativeName='InventoryContainer';value.reduction=80
        value.inventory=container(value);value.getInventory=function(self)return self.inventory end
        value.getWeightReduction=function(self)return self.reduction end
        value.getUnequippedWeight=impure;value.getEquippedWeight=impure;value.getHotbarEquippedWeight=impure
        if where then s.add(value,where)end
        return value
    end
    s.food=function(where)
        local value=item(.5);value.class='Food';value.nativeName='Food';value.hunger=-.06;value.base=-.06
        value.extraTypes={'Base.Tomato'};value.getExtraItems=function(self)return list(self.extraTypes)end
        value.haveExtraItems=function(self)return #self.extraTypes>0 end
        value.getHungChange=function(self)return self.hunger end
        value.getBaseHunger=function(self)return self.base end
        value.getReplaceOnUse=function()return 'Base.Bowl'end
        value.getReplaceOnUseFullType=value.getReplaceOnUse
        value.getWeight=impure;value.getActualWeight=impure;value.getExtraItemsWeight=impure
        value.getUnequippedWeight=impure;value.getEquippedWeight=impure;value.getHotbarEquippedWeight=impure
        if where then s.add(value,where)end
        return value
    end
    local extra={kind='base:food',hunger=-12,weight=.2}
    extra.getItemType=function(self)return self.kind end
    extra.getHungerChange=function(self)return self.hunger end
    extra.getActualWeight=function(self)return self.weight end
    extra.getLuaCreate=function(self)return self.callback end
    extra.getItemConfig=function(self)return self.config end
    extra.getItemConfigKey=function(self)return self.configKey end
    extra.hasComponents=function(self)return self.components or false end
    extra.getReplaceOnUse=function(self)return self.replacement end
    s.extra=extra;s.scripts['Base.Tomato']=extra
    s.shell={weight=.5,getActualWeight=function(self)return self.weight end};s.scripts['Base.Bowl']=s.shell
    s.weights=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueWeights.lua'))()
    return s
end
do
    local s=setup();local ordinary=s.add(s.item(1.25),s.root)
    local upper,lower=s.weights.unequipped(ordinary)
    assert(upper==1.25 and lower==upper,'factory-free item retains exact native weight and release credit')
    s.root.nativeLoad=.375
    upper,lower=s.weights.capacity(s.root,s.actor)
    assert(upper==.375 and lower==upper,'factory-free container retains its native load semantics')
    assert(s.weights.factoryFree(s.root))
    local food=s.food(s.root)
    assert(not s.weights.factoryFree(food)and not s.weights.factoryFree(s.root))
    s.root.getCapacityWeight=impure
    for _,case in ipairs({{-.06,.6200000047683716},{-.03,.5600000023841858},{-.015,.5299999713897705}})do
        food.hunger=case[1]
        upper,lower=s.weights.unequipped(food);encloses(upper,lower,case[2])
        assert(lower==0,'an estimated extra weight must not release space through subtraction')
        encloses(s.weights.capacity(s.root,s.actor),0,1.25+case[2])
    end
    food.hunger=-.06
    local meta;upper,lower,meta=s.weights.extraFood(food)
    assert(meta.raw==.5 and meta.shell==.5 and meta.count==1 and meta.extraUpper>=.12)
    encloses(upper,lower,.6200000047683716)
end
do
    local s=setup();local witness=s.add(s.item(1),s.root)
    local bag=s.bag(s.root);local food=s.food(bag.inventory)
    s.add(s.item(1),bag.inventory)
    s.root.getCapacityWeight=impure;bag.inventory.getCapacityWeight=impure
    encloses(s.weights.unequipped(bag),0,3.6200000047683716)
    encloses(s.weights.capacity(bag.inventory,s.actor),0,1.6200000047683716)
    bag.equipped=true
    encloses(s.weights.capacity(s.root,s.actor),0,1+2*.3+1.6200000047683716*.2)
    s.nativeMultiplier=2
    encloses(s.weights.capacity(s.root,s.actor),0,1+2*2+1.6200000047683716*.2)
    s.nativeMultiplier=.3
    bag.equipped=false;bag.slot=0
    encloses(s.weights.capacity(s.root,s.actor),0,1+3.6200000047683716*.7)
    bag.light=true
    encloses(s.weights.capacity(s.root,s.actor),0,1+3.6200000047683716*.3)
    bag.light=false;bag.slot=-1;bag.fake=true
    encloses(s.weights.capacity(s.root,s.actor),0,1+2*.3+1.6200000047683716*.2)
    bag.reduction=100
    encloses(s.weights.capacity(s.root,s.actor),0,1+2*.3)
    bag.reduction=80
    local inner=s.bag(bag.inventory);food.container=inner.inventory
    bag.inventory.items={inner};inner.inventory.items={food}
    -- A nested bag's reduction does not apply while summing outer contents.
    encloses(s.weights.capacity(s.root,s.actor),0,1+2*.3+(2+.6200000047683716)*.2)
    local fluid={class='FluidContainer',amount=.4,getOwner=function()return inner end,getAmount=function(self)return self.amount end}
    inner.fluid=fluid
    encloses(s.weights.capacity(s.root,s.actor),0,1+2*.3+(2+.6200000047683716+.4)*.2)
    s.root.items={bag}
    assert(not s.weights.capacity(s.root,s.actor),'affected equipped containers need a native multiplier witness')
    bag.fake=false
    encloses(s.weights.capacity(s.root,s.actor),0,2+2+.6200000047683716+.4)
    s.root.items={witness,bag};bag.fake=true
    witness.raw=0
    assert(not s.weights.capacity(s.root,s.actor),'zero-weight witnesses cannot bound the native loaded multiplier')
end
do
    local s=setup();local food=s.food(s.root);s.root.getCapacityWeight=impure
    for _,spec in ipairs({{'kind','base:normal'},{'hunger',0},{'hunger',-1e-43},{'hunger',-3.4028234663852886e38},
        {'hunger',math.huge},{'weight',-.1},{'weight',math.huge},{'weight',0/0},{'callback','OnCreate'},
        {'config',{}},{'configKey','x'},{'components',true},{'replacement','Base.Bowl'}})do
        local field,value=spec[1],spec[2];local previous=s.extra[field];s.extra[field]=value
        assert(not s.weights.unequipped(food),'unknown prototype path must fail without construction: '..field)
        s.extra[field]=previous
    end
    for _,value in ipairs({.49,math.huge,0/0})do
        food.raw=value;assert(not s.weights.extraFood(food),'raw base must be finite and at least the shell')
    end
    food.raw=.5
    for _,value in ipairs({0,.01,-.061,math.huge,0/0})do
        food.hunger=value
        if value==0 then encloses(s.weights.unequipped(food),0,.5)
        else assert(not s.weights.unequipped(food),'malformed hunger ratio must not enter capacity arithmetic')end
    end
    food.hunger=-.06;food.extraTypes={'Base.Unknown'}
    assert(not s.weights.capacity(s.root,s.actor))
    food.extraTypes={'Base.Tomato'}
    food.ammo='Base.Bullets9mm';assert(not s.weights.unequipped(food));food.ammo=nil
    food.world={};assert(not s.weights.unequipped(food));food.world=nil
    s.root.callback='accept';assert(not s.weights.capacity(s.root,s.actor));s.root.callback=nil
    s.root.category='Food';assert(not s.weights.capacity(s.root,s.actor));s.root.category=nil
    s.root.parent={};assert(not s.weights.capacity(s.root,s.actor));s.root.parent=s.actor
    local alias=s.bag(s.root).inventory
    alias.parent=s.actor;alias.getCapacityWeight=function()error('alias must not inspect another actor inventory')end
    assert(not s.weights.capacity(alias,s.actor),'actor capacity aliases cannot bypass the inspected item tree')
    local bag=s.bag(s.root);bag.inventory.items={bag}
    assert(not s.weights.factoryFree(bag)and not s.weights.unequipped(bag),'recursive inventories fail closed')
    bag.getInventory=function()end
    assert(not s.weights.factoryFree(bag)and not s.weights.unequipped(bag),'missing collections fail closed')
    assert(not s.weights.factoryFree(nil))
end
-- Independent IEEE-754 binary32 oracle for the native bytecode's operation
-- order. This uses nearest-even rounding, not the implementation's interval
-- padding, so tiny/large script values cannot silently understate capacity.
do
    local MAX=3.4028234663852886e38
    local function f32(value)
        if value==0 or value~=value or value==math.huge or value==-math.huge then return value end
        local sign=value<0 and -1 or 1;value=math.abs(value)
        local _,exponent=math.frexp(value)
        if exponent>128 then return sign*math.huge end
        local quantum=2^math.max(exponent-24,-149)
        local units=value/quantum;local rounded=math.floor(units);local tail=units-rounded
        if tail>.5 or tail==.5 and rounded%2==1 then rounded=rounded+1 end
        local result=rounded*quantum
        return sign*(result>MAX and math.huge or result)
    end
    assert(f32(.1)==0.10000000149011612 and f32(1.401298464324817e-45)==1.401298464324817e-45)
    assert(f32(1.0000000596046448)==1 and f32(1.0000001788139343)==1.000000238418579)
    local s=setup();local food=s.food();local tested=0
    for _,h in ipairs({-12,-1.1754943508222875e-36,-1e-30,-1e-20,-1e-5,-1,-1e10,-1e30,-1e37})do
    for _,w in ipairs({0,1.401298464324817e-45,1.1754943508222875e-38,.001,.2,20,1e15,1e30,1e36})do
    for _,raw in ipairs({0,.5,1,1e15,1e35})do
    for _,shellFraction in ipairs({0,.5,1})do
    for _,count in ipairs({1,3,6})do
    for _,fraction in ipairs({0,.01,.25,.75,1})do
        s.extra.hunger,s.extra.weight=f32(h),f32(w)
        food.raw=f32(raw);s.shell.weight=f32(food.raw*shellFraction)
        food.base=f32(-.06);food.hunger=f32(food.base*fraction)
        food.extraTypes={};for i=1,count do food.extraTypes[i]='Base.Tomato'end
        local upper,lower=s.weights.extraFood(food)
        if upper then
            local prototypeRatio=f32(f32(f32(s.extra.hunger/100)*100)/s.extra.hunger)
            local prototype=f32(s.extra.weight*prototypeRatio);local total=0
            for i=1,count do if prototype>0 then total=f32(total+prototype)end end
            local extras=f32(total*f32(.6))
            local slope=f32(f32(food.raw+extras)-s.shell.weight)
            local ratio=f32(food.hunger/food.base)
            local expected=f32(f32(slope*ratio)+s.shell.weight)
            assert(finite(expected)and lower<=expected and expected<=upper,
                'pure interval must enclose native binary32 food arithmetic')
            tested=tested+1
        end
    end end end end end end
    assert(tested>10000,'numeric oracle must exercise admitted weights rather than only rejections')
    local equippedCases=0
    for _,m in ipairs({0,1e-35,.3,1,2,1e30})do
    for _,w in ipairs({1e-37,.1,1000})do
    for _,reduction in ipairs({0,80,90,100})do
        local s=setup();local witness=s.add(s.item(f32(w)),s.root)
        witness.getEquippedWeight=function(self)return f32(self.raw*f32(m))end
        local bag=s.bag(s.root);bag.raw=f32(.5);bag.reduction=reduction;bag.equipped=true
        s.food(bag.inventory)
        local retained=f32(1-f32(reduction/100))
        local nativeBag=f32(f32(bag.raw*f32(m))+f32(0.6200000047683716*retained))
        local nativeRoot=f32(witness.raw+nativeBag)
        local upper,lower=s.weights.capacity(s.root,s.actor)
        assert(finite(upper)and lower<=nativeRoot and nativeRoot<=upper,
            'loaded Java multiplier witness must bound rounded equipped bag arithmetic')
        equippedCases=equippedCases+1
    end end end
    print('Pure weight binary32 oracle: '..tested..' food and '..equippedCases..' equipped-bag cases passed.')
end
print('Pure action queue weights: native exact safe getters, bounded extra Food, nested bag fluids, worn/hotbar/fake reduction, loaded multiplier witnesses and unknown metadata/ownership guards passed.')
