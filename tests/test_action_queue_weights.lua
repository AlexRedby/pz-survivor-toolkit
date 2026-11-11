local function finite(value)return type(value)=='number'and value==value and value>-math.huge and value<math.huge end
local fixture=assert(loadfile(ProjectRoot..'/tests/support/action_queue_weights_fixture.lua'))()
local setup,impure=fixture.setup,fixture.impure
local function encloses(upper,lower,expected,slack)
    assert(finite(upper)and finite(lower)and lower<=expected and upper>=expected,
        'weight interval must enclose the independent native formula: '..tostring(expected))
    assert(upper-expected<(slack or .0001),'reviewed weight bound must retain useful carried capacity')
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
-- The qualified Host path reuses free(root)'s existing traversal. It adds
-- explicit Lua/Java mode/weight reads in that walk instead of the later native
-- aggregate call. The legacy nil-reserve path keeps its previous getter work.
for _,size in ipairs({1,16,128})do
    local s=setup();local visits,weights,aggregates=0,0,0
    for i=1,size do
        local item=s.add(s.item(.25),s.root)
        item.getUnequippedWeight=function()weights=weights+1;return .25 end
    end
    local get=s.root.getItems
    s.root.getItems=function(self)visits=visits+1;return get(self)end
    s.root.getCapacityWeight=function()aggregates=aggregates+1;return size*.25 end
    assert(s.weights.capacity(s.root,s.actor)==size*.25)
    assert(visits==1 and weights==0 and aggregates==1,'legacy exact root work changed')
    visits,weights,aggregates=0,0,0
    local upper=s.weights.capacity(s.root,s.actor,.7)
    assert(upper>=size*.25+.7 and visits==1 and weights==size and aggregates==0,
        'qualified hand release added a root traversal or called the native aggregate')
end
do
    local s=setup();s.add(s.item(1),s.root);s.add(s.item(-.25),s.root);s.root.nativeLoad=.75
    assert(s.weights.capacity(s.root,s.actor)==.75,'legacy aggregate semantics changed')
    s.root.getCapacityWeight=impure
    assert(not s.weights.capacity(s.root,s.actor,.7),'positive aggregate concealed a negative unrelated term')
    s.root.items[2].raw=0/0
    assert(not s.weights.capacity(s.root,s.actor,.7),'NaN unrelated term entered the sign proof')
    s.root.items[2].raw=1;s.root.items[2].nativeName='ForeignWeight'
    assert(not s.weights.capacity(s.root,s.actor,.7),'unknown weight subclass invoked its virtual getter')
