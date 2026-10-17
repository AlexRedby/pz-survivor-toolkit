local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true,'CartMotionConfig.disposable must be true')

function CartLabSelectScenes(cases)
 local requested=config.scenes
 if requested==nil then return cases end
 assert(type(requested)=='table' and #requested>0,'CartMotionConfig.scenes must be a nonempty array')
 local names,count={},0
 for index,name in pairs(requested) do
  assert(type(index)=='number' and index%1==0 and index>=1 and index<=#requested,
   'CartMotionConfig.scenes must be a dense array')
  assert(type(name)=='string' and name~='','CartMotionConfig.scenes requires nonempty exact names')
  assert(not names[name],'Duplicate cart scene: '..name)
  names[name]=true;count=count+1
 end
 assert(count==#requested,'CartMotionConfig.scenes must be a dense array')
 local selected={}
 for _,case in ipairs(cases) do
  if names[case.name] then selected[#selected+1]=case end
 end
 assert(#selected==count,'Unknown cart scene in CartMotionConfig.scenes')
 return selected
end
