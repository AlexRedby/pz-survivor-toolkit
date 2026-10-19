"""Reviewed upstream inputs, their Toolkit owners and focused source checks."""
from pathlib import Path

try:
    from .queue_checks import native, pack
    from .queue_checks.mod_selection import mod_layers
except ImportError:
    from queue_checks import native, pack
    from queue_checks.mod_selection import mod_layers


INTEGRATIONS = {
    'CleanUI': {
        'owners': ['client/PZSurvivorToolkit/InventoryClasses.lua', 'client/PZSurvivorToolkit/InventoryFilter.lua',
                   'client/PZSurvivorToolkit/InventoryLayout.lua', 'client/PZSurvivorToolkit/InventoryInteraction.lua',
                   'client/PZSurvivorToolkit/InventoryTags.lua'],
        'option': 'cleanui_inventory_pane', 'root': 'media/lua/client/ISUI', 'argument': 'ISInventoryPane.lua',
        'tests': {name: ['ISInventoryPane.lua'] for name in (
            'test_inventory_tags.lua', 'test_inventory_filter.lua', 'test_inventory_layout.lua',
            'test_inventory_interaction.lua')},
    },
    'ContainerCapacityIndicator': {
        'owners': ['client/PZSurvivorToolkit/InventoryClasses.lua', 'client/000ToolkitCCICompatibility.lua'],
        'option': 'cci_source', 'root': 'media/lua/client', 'argument': 'ContainerCapacityIndicator.lua',
        'tests': {'test_cci_compat.lua': ['ContainerCapacityIndicator.lua']},
    },
    'BravoItemDetails': {
        'owners': ['client/PZSurvivorToolkit/InventoryClasses.lua', 'client/000ToolkitItemDetailsCompatibility.lua'],
        'option': 'item_details_source', 'root': 'media/lua/client',
        'tests': {'test_item_details.lua': ['BravoItemDetails.lua', 'BravoItemDetailsConfig.lua',
                                          'BravoItemDetailsSorter.lua']},
    },
    'Navigator': {
        'owners': ['client/PZSurvivorToolkit/Navigator.lua'],
        'option': 'navigator_source', 'root': 'media/lua/client/NavigatorRadio',
        'tests': {'test_navigator.lua': ['MonitorConfig.lua', 'MonitorRender.lua', 'NavigatorMonitorDrag.lua']},
    },
    'TVRadio_ReInvented': {
        'owners': ['client/PZSurvivorToolkit/TVRadio.lua', 'JavaPatches/src/net/alexredby/pztoolkitjavapatches/TVVideoPaths.java',
                   'client/PZSurvivorToolkit/TVDeviceResolver.lua'],
        'option': 'tv_source', 'root': 'media/lua/client/RadioCom',
        'argument': 'RadioWindowModules/RWMMergedTV.lua',
        'tests': {'test_tv_controls.lua': ['RadioWindowModules/RWMMergedTV.lua', 'ISRadioWindow.lua'],
                  'test_tv_videos.lua': ['RadioWindowModules/RWMMergedTV.lua']},
    },
    'MoodleFramework': {
        'owners': ['client/PZSurvivorToolkit/MedicineMoodles.lua',
                   'shared/PZSurvivorToolkit/MedicineEffects.lua',
                   'server/PZSurvivorToolkit/MedicineMoodles.lua'],
        'option': 'medicine_framework_source', 'root': 'media/lua/client', 'argument': 'MF_ISMoodle.lua',
        'tests': {'test_medicine_moodles.lua': ['MF_ISMoodle.lua']},
    },
    'MPFastForward': {
        'owners': ['server/000ToolkitMPFFCompatibility.lua'],
        'option': 'mpff_source', 'root': 'media/lua',
        'tests': {'test_mpff_compat.lua': ['shared/MPFastForward_Config.lua', 'server/MPFastForward_Server.lua']},
    },
    'EURY_CONTAINERS': {
        'owners': ['client/000ToolkitBCCompatibility.lua'],
        'option': 'bc_filter_source', 'root': 'media/lua/client/BetterContainers/Categorize',
        'argument': 'CategoryFilters.lua',
        'tests': {'test_bc_filter_compat.lua': ['CategoryFilters.lua']},
    },
}


def source_path(root, relative):
    """Resolve an effective source file, with the selected version overriding common."""
    path = next((layer / relative for layer in reversed(mod_layers(root)) if (layer / relative).is_file()), None)
    if path is None:
        raise ValueError('Missing upstream source: ' + str(root / relative))
    return path


def configure(args, project, requested):
    checks = set(requested)
    for id in args.integration:
        checks.update(INTEGRATIONS[id]['tests'])
    selected = set(args.integration)
    if args.pack_lock:
        selected.update(id for id, spec in INTEGRATIONS.items() if checks.intersection(spec['tests']))
    if not args.pack_lock or not args.game:
        raise ValueError('Integration source checks require --pack-lock and --game')
    if not selected:
        raise ValueError('Select --integration or a mapped --test with --pack-lock; see --list-integrations')
    identifiers = native._metadata(project / 'SurvivorQoL-selected.ini')['Mods'].split(';')
    locations = pack.validate(args.pack_lock.resolve(), project, args.game.resolve(), identifiers)
    for id in sorted(selected):
        if id not in locations:
            raise ValueError('Integration mod is absent from the locked pack: ' + id)
        spec = INTEGRATIONS[id]
        files = sorted({name for test, sources in spec['tests'].items() if test in checks for name in sources})
        resolved = [source_path(Path(locations[id]), str(Path(spec['root']) / name)) for name in files]
        bases = {path.parents[len(Path(name).parts) - 1] for path, name in zip(resolved, files)}
        if len(bases) != 1:
            raise ValueError(id + ': this source check requires one Lua tree; effective inputs span version/common layers')
        value = bases.pop() / spec.get('argument', '')
        option = spec['option']
        previous = getattr(args, option)
        if previous and previous.resolve() != value.resolve():
            raise ValueError('--' + option.replace('_', '-') + ' differs from locked integration inputs')
        setattr(args, option, value)
        print('Upstream ' + id + ' -> ' + ', '.join(spec['owners']) + ' -> '
              + ', '.join(test for test in spec['tests'] if test in checks))
    for test, option, relative in (('test_tv_controls.lua', 'native_radio_root', 'media/lua/client'),
                                    *[(test, 'native_inventory_pane', 'media/lua/client/ISUI/ISInventoryPane.lua')
                                      for test in INTEGRATIONS['CleanUI']['tests']]):
        if test in checks:
            value = args.game.resolve() / relative
            previous = getattr(args, option)
            if previous and previous.resolve() != value:
                raise ValueError('--' + option.replace('_', '-') + ' differs from --game')
            setattr(args, option, value)
    requested.update(checks)
