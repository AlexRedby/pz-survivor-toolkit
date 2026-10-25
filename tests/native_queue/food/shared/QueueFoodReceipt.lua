-- Keep readiness and its diagnostic on the same strict field comparison.
local Receipt={}
function Receipt.differences(current,expected,encode)
 local differences={}
 for field,value in pairs(expected)do
  local actual=current[field]
  local matches
  if type(value)=='number'then
   local tolerance=(field=='hunger'or field=='thirst')and .01 or .0001
   matches=type(actual)=='number'and math.abs(actual-value)<=tolerance
  elseif type(value)=='table'then
   matches=type(actual)=='table'and encode(actual)==encode(value)
  else matches=actual==value end
  if not matches then
   differences[#differences+1]={field=field,expected=value,actual=actual,
    expectedType=type(value),actualType=type(actual)}
  end
 end
 table.sort(differences,function(a,b)return a.field<b.field end)
 return differences
end
return Receipt
