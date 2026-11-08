assert(NativeActionRoot,'device target checks require --game or --native-action-root')
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.native('shared/RadioCom/ISRadioAction.lua')
-- Execute the installed native Lua, with explicit DeviceData doubles. This
-- establishes the upstream boundary; only an in-game run proves Java effects.
local actor=f.player
local faced
actor.faceThisObject=function(_,object)faced=object end
for _,kind in ipairs({'IsoTelevision','IsoRadio'})do
    for _,loss in ipairs({'removed','moved'})do
        for _,mode in ipairs({'SetVolume','SetChannel'})do
            local origin,destination={class='IsoGridSquare'},{class='IsoGridSquare'}
            local object={class=kind,square=origin,index=1}
            local data={volume=.5,channel=90000,on=true,power=1,parent=object}
            object.getSquare=function(self)return self.square end
            object.getObjectIndex=function(self)return self.index end
            object.getDeviceData=function()return data end
            data.getParent=function(self)return self.parent end
            data.getIsTurnedOn=function(self)return self.on end
            data.getPower=function(self)return self.power end
            data.getIsTelevision=function()return kind=='IsoTelevision'end
            data.isVehicleDevice=function()return false end
            data.isIsoDevice=function()return true end
            data.stopOrTriggerSoundByName=function()end
            data.setDeviceVolume=function(self,value)self.volume=value end
            data.setChannel=function(self,value)self.channel=value end
            local value=mode=='SetVolume'and .75 or 95000
            local action=ISRadioAction:new(mode,actor,object,value)
            if loss=='removed'then object.square,object.index=nil,-1
            else object.square=destination end
            assert(action.device==object and action.deviceData==data and data:getParent()==object)
            assert(action:isValid()==true,'native validity unexpectedly rejected stale world binding')
            faced=nil;action:update();assert(faced==object,'native update no longer targets retained parent')
            if mode=='SetVolume'then action:performSetVolume();assert(data.volume==.75)
            else action:performSetChannel();assert(data.channel==95000)end
        end
    end
end
if TestCoverage then TestCoverage('native-stale-device','passed')end
print('Device target source: native retained-data validity/update/setter boundary passed; Java outcomes require native scenarios.')
