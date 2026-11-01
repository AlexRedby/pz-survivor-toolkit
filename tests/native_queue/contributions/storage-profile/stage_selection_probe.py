"""Instrument only owned snapshots, before Lua callbacks are captured by mods."""
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Selection observer source anchor must occur exactly once: ' + old[:80])
    return text.replace(old, new)


def mapper(text, class_name, label):
    pattern = r'(function ' + re.escape(class_name) + r':restoreSelection\(selected\)\n.*?\nend\n)'
    found = list(re.finditer(pattern, text, re.S))
    if len(found) != 1:
        raise ValueError('Expected one reviewed mapper declaration: ' + class_name)
    body = found[0].group(1)
    # These leaves have only their final return. Never wrap an outer mod chain.
    if 'for _,v in ipairs(self.itemslist)' not in body or 'selected[item2]' not in body:
        raise ValueError('Selection mapper source shape changed')
    return text[:found[0].end()] + (class_name + '.restoreSelection = require("InventorySelectionProfile").wrap("'
        + label + '", ' + class_name + '.restoreSelection)\n') + text[found[0].end():]


def transform(relative, text):
    if relative == 'BetterContainers/Reorder/Reorder_ISInventoryPage.lua':
        pattern = r'(    function ISInventoryPane:restoreSelection\(selected\)\n.*?\n    end\n)'
        found=list(re.finditer(pattern,text,re.S))
        if len(found)!=1 or 'for _, stack in ipairs(self.itemslist)' not in found[0].group(1) or 'selected[childItem]' not in found[0].group(1):
            raise ValueError('Expected one reviewed Better Containers mapper leaf')
        end=found[0].end()
        # CleanUI aliases do not exist yet during BC's load-time installation.
        # The phase attests the actual class and filters callbacks by exact pane.
        return text[:end]+'    ISInventoryPane.restoreSelection = require("InventorySelectionProfile").wrap("mapper.bc", ISInventoryPane.restoreSelection)\n'+text[end:]
    if relative == 'ISUI/ISInventoryPane.lua':
        return mapper(text, 'ISInventoryPane', 'mapper.clean')
    if relative == 'CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryPane.lua':
        return mapper(text, 'CleanUI_Vanilla_ISInventoryPane', 'mapper.vanilla')
    if relative == 'PZSurvivorToolkit/InventoryFilter.lua':
        text = replace_once(text, 'class.restoreSelection = function(self, selected)',
            'class.restoreSelection = require("InventorySelectionProfile").wrap("filter.restore", function(self, selected)')
        return replace_once(text, '        return result\n    end\n    class.prerender',
                            '        return result\n    end)\n    class.prerender')
    if relative == 'PZSurvivorToolkit/InventoryPresentation.lua':
        text = replace_once(text, 'class.refreshContainer = function(pane, ...)',
            'class.refreshContainer = require("InventorySelectionProfile").wrap("presentation.refresh", function(pane, ...)')
        return replace_once(text, '        return result\n    end\nend\n\nlocal function installPage',
                            '        return result\n    end)\nend\n\nlocal function installPage')
    exports = {'PZSurvivorToolkit/InventoryCategoryGroups.lua': ('Groups', 'split', 'categories.split'),
               'PZSurvivorToolkit/InventoryOrder.lua': ('Order', 'prioritize', 'priority'),
               'PZSurvivorToolkit/InventoryDetailSort.lua': ('Sorter', 'refresh', 'detail.sort'),
               'PZSurvivorToolkit/InventoryRows.lua': ('Rows', 'restoreSelection', 'toolkit.mapper')}
    name, member, label = exports[relative]
    return replace_once(text, 'return ' + name + '\n',
        name + '.' + member + ' = require("InventorySelectionProfile").wrap("' + label + '", '
        + name + '.' + member + ')\nreturn ' + name + '\n')


def stage(output, runtime, selected_mod_version):
    records = []
    for role, settings in runtime['roles'].items():
        if role != 'client1':
            raise ValueError('Selection observer supports one SP client only')
        mods = Path(settings['cache']) / 'mods'
        relative_paths = {'CleanUI': ['ISUI/ISInventoryPane.lua', 'CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryPane.lua'],
            'EURY_CONTAINERS': ['BetterContainers/Reorder/Reorder_ISInventoryPage.lua'],
            'PZSurvivorToolkit': ['PZSurvivorToolkit/' + name + '.lua' for name in
                ('InventoryFilter', 'InventoryPresentation', 'InventoryCategoryGroups', 'InventoryOrder', 'InventoryDetailSort', 'InventoryRows')]}
        for mod, paths in relative_paths.items():
            # Use the same version selector as the runner's mod-source resolver.
            layer = selected_mod_version(mods / mod)
            for relative in paths:
                path = layer / 'media/lua/client' / relative
                before = path.read_bytes()
                after = transform(relative, before.decode()).encode()
                path.write_bytes(after)
                records.append({'role': role, 'mod': mod, 'path': str(path.relative_to(mods)),
                    'source_sha256': hashlib.sha256(before).hexdigest(),
                    'observed_sha256': hashlib.sha256(after).hexdigest()})
        helper = mods / 'StorageProfileNative/42/media/lua/shared'
        helper.mkdir(parents=True, exist_ok=True)
        (helper / 'InventorySelectionProfile.lua').write_bytes((HERE / 'InventorySelectionProfile.lua').read_bytes())
    (Path(output) / 'selection-observer-inputs.json').write_text(json.dumps({
        'test_only': True, 'installation_modified': False, 'callback_wrapping': 'at declaration before capture',
        'observerOverheadIncluded': True, 'sources': records}, indent=2) + '\n')
