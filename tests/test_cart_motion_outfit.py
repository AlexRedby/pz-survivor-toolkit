"""Execute the motion fixture's outfit setup without launching the game."""
from pathlib import Path
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCES = tuple(ROOT / 'tests/native_queue/contributions/wooden_cart_motion' / name for name in (
    'scenario-motion-matrix.lua', 'scenario-obstacle-matrix.lua'))
LUA = shutil.which('luajit') or shutil.which('lua')

HARNESS = r'''
local pants,pantsModel
local c={female=false}
local additions,resets,clears=0,0,0
local wearFailure,modelOverride,visualTypeOverride=false,nil,nil
local locations={
 ['Base.Tshirt_DefaultTEXTURE_TINT']='base:tshirt',
 ['Base.Trousers_JeanBaggy']='base:pants',
 ['Base.Shoes_TrainerTINT']='base:shoes',
 ['Base.Skirt_Short']='base:skirt',
}
local weights={
 ['Base.Tshirt_DefaultTEXTURE_TINT']=.3,
 ['Base.Trousers_JeanBaggy']=1,
 ['Base.Shoes_TrainerTINT']=1,
 ['Base.Skirt_Short']=2,
}
local inventory={items={}}
local function make(name)
 local item={name=name,id=#inventory.items+1,container=inventory}
 function item:getFullType() return self.name end
 function item:getBodyLocation() return assert(locations[self.name]) end
 function item:getID() return self.id end
 function item:getContainer() return self.container end
 function item:getActualWeight() return assert(weights[self.name]) end
 function item:getVisual()
  return {
   getItemType=function() return visualTypeOverride or self.name end,
   getClothingItem=function()
    return {getModel=function(_,female)
     assert(type(female)=='boolean','Model lookup must use the actual body sex')
     return modelOverride or ('Skinned\\Clothes\\'..(female and 'Kate' or 'Bob')..'_Trousers.X')
    end}
   end,
  }
 end
 return item
end
function inventory:AddItem(name)
 assert(locations[name],'Unexpected fixture item')
 additions=additions+1
 local item=make(name);self.items[#self.items+1]=item;return item
end
local skirt=make('Base.Skirt_Short');inventory.items[1]=skirt
local p={female=false,worn={['base:skirt']=skirt},hair='Long',beard='Full'}
function p:isFemale() return self.female end
function p:getInventory() return inventory end
function p:clearWornItems() self.worn={};clears=clears+1 end
function p:setWornItem(location,item)
 if wearFailure and item:getFullType()=='Base.Trousers_JeanBaggy' then return end
 self.worn[location]=item
end
function p:getWornItem(location) return self.worn[location] end
function p:getWornItems()
 return {size=function() local n=0;for _ in pairs(self.worn) do n=n+1 end;return n end}
end
function p:getHumanVisual()
 return {setHairModel=function(_,name) self.hair=name end,
         setBeardModel=function(_,name) self.beard=name end}
end
function p:resetModel()
 assert(self:getWornItems():size()==3,'Model reset must follow dressing')
 resets=resets+1
end
local function weight()
 local total=0;for _,item in ipairs(inventory.items) do total=total+item:getActualWeight() end;return total
end
'''


@unittest.skipUnless(LUA, 'Requires Lua or LuaJIT')
class MotionOutfitTests(unittest.TestCase):
    def run_lua(self, checks):
        for path in SOURCES:
            with self.subTest(fixture=path.name):
                source = path.read_text()
                prefix, suffix = 'local outfit={}', 'local function owned()'
                self.assertEqual(source.count(prefix), 1, 'Missing or ambiguous real outfit helper')
                helper = prefix + source.split(prefix, 1)[1].split(suffix, 1)[0]
                result = subprocess.run([LUA, '-'], input=HARNESS + '\n' + helper + '\n' + checks,
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_repeated_setup_and_sex_change_reuse_exact_items_without_added_weight(self):
        self.run_lua(r'''
            dress()
            assert(additions==3 and #inventory.items==4)
            assert(p:getWornItem('base:skirt')==nil,'Initial skirt stayed worn')
            assert(p:getWornItem('base:tshirt'):getFullType()=='Base.Tshirt_DefaultTEXTURE_TINT')
            assert(p:getWornItem('base:shoes'):getFullType()=='Base.Shoes_TrainerTINT')
            assert(p:getWornItem('base:pants')==pants and pants:getFullType()=='Base.Trousers_JeanBaggy')
            local originalPants=pants
            local originalShirt=p:getWornItem('base:tshirt')
            local originalShoes=p:getWornItem('base:shoes')
            local originalWeight=weight()
            local originalID=pants:getID()
            for _,female in ipairs({false,true,true,false}) do
                c.female=female;p.female=female
                -- A scene/retry can start with another outfit; only worn state is cleared.
                p.worn['base:skirt']=skirt
                dress()
                assert(additions==3 and #inventory.items==4,'Scene/retry accumulated fixture clothes')
                assert(math.abs(weight()-originalWeight)<1e-9,'Scene/retry changed inventory weight')
                assert(pants==originalPants and pants:getID()==originalID)
                assert(p:getWornItem('base:pants')==originalPants)
                assert(p:getWornItem('base:tshirt')==originalShirt)
                assert(p:getWornItem('base:shoes')==originalShoes)
                assert(p:getWornItem('base:skirt')==nil and p:getWornItems():size()==3)
                assert(pantsModel:lower():gsub('\\','/'):gsub('%.x$','')==
                    'skinned/clothes/'..(female and 'kate' or 'bob')..'_trousers')
            end
            assert(clears==5 and resets==5)
            assert(p.hair=='CrewCut' and p.beard=='')
        ''')

    def test_silent_failure_to_wear_jeans_is_rejected(self):
        self.run_lua(r'''
            wearFailure=true
            local ok,why=pcall(dress)
            assert(not ok and tostring(why):find('not worn',1,true),tostring(why))
            assert(resets==0,'Invalid outfit reached model reset')
        ''')

    def test_actual_visual_model_and_item_type_are_required_on_each_setup(self):
        self.run_lua(r'''
            dress()
            modelOverride='Skinned/Clothes/Bob_Skirt'
            local ok,why=pcall(dress)
            assert(not ok and tostring(why):find('calibrated native trousers',1,true),tostring(why))
            assert(resets==1,'Wrong actual clothing model reached model reset')
            modelOverride=nil;visualTypeOverride='Base.Skirt_Short'
            ok,why=pcall(dress)
            assert(not ok and tostring(why):find('Wrong worn-jeans visual',1,true),tostring(why))
        ''')


if __name__ == '__main__':
    unittest.main()
