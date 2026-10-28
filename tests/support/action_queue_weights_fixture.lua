-- Shared test-only scene builders; no production implementation or arithmetic is copied.
local function list(items)return {size=function()return #items end,get=function(_,index)return items[index+1]end}end
local function impure()error('weight inspection must not create ingredient prototypes or call an affected aggregate getter')end
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
return {setup=setup,list=list,impure=impure}
