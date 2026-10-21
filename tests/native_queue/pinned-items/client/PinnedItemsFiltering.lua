-- Physical filtering on real inventory rows; no product methods are replaced.
local F = {}
local quote = require('PinnedItemsFixture').quote
local items
local categories = {'toolElectrical','toolCarpentry','medicalTreatment'}

local function render(pane)
    pane:refreshContainer()
    pane:renderdetails(false)
end

local function clear(pane)
    pane.toolkitCategory,pane.toolkitTag,pane.toolkitTagRule=nil,nil,nil
    if pane.clearSearch then pane:clearSearch() end
    pane.searchText,pane.searchCategoryText=nil,nil
    render(pane)
end

local function physicalSet(pane)
    local visible={}
    for _, group in ipairs(pane.itemslist) do
        for _, item in ipairs(group.items or {}) do visible[item]=true end
    end
    return visible
end

local function ids(set)
    local values={}
    for _, item in ipairs(items) do if set[item] then values[#values+1]=quote(item:getID()) end end
    return '['..table.concat(values,',')..']'
end

local function assertUniverse(pane, expected)
    local available={}
    for _, entry in ipairs(PZSurvivorToolkit.InventoryFilter.choices(pane, false)) do available[entry.id]=true end
    for _,category in ipairs(categories) do
        assert(available[category],'Filter lost a fixture category from the source universe: '..category)
    end
    for category in pairs(expected or {}) do
        assert(available[category],'Filter lost a pre-filter category from the source universe: '..category)
    end
end

local function prepare(pane)
    if items then return end
    assert(PZSurvivorToolkit.Settings.inventoryFilters() and PZSurvivorToolkit.Settings.itemTags(),
        'Isolated selection profile must enable Toolkit inventory filters and tags')
    items={assert(pane.inventory:AddItem('Base.Screwdriver_Improvised')),assert(pane.inventory:AddItem('Base.Nails'))}
    local excluded=assert(pane.inventory:AddItem('Base.Bandage'))
    local organized=getActivatedMods():contains('organizedCategories_core')
    for index, item in ipairs({items[1],items[2],excluded}) do
        item:setName(index<=2 and 'Toolkit filter fixture' or 'Toolkit excluded fixture')
        if organized then
            assert(OrganizedCategories and OrganizedCategories.setItemDisplayCategory,
                'Organized Categories instance category API unavailable')
            assert(OrganizedCategories.setItemDisplayCategory(item,categories[index],true))
        else
            item:setDisplayCategory(categories[index])
        end
        assert(item:getDisplayCategory()==categories[index],'Physical item category was not applied')
    end
    assert(items[1]:getName(getPlayer())==items[2]:getName(getPlayer()),'Fixture items do not share a display name')
    assert(items[1]:getType()~=items[2]:getType(),'Fixture needs distinct types behind the same display name')
end

function F.probe(pane, mode)
    prepare(pane)
    clear(pane)
    local count=pane.inventory:getItems():size()
    local sourceCategories={}
    local choices=PZSurvivorToolkit.InventoryFilter.choices(pane, false)
    for _,entry in ipairs(choices) do sourceCategories[entry.id]=true end
    local sourceCategoryCount=#choices
    local checks={}
    local function check(label, expected, selection)
        render(pane)
        -- OC may replace itemslist after the inner restore has filtered it.
        -- Repeating the public restore must still retain both source categories.
        local saved=pane:saveSelection({})
        for pass=1,2 do pane:restoreSelection(saved);pane:renderdetails(false);assertUniverse(pane,sourceCategories) end
        assertUniverse(pane,sourceCategories)
        local visible=physicalSet(pane)
        local transfers=pane.toolkitVisibleItems or visible
        for _, item in ipairs(items) do
            assert((visible[item]==true)==(expected[item]==true),label..' showed the wrong physical item')
            assert((transfers[item]==true)==(expected[item]==true),label..' transfer gate differs from visible physical items')
        end
        for row, value in pairs(pane.selected) do
            assert(pane.items[row]==value,label..' selection differs from the rendered row')
        end
        if selection then
            local saved=pane:saveSelection({})
            local name,collapsed,rendered
            for _,group in ipairs(pane.itemslist) do
                for _,item in ipairs(group.items or {}) do
                    if item==selection then name=group.name;collapsed=pane.collapsed[group.name] end
                end
            end
            for _,value in ipairs(pane.items) do if value==selection then rendered=true end end
            assert(saved[selection]=='item',label..' lost the selected physical child (saved='..tostring(saved[selection])..
                ', group='..tostring(name)..', collapsed='..tostring(collapsed)..', renderedChild='..tostring(rendered==true)..')')
        end
        checks[#checks+1]='{"case":'..quote(label)..',"visible":'..ids(visible)..',"transferVisible":'..ids(transfers)..
            ',"categoryUniverse":true,"repeatedRestore":true,"selectionPreserved":'..tostring(selection~=nil)..'}'
    end
    -- OC's split keys differ from the original native name. A homogeneous
    -- filtered row uses that base key again, so keep both forms expanded.
    pane.collapsed[items[1]:getName(getPlayer())]=false
    for _, group in ipairs(pane.itemslist) do if group.items then pane.collapsed[group.name]=false end end
    render(pane)
    local selectedRow
    for row, value in ipairs(pane.items) do if value==items[2] then selectedRow=row end end
    assert(selectedRow,'Fixture physical child is not rendered')
    pane.selected={[selectedRow]=items[2]};pane.firstSelect=selectedRow
    pane.toolkitCategory=categories[2]
    check('exact-right',{[items[2]]=true},items[2])
    pane.toolkitCategory=categories[1]
    check('exact-left',{[items[1]]=true})
    pane.toolkitCategory=nil;pane.toolkitTag='electrical'
    check('tag-left',{[items[1]]=true})
    pane.toolkitTag=nil
    if mode=='clean' then
        assert(type(pane.searchContainer)=='function','CleanUI search callback unavailable')
        pane:searchContainer(items[1]:getType(),nil,'name')
        check('search-name',{[items[1]]=true})
        pane:searchContainer('Toolkit filter fixture',nil,'name')
        check('search-shared',{[items[1]]=true,[items[2]]=true})
        pane:searchContainer(nil,categories[2],'category')
        check('search-category',{[items[2]]=true})
        pane:searchContainer(items[1]:getType(),categories[2],'both')
        check('search-both-disjoint',{})
        assert(#pane.itemslist==0,'Combined search should have no matching item')
        pane:searchContainer('Toolkit filter fixture',categories[2],'both')
        check('search-both-match',{[items[2]]=true})
    else
        assert(not pane.searchText and not pane.searchCategoryText,'Vanilla fixture installed an unsupported search path')
    end
    clear(pane)
    check('clear',{[items[1]]=true,[items[2]]=true})
    assert(pane.inventory:getItems():size()==count,'Filtering changed the physical inventory')
    pane.selected={};pane.firstSelect=nil
    local provider=getActivatedMods():contains('organizedCategories_core') and 'organizedCategories_core' or 'native-instance'
    print('[PIN_ITEMS] FILTERING {"mode":'..quote(mode)..',"status":"passed","provider":'..quote(provider)..
        ',"searchInput":'..quote(mode=='clean' and 'CleanUI.searchContainer' or 'unsupported')..
        ',"leftId":'..quote(items[1]:getID())..',"rightId":'..quote(items[2]:getID())..
        ',"sameName":true,"distinctTypes":true,"itemCountBefore":'..count..',"itemCountAfter":'..pane.inventory:getItems():size()..
        ',"sourceCategoryCount":'..sourceCategoryCount..
        ',"checks":['..table.concat(checks,',')..']}')
end

function F.snapshot(pane, mode)
    clear(pane)
    if mode=='clean' then pane:searchContainer('Toolkit filter fixture',categories[2],'both')
    else pane.toolkitCategory=categories[2] end
    pane:setYScroll(0)
    render(pane)
end

F.clear=clear
return F
