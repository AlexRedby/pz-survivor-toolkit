-- Rendering-only fixture: status follows read-only settlement facts without native/gameplay authority.
require=function() end
local function derive(_,name) return {Type=name} end
ISCollapsableWindow={derive=derive}
ISScrollingListBox={derive=derive}
Events={OnTickEvenPaused={Add=function() end}}
UIFont={Small=1}
getText=function(key) return key end
getTextManager=function() return {getFontHeight=function() return 14 end,
    MeasureStringX=function(_,_,text) return #text end} end
local token={}
local first={toolkitQueueOperation=token,action={}}
function first:getJobDelta() return .42 end
local current={toolkitQueueOperation=token,action={}}
function current:getJobDelta() return .73 end
local queued={toolkitQueueOperation=token}
local queue={queue={first,current,queued},current=current}
local waiting,outcome=true,nil
local reads=0
PZSurvivorToolkit={
    ActionQueue={isCraftPlanAction=function() return false end,
        isDeferredWorldAction=function() return false end,isCraftAction=function() return false end},
    ActionQueueLabels={describe=function(action)
        return {title=action==current and 'Current action' or 'Queued action',icon=function() return 'icon' end}
    end},
    ActionQueueBatch={progress=function() end},
    ActionQueueSettlement={waitingForHandAuthority=function(actual,action)
        assert(actual==queue and action==current, 'only the live current action can expose authority waiting')
        reads=reads+1
        return waiting,outcome
    end},
}
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePanel.lua'))()
local panel=PZSurvivorToolkit.ActionQueuePanel
local list={parent={queue=queue,expanded={}},width=360,height=240,items={},
    dragTexture='drag',cancelTexture='cancel'}
function list:getYScroll() return 0 end
function list:isMouseOver() return false end
function list:cancelX() return 320 end
function list:drawRect() end
function list:drawTextureScaledAspect() end
function list:setStencilRect() end
function list:clearStencilRect() end
function list:repaintStencilRect() end
function list:drawText(text) self.texts[#self.texts+1]=text end
list.drawTextRight=list.drawText
local header={item=first,operation=token,first=1,last=3,height=48,header=true,task='Group',index=1,
    groupFirst=1,groupLast=3}
local child={item=current,operation=token,first=2,last=2,height=32,index=2,groupFirst=1,groupLast=3}
local tail={item=queued,operation=token,first=3,last=3,height=32,index=3,groupFirst=1,groupLast=3}
local function draw(row)
    list.texts={}
    panel.drawRow(list,0,row,false)
    return table.concat(list.texts,'\n')
end
assert(draw(header):find('[UI_PZSurvivorToolkit_queue_waiting_server] Current action',1,true)
    and header.tooltip:find('queue_waiting_server',1,true)
    and not header.tooltip:find('[73%]',1,true),
    'a collapsed group must show authority waiting for its live current step, not its anchor')
local native=current.action
current.action=nil
assert(draw(header):find('queue_waiting_server',1,true),
    'authority waiting remains visible before native cleanup allocation')
current.action=native
list.parent.expanded[token]=true
assert(draw(child):find('queue_waiting_server',1,true), 'expanded current steps must show authority waiting')
local previousReads=reads
assert(not draw(tail):find('queue_waiting_server',1,true) and reads==previousReads,
    'queued steps must neither query nor inherit current authority waiting')
outcome='unknown'
list.parent.expanded[token]=nil
assert(draw(header):find('queue_outcome_unconfirmed',1,true)
    and header.tooltip:find('queue_outcome_unconfirmed',1,true)
    and not header.tooltip:find('queue_waiting_server',1,true),
    'an expired deadline must expose the unconfirmed outcome in the collapsed group')
assert(draw(child):find('queue_outcome_unconfirmed',1,true),
    'the current step must expose the unconfirmed outcome when expanded')
waiting=false
assert(draw(header):find('[73%]',1,true)
    and not header.tooltip:find('queue_waiting_server',1,true)
    and not header.tooltip:find('queue_outcome_unconfirmed',1,true),
    'settled authority must restore progress without a projection refresh')
queue.current=nil
previousReads=reads
assert(not draw(header):find('queue_outcome_unconfirmed',1,true) and reads==previousReads,
    'an idle group must drop its prior current-step status')
print('Queue panel authority status: collapsed/current rows, pending/unknown outcomes and immediate clearing passed.')