end
do
    local s=setup();s.add(s.item(1),s.root);s.food(s.root)
    s.root.getCapacityWeight=impure
    assert(s.weights.capacity(s.root,s.actor,.7), 'nonfactory qualification did not reuse pure extra-food bounds')
    s.root.items[#s.root.items+1]=s.item(-.25)
    assert(not s.weights.capacity(s.root,s.actor,.7),'nonfactory fallback skipped unrelated sign validation')
    assert(not s.weights.shiftedCapacity(1,.1,-1)and not s.weights.shiftedCapacity(1,.1,.5)
        and not s.weights.shiftedCapacity(1,.1,0/0)and not s.weights.shiftedCapacity(1,.1,math.huge))
    assert(not s.weights.shiftedCapacity(3.4028234663852886e38,1,1),'overflow manufactured a finite capacity promise')
end
-- The double-sum domain is the native ArrayList.size() int contract, not a
-- workload budget. Reject a forged larger count before visiting any entry.
do
    local s=setup();local reads=0
    s.root.getItems=function()return{size=function()return 2147483648 end,
        get=function()reads=reads+1;error('invalid native count entered the walk')end}end
    s.root.getCapacityWeight=impure
    assert(not s.weights.capacity(s.root,s.actor,0)and reads==0)
end
-- The source-qualified generic Java getter must actually expose a normal
-- nonincreasing equipped multiplier; a zero/subnormal witness cannot prove it.
do
    local s=setup()
    assert(s.weights.nativeDiscountKnown(1,.3)and s.weights.nativeDiscountKnown(1,.69))
    assert(not s.weights.nativeDiscountKnown(1,.8)and not s.weights.nativeDiscountKnown(1,1))
    assert(not s.weights.nativeDiscountKnown(1,2)and not s.weights.nativeDiscountKnown(1,-.3))
    assert(not s.weights.nativeDiscountKnown(0,0)and not s.weights.nativeDiscountKnown(1.401298464324817e-45,0))
    assert(not s.weights.nativeDiscountKnown(1,0/0)and not s.weights.nativeDiscountKnown(0/0,0))
end
-- Explicit numeric zero still qualifies signs; a nil discount alone owns the
-- retained legacy fast path. Negative incoming U is legal native part data.
do
    local s=setup();s.add(s.item(10),s.root);s.add(s.item(-5),s.root);s.root.nativeLoad=5
    assert(s.weights.capacity(s.root,s.actor)==5)
    s.root.getCapacityWeight=impure
    assert(not s.weights.capacity(s.root,s.actor,0),'zero current hands concealed negative incoming root weight')
end
-- A positive root bag term can hide negative contents. Validate nested leaves
-- even when an earlier extra Food selected the existing nonfactory fallback.
for _,extra in ipairs({false,true})do
    local s=setup();s.add(s.item(1),s.root)
    if extra then s.food(s.root)end
    local bag=s.bag(s.root);bag.raw=10
    local child=s.add(s.item(-.9),bag.inventory)
    local bagCalls,childCalls=0,0
    bag.getUnequippedWeight=function()bagCalls=bagCalls+1;return 9.1 end
    child.getUnequippedWeight=function(self)childCalls=childCalls+1;return self.raw end
    s.root.getCapacityWeight=impure
    assert(not s.weights.capacity(s.root,s.actor,0)and childCalls>0 and bagCalls==0,
        'nested negative contents hid behind a positive bag current term or fallback')
end
-- Nested exact native owners use raw/fluid structural signs after their
-- children; do not call each recursive owner U getter on the way up again.
do
    local s=setup();local outer=s.bag(s.root);local inner=s.bag(outer.inventory)
    s.add(s.item(1),inner.inventory);local leaves,owners=0,0
    inner.getUnequippedWeight=function()owners=owners+1;return 2 end
    local leaf=inner.inventory.items[1]
    leaf.getUnequippedWeight=function()leaves=leaves+1;return 1 end
    outer.getUnequippedWeight=function()owners=owners+1;return 3 end
    s.root.getCapacityWeight=impure
    assert(s.weights.capacity(s.root,s.actor,0)and owners==1 and leaves==1,
        'nested sign proof recalculated recursive owner U or repeated a leaf getter')
end
-- A native attached container is a different source mode: no-reduction held
-- contents can outweigh hotbar 0.7 even with generic m=.3 and positive data.
-- Reject it before calling its virtual weight, including nonfactory fallback.
for _,extra in ipairs({false,true})do
    local s=setup();if extra then s.food(s.root)end
    local bag=s.bag(s.root);bag.raw=1;bag.reduction=0;bag.slot=2
    s.add(s.item(10),bag.inventory);s.root.nativeLoad=7.7
    local calls=0;bag.getHotbarEquippedWeight=function()calls=calls+1;return 7.7 end
    assert(s.weights.capacity(s.root,s.actor),'legacy native semantics changed for attached containers')
    calls=0
    assert(not s.weights.capacity(s.root,s.actor,0)and calls==0,'new authority treated hotbar container contents as generic incoming discount')
    bag.slot=-1;bag.equipped=true;bag.getEquippedWeight=function()return 10.3 end
    assert(s.weights.capacity(s.root,s.actor,0),'ordinary worn/held positive container was lost with hotbar rejection')
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
    -- Independent root fadd oracle, including cascades where changing an early
    -- term crosses later rounding boundaries. No production arithmetic is copied.
    for _,count in ipairs({1,2,17,257})do
    for _,base in ipairs({1.401298464324817e-45,1e-37,.1,1,1e15,1e30})do
    for _,gain in ipairs({1.401298464324817e-45,1e-7,.7,1e15})do
        local s=setup();local native=0
        for index=1,count do
            local value=f32(base)
            s.add(s.item(value),s.root)
            native=f32(native+(index==1 and f32(value+f32(gain))or value))
        end
        local upper=s.weights.capacity(s.root,s.actor,f32(gain))
        if upper then assert(finite(native)and upper>=native,'root release bound missed native binary32 aggregation')end
    end end end
    do
        local s=setup();s.add(s.item(f32(1)),s.root)
        for index=1,257 do s.add(s.item(f32(2^-24)),s.root)end
        local old,new=f32(1),f32(1+2^-23)
        for index=1,257 do old=f32(old+2^-24);new=f32(new+2^-24)end
        local naive=old+2^-23
        assert(new>naive,'oracle did not construct its rounding cascade')
        local upper=s.weights.capacity(s.root,s.actor,2^-23)
        assert(upper>=new,'source-bound root term probe missed the rounding cascade')
    end
    -- Double sum + one real-sum pad does not by itself enclose the current
    -- native float aggregate: zero discount must retain the fadd bound too.
    do
        local s=setup();s.add(s.item(1),s.root)
        local native,real=1,1
        for index=1,257 do
            local term=f32(3*2^-24);s.add(s.item(term),s.root)
            native=f32(native+term);real=real+term
        end
        assert(native>real*(1+1e-6),'oracle lacks its accumulated upward-rounding boundary')
        local bound=s.weights.capacity(s.root,s.actor,0)
        assert(bound and bound>=native,'qualified zero-discount path lost the native fadd bound after double accumulation')
        assert(s.weights.shiftedCapacity(real,0,258)>=native,'numeric helper incorrectly treats zero as an identity on a real sum')
    end
    print('Pure weight binary32 oracle: '..tested..' food and '..equippedCases..' equipped-bag cases passed.')
end
print('Pure action queue weights: native exact safe getters, bounded extra Food, nested bag fluids, worn/hotbar/fake reduction, loaded multiplier witnesses and unknown metadata/ownership guards passed.')
