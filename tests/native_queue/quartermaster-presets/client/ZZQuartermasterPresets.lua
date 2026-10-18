local config = require 'QueueTestSelection'
local Tags = require 'PZSurvivorToolkit/ItemTags'
local Rules = require 'PZSurvivorToolkit/QuartermasterTagRules'
local started, done = false, false
local specs = {
 {name='PZST restart all', rule={mode='all', include={'food','perishable'}, exclude={'meat'}},
  yes={'foodPerishable_fruit'}, no={'toolElectrical','craftingElectrical_material','foodPerishable_meat','foodNonPerishable_cannedJarred'}},
 {name='PZST restart any', rule={mode='any', include={'food','electrical'}, exclude={'perishable'}},
  yes={'toolElectrical','craftingElectrical_material','foodNonPerishable_cannedJarred'}, no={'foodPerishable_fruit'}},
}

local function creatorToken(value)
 if value == nil then return 'nil' end
 assert(type(value) == 'string', 'invalid persisted native creator')
 local parts = {'s'}
 for index = 1, #value do parts[#parts + 1] = string.format('%04x', string.byte(value, index)) end
 return table.concat(parts)
end

local function check()
 assert(not isClient() and not isServer(), 'real SP required')
 PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ItemTags'):setValue(true)
 assert(Tags.enabled() and LootSorter.pzstTagRuleAuthority and LootSorter.toolkitTagPicker, 'missing adapters')
 local categories = {}
 for _, category in ipairs(LootSorter.getCategories()) do categories[category] = true end
 for index, spec in ipairs(specs) do
  if config.cases[1] == 'seed' then
   assert(not LootSorter.getPresetStore()[spec.name], 'seed already contains preset')
   local verdict
   LootSorter.putPreset({name=spec.name,cats={},items={},expectExisting=false}, function(value) verdict=value end)
   assert(verdict == 'ok', 'native preset creation refused')
   local created = assert(LootSorter.getPresetStore()[spec.name])
   local generation = assert(created.gen)
   assert(created.rev == 1, 'new preset revision')
   LootSorter.openPresetEditor(spec.name, 0)
   local editor = assert(LootSorter._presetEditor)
   assert(editor.toolkitTagRuleButton, 'native editor missing tag rule control')
   editor.toolkitTagRule = Tags.normalizeRule(spec.rule)
   editor.toolkitTagRuleTouched = true
   editor.btnSave.onclick(editor, editor.btnSave)
   local saved = assert(LootSorter.getPresetStore()[spec.name])
   assert(saved.gen == generation and saved.rev == 2, 'native Save did not preserve generation and advance revision')
  end
  local store = LootSorter.getPresetStore()
  local preset = assert(store[spec.name], 'preset missing after process restart')
  assert(preset.rev == 2, 'persisted native revision differs')
  if config.cases[1] == 'seed' then
   local username = getPlayer():getUsername()
   if type(username) == 'string' then assert(preset.createdBy == username, 'persisted native creator differs') end
  end
  local creator = creatorToken(preset.createdBy)
  local rule = assert(Rules.getPreset(spec.name, preset), 'rule missing or stale generation')
  local expected = Tags.normalizeRule(spec.rule)
  assert(rule.mode == expected.mode and table.concat(rule.include, ',') == table.concat(expected.include, ',')
   and table.concat(rule.exclude, ',') == table.concat(expected.exclude, ','), 'persisted rule differs')
  assert(not Rules.getPreset(spec.name, {gen=preset.gen+1}), 'stale generation accepted')
  local cats, items = LootSorter.resolveEffective({}, {}, {[spec.name]=preset.gen}, store)
  for _ in pairs(items) do error('tag rule changed explicit item selection') end
  for _, category in ipairs(spec.yes) do
   assert(categories[category], 'missing source category '..category)
   assert(cats[category], 'rule lost matching category '..category)
  end
  for _, category in ipairs(spec.no) do
   assert(categories[category], 'missing source category '..category)
   assert(not cats[category], 'rule included excluded category '..category)
  end
  LootSorter.openPresetEditor(spec.name, 0)
  local editor = assert(LootSorter._presetEditor)
  assert(editor.toolkitTagRule and editor.toolkitTagRule.mode == expected.mode, 'reopened editor lost preset rule')
  LootSorter.closeAllWindows()
  print('[QM_PRESET] RULE index='..index..' gen='..tostring(preset.gen)..' rev='..tostring(preset.rev)..' creator='..creator..' mode='..rule.mode..' resolved=true')
 end
 print('[QM_PRESET] COMPLETE case='..config.cases[1])
end

Events.OnGameStart.Add(function() started = true end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState() or not getPlayer() or not getPlayer():getSquare() then return end
 done = true
 local ok, err = pcall(check)
 if not ok then print('[QM_PRESET] FAIL '..tostring(err)) end
end)
