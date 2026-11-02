-- Test-only actual-metatable seam; native Kahlua uses the production JVM predicate.
if NativeMetatableMatches then return NativeMetatableMatches end
if TestOfflineMetatableMatches then return TestOfflineMetatableMatches end
assert(debug and debug.getmetatable,'offline binding fixture requires actual metatable access')
local actual,kind,equal=debug.getmetatable,type,rawequal
TestOfflineMetatableMatches=function(owner,expected)return kind(owner)=='table'and equal(actual(owner),expected)end
return TestOfflineMetatableMatches
