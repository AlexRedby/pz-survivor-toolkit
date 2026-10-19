-- Actual UI and timed actions; no lifecycle or effect callback is replaced here.
require 'Project_Cook/PJCK_Window'
require 'Project_Cook/PJCK_CookingUI'
require 'Project_Cook/PJCK_Config'
local Evolved={}
local methods={'new','isValidStart','start','perform','complete','getDuration'}
local function queue(player)return ISTimedActionQueue.getTimedActionQueue(player)end
local function values(list)
 local result={};for _,value in ipairs(list)do result[#result+1]=value end;return result
end
function Evolved.start(player,state,ids,enabled)
 local run={player=player,state=state,ids=ids,enabled=enabled,actions={},seen={},progress={},durations={},snapshots={}}
 run.previousSetting=PJCK_Config.get().baseItemHandling
 PJCK_Config.get().baseItemHandling='return_source'
 assert(PJCK_Config.shouldReturnBaseItemToSource(),'evolved in-memory return-source setting did not apply')
 assert(not PJCK_CookingUI.IsWindowOpen(player:getPlayerNum()),'evolved fixture inherited a registered cooking window')
 PJCK_CookingUI.OnOpenPanel(player)
 run.window=assert(PJCK_CookingUI.GetWindowInstance(player:getPlayerNum()),'native cooking window registration missing')
 run.window:switchToPanel('evolved')
 local panel=assert(run.window.EvoPanel,'Project Cook real EvoPanel missing');run.panel=panel
 assert(getmetatable(panel)==PJCK_EvoPanel,'evolved panel replaced')
 assert(PZSurvivorToolkit.ActionQueueCompat.isInstalled('Project_Cook'),'evolved source adapter is not verified')
 panel:setContainers(state.containers)
 local base=assert(state.root:getItemById(ids.base.id))
 panel:setBaseItem(base)
 run.sourceDeferred=base:getContainer()==state.root:getItemById(ids.bags[1]):getItemContainer()and #queue(player).queue==0
 assert(run.sourceDeferred,'return-source selection moved the base before cooking')
 local recipes=assert(panel:getRecipes(base));local recipe
 for i=0,recipes:size()-1 do
  local candidate=recipes:get(i);local result=candidate:getResultItem()
  if result=='Salad'or result=='Base.Salad'then assert(not recipe,'ambiguous real Salad recipe');recipe=candidate end
 end
 assert(recipe,'real Bowl->Salad evolved recipe unavailable');run.recipe=recipe
 panel:setRecipe(recipe)
 panel:getInputList('Ingredient');panel:getInputList('Seasoning')
 local ingredient=assert(state.root:getItemById(ids.ingredient.id))
 local spice=assert(state.root:getItemById(ids.spice.id))
 assert(not ingredient:isCooked()and not ingredient:isRotten(),'fixture Tomato is not raw usable food')
 assert(recipe:getItemRecipe(ingredient):getUse()==6 and recipe:getItemRecipe(spice):getUse()==1,
  'native Salad portion definitions differ')
 panel:addIngredients({ingredient,spice},recipe,base)
 run.command=assert(queue(player).queue[1],'real EvoPanel did not queue cooking')
 run.tail=ISReadABook:new(player,state.book)
 assert(run.tail.minutesPerPage==2.0 and run.tail.maxTime>1,'evolved reader duration changed')
 ISTimedActionQueue.add(run.tail)
 if enabled then assert(run.command.toolkitQueueOperation and run.tail.toolkitQueueOperation~=run.command.toolkitQueueOperation,
  'evolved reader operation not independent')end
 return run
end
function Evolved.observe(run)
 local q=queue(run.player)
 for _,action in ipairs(q.queue)do
  if action.Type=='ISAddItemInRecipe'and action.recipe==run.recipe and not run.seen[action]then
   local id=action.usedItem:getID()
   assert(id==run.ids.ingredient.id or id==run.ids.spice.id,'evolved selected an unrelated ingredient')
   run.seen[action]=true;run.actions[#run.actions+1]=action
   local duration=action:getDuration()
   assert(duration==100-run.player:getPerkLevel(Perks.Cooking)*2.5 and not run.player:isTimedActionInstant(),
    'evolved action duration changed')
   run.durations[#run.durations+1]=duration
   local snapshot={};for _,name in ipairs(methods)do snapshot[name]=action[name]end
   run.snapshots[action]=snapshot
   if run.enabled then
    assert(action.toolkitQueueOperation==run.command.toolkitQueueOperation and PZSurvivorToolkit.ActionQueueDefinitions.inspect(action),
     'expanded native recipe action lost source grouping or contract')
   end
  end
 end
 local current=q.current
 for i,action in ipairs(run.actions)do
  if current==action and action:isStarted()and action:getJobDelta()>0 then run.progress[i]=true end
 end
 if current==run.tail and run.tail:isStarted()and run.tail:getJobDelta()>0 then
  run.tailProgress=true
  if run.returnsBeforeRead==nil then
   local base=run.panel:resolveCurrentBaseItem(true)
   local source=run.state.root:getItemById(run.ids.bags[1]):getItemContainer()
   local ingredient=run.state.root:getItemById(run.ids.ingredient.id)
   local ingredientSource=run.state.root:getItemById(run.ids.bags[2]):getItemContainer()
   run.returnsBeforeRead=base and base:getFullType()=='Base.Salad'and base:getContainer()==source
    and ingredient and ingredient:getContainer()==ingredientSource and not run.state.root:getItemById(run.ids.spice.id)or false
  end
 end
end
function Evolved.finish(run,authority)
 local unchanged=true;local inputs,progress={},{}
 for i,action in ipairs(run.actions)do
  inputs[i]=action.usedItem:getID()
  if run.progress[i]then progress[#progress+1]=i end
  for _,name in ipairs(methods)do if action[name]~=run.snapshots[action][name]then unchanged=false end end
 end
 local selected=run.panel:resolveCurrentBaseItem(true)
 local dish=authority.dishes[1]
 local expected=authority.outputs==1 and authority.base.totalCount==0 and authority.spice.totalCount==0
  and authority.ingredient.totalCount==1 and authority.ingredient.sourceCount==1
  and math.abs(authority.ingredient.hunger-(run.ids.ingredient.hunger+0.06*(1-0.03*run.ids.cookingLevel)))<0.00001
  and dish and dish.kind=='Base.Salad'and dish.sourceCount==1 and dish.totalCount==1
  and #dish.extras==1 and dish.extras[1]=='Base.Tomato'and #dish.spices==1 and dish.spices[1]=='Base.Pepper'
 local reason=not expected and 'native-evolved-effect-differs'or not authority.tailRead and 'native-independent-tail-not-preserved'
  or not run.returnsBeforeRead and 'native-returns-not-before-tail'or nil
 local value={event='case',id=run.ids.case,status=reason and 'failed'or 'passed',reason=reason,
  requested=2,actions=#run.actions,actionInputIds=inputs,progressIds=progress,nativeDurations=values(run.durations),
  cookingLevel=run.player:getPerkLevel(Perks.Cooking),sourceMethodsUnchanged=unchanged,
  callbackClass='PJCK_EvoPanel',sourceDeferred=run.sourceDeferred,sourceVerified=true,tokensGrouped=run.enabled,
  tailIndependent=not run.enabled or run.tail.toolkitQueueOperation~=run.command.toolkitQueueOperation,
  tailProgress=run.tailProgress==true,returnsBeforeRead=run.returnsBeforeRead==true,selectedDishId=selected and selected:getID()or -1}
 for key,entry in pairs(authority)do if key~='case'then value[key]=entry end end
 PJCK_Config.get().baseItemHandling=run.previousSetting
 run.window:onCloseClick()
 assert(not PJCK_CookingUI.IsWindowOpen(run.player:getPlayerNum()),'evolved cooking window registration leaked')
 return value,reason
end
return Evolved
