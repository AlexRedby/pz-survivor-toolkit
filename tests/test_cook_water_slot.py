"""Source-backed native slot geometry; no game launch or physical pointer input.

Run explicitly with PZ_GAME (directory containing projectzomboid.jar) and
PZ_PROJECT_COOK (mod root, or its effective common/42 directory). LuaJIT is
required on PATH, or can be selected with PZ_LUAJIT. Generic discovery skips this
source check when neither source root is configured; explicit selection fails.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
EXPLICIT = __name__ == '__main__' or any('test_cook_water_slot' in arg for arg in sys.argv[1:])
SLOT_ROOT = Path('media/lua/client/Project_Cook/EvolvedRecipePanel')


LUA = r'''
local function read(path)
 local file=assert(io.open(path));local source=file:read('*a');file:close();return source:gsub('\r','')
end
local function derive(self,name)
 local class={Type=name,derive=self.derive};class.__index=class;return setmetatable(class,{__index=self})
end
ISUIElement={derive=derive,IDMax=1};ISPanel=ISUIElement
ISDock={None=0};UIHorizontalAlignment={Left=0}
-- Execute production Lua methods. Only the Java surface is modeled below; native
-- clamping, relative coordinates, attachment and callback guards remain source.
local source=read(UI_SOURCE)
for _,name in ipairs({'new','initialise','instantiate','createChildren','getKeepOnScreen','setX','setY',
 'getMouseX','getMouseY','getAbsoluteX','getAbsoluteY','getX','getY','getWidth','getHeight','getParent',
 'addChild','removeChild','isVisible','setVisible'})do
 local method=assert(source:match('(function ISUIElement:'..name..'%b().-\nend)'),name)
 assert(loadstring(method,'@'..UI_SOURCE))()
end
local pointer={x=POINTER_X,y=POINTER_Y}
getCore=function()return {getScreenWidth=function()return 1000 end,getScreenHeight=function()return 1000 end}end
getMouseX=function()return pointer.x end;getMouseY=function()return pointer.y end
getISUIStackTrace=function()return ''end
luautils={remove=function(values,item)
 for index,value in ipairs(values)do if value==item then table.remove(values,index);return end end
end}
local java={}
function java:getAbsoluteX()return self.x+(self.parent and self.parent:getAbsoluteX()or 0)end
function java:getAbsoluteY()return self.y+(self.parent and self.parent:getAbsoluteY()or 0)end
function java:AddChild(child)child.parent=self end
function java:RemoveChild(child)child.parent=nil end
for _,property in ipairs({'X','Y','Width','Height','Visible'})do
 local key=property:sub(1,1):lower()..property:sub(2)
 java['set'..property]=function(self,value)self[key]=value end
 java['get'..property]=function(self)return self[key]end
end
java.isVisible=function(self)return self.visible end
java.getXScroll=function()return 0 end;java.getYScroll=function()return 0 end
UIElement={new=function(luaTable)
 return setmetatable({visible=true,luaTable=luaTable},{__index=function(_,key)
  return java[key]or key:match('^set')and function()end
 end})
end}
require=function()end
UIFont={Small=1,Medium=2};getTextManager=function()return {getFontHeight=function()return 12 end}end
round=function(value)return math.floor(value+.5)end
assert(loadstring(read(SLOT_SOURCE),'@'..SLOT_SOURCE))()
assert(loadstring(read(INPUT_SOURCE),'@'..INPUT_SOURCE))()
local nativeDoubleClick=PJCK_ItemSlot.onMouseDoubleClick
local nativeMouseX,nativeMouseY=ISUIElement.getMouseX,ISUIElement.getMouseY
local detached
local nativeRemove=java.RemoveChild
java.RemoveChild=function(self,child)
 detached=child
 return nativeRemove(self,child)
end
local ingredient={getID=function()return 12 end};local calls=0
local recipe,base={},{}
-- Recipe effects are outside this geometry check. The actual slot guard and
-- double-click must forward one exact native ingredient request to this boundary.
local evo={padding=4,getGroupUseCapacity=function()return 1 end,
 getBaseItem=function()return base end,getRecipe=function()return recipe end,
 addPreCookItems=function(_,item)assert(item==ingredient);return item end,
 addIngredients=function(_,items,selectedRecipe,selectedBase)
  assert(#items==1 and items[1]==ingredient and selectedRecipe==recipe and selectedBase==base)
  calls=calls+1
 end}
local scroll=ISUIElement:new(300,400,200,200)
scroll.axisCount=2;scroll:initialise();scroll:instantiate()
local input=setmetatable({padding=4,slotWidth=48,slotHeight=64,scrollView=scroll,EvoPanel=evo,
 panelType='Ingredient',canAddItem=function(_,item)assert(item==ingredient);return true end},PJCK_InputPanel)
local info={item=ingredient,count=1,isPossible=false,groupKey='Tomato',usableIds={[12]=true}}
local fixture=assert(loadfile(FIXTURE_SOURCE))()
if CASE=='old-edge'then
 local slot=input:onCreateSlot(1);input:onUpdateSlot(slot,info,1,1)
 slot:setY(getMouseY())
 assert(slot:getMouseY()>=slot.width,'old top-level clamp no longer reproduces the source guard failure')
 assert(slot:onMouseDoubleClick()==false and calls==0,'old rejected slot must not dispatch a recipe')
elseif CASE=='bound'then
 local geometry=fixture.dispatchWaterSlot(input,info)
 assert(calls==1 and geometry.width==48 and geometry.height==64)
 assert(geometry.mouseX==24 and geometry.mouseY==24,'actual native coordinates must land inside icon')
 assert(#scroll.childrenInOrder==0 and next(scroll.children)==nil,'fixture child leaked after dispatch')
 assert(detached and detached.luaTable.onMouseDoubleClick==nativeDoubleClick
  and detached.luaTable.getMouseX==nativeMouseX and detached.luaTable.getMouseY==nativeMouseY,
  'fixture instance replaced native callback or coordinate methods')
elseif CASE=='invalid-dimensions'then
 for _,size in ipairs({{0,64},{-1,64},{48,47}})do
  input.slotWidth,input.slotHeight=size[1],size[2]
  local ok,problem=pcall(fixture.dispatchWaterSlot,input,info)
  assert(not ok and tostring(problem):find('dimensions unavailable',1,true),'invalid size must fail before callback')
  assert(calls==0 and #scroll.childrenInOrder==0,'invalid dimensions must not dispatch or attach a child')
 end
else error('unknown test case')end
assert(PJCK_ItemSlot.onMouseDoubleClick==nativeDoubleClick and ISUIElement.getMouseX==nativeMouseX
 and ISUIElement.getMouseY==nativeMouseY,'native callback or coordinate method was replaced')
assert(pointer.x==POINTER_X and pointer.y==POINTER_Y,'fixture moved the pointer')
print('PASS '..CASE)
'''


class CookWaterSlotGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        game, cook = os.environ.get('PZ_GAME'), os.environ.get('PZ_PROJECT_COOK')
        if not game or not cook:
            message = 'PZ_GAME and PZ_PROJECT_COOK are required for actual native/Cook slot sources'
            if EXPLICIT or game or cook:
                raise RuntimeError(message)
            raise unittest.SkipTest(message)
        cls.ui = Path(game) / 'media/lua/client/ISUI/ISUIElement.lua'
        roots = [Path(cook) / version / SLOT_ROOT for version in ('42', 'common', '')]
        cls.cook = next((root for root in roots if (root / 'PJCK_ItemSlot.lua').is_file()), roots[-1])
        for source in (cls.ui, cls.cook / 'PJCK_ItemSlot.lua', cls.cook / 'PJCK_InputPanel.lua'):
            if not source.is_file():
                raise FileNotFoundError('Required source missing: ' + str(source))
        cls.luajit = os.environ.get('PZ_LUAJIT') or shutil.which('luajit')
        if not cls.luajit:
            raise RuntimeError('LuaJIT is required on PATH, or set PZ_LUAJIT')

    def check(self, case, x, y):
        values = dict(UI_SOURCE=str(self.ui), SLOT_SOURCE=str(self.cook / 'PJCK_ItemSlot.lua'),
                      INPUT_SOURCE=str(self.cook / 'PJCK_InputPanel.lua'),
                      FIXTURE_SOURCE=str(ROOT / 'tests/native_queue/craft-ui/client/QueueCookEvolved.lua'),
                      CASE=case, POINTER_X=x, POINTER_Y=y)
        prefix = '\n'.join(key + '=' + json.dumps(value, ensure_ascii=False) for key, value in values.items())
        result = subprocess.run([self.luajit, '-'], input=prefix + '\n' + LUA, text=True,
                                capture_output=True, timeout=20, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + case, result.stdout)

    def test_actual_unattached_slot_reproduces_bottom_edge_rejection(self):
        self.check('old-edge', 990, 990)

    def test_actual_bound_slot_dispatches_and_cleans_up_at_bottom_and_ordinary_pointer(self):
        for x, y in ((990, 990), (450, 450)):
            with self.subTest(x=x, y=y):
                self.check('bound', x, y)

    def test_invalid_dimensions_reject_before_child_creation_or_dispatch(self):
        self.check('invalid-dimensions', 990, 990)


if __name__ == '__main__':
    unittest.main()
