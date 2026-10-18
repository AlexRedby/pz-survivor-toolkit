require 'TimedActions/ISDrinkFluidAction'

local isValidStart=ISDrinkFluidAction.isValidStart
function ISDrinkFluidAction:isValidStart()
 -- Match the native drink menu: fullness must not block water after a transfer.
 if self.fluidContainer:getProperties():getHungerChange()==0 then
  return not self.fluidContainer:isEmpty()
 end
 return isValidStart(self)
end
