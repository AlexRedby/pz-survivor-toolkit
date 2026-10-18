"""Reviewed upstream inputs, their Toolkit owners and focused source checks."""
from pathlib import Path

try:
    from .queue_checks import native, pack
except ImportError:
    from queue_checks import native, pack


INTEGRATIONS = {
    'Navigator': {
        'owners': ['client/PZSurvivorToolkit/Navigator.lua'],
        'option': 'navigator_source', 'root': 'media/lua/client/NavigatorRadio',
        'tests': {'test_navigator.lua': ['MonitorConfig.lua', 'MonitorRender.lua', 'NavigatorMonitorDrag.lua']},
    },
    'TVRadio_ReInvented': {
        'owners': ['client/PZSurvivorToolkit/TVRadio.lua', 'client/PZSurvivorToolkit/TVVideos.lua',
                   'client/PZSurvivorToolkit/TVDeviceResolver.lua'],
        'option': 'tv_source', 'root': 'media/lua/client/RadioCom',
        'argument': 'RadioWindowModules/RWMMergedTV.lua',
        'tests': {'test_tv_controls.lua': ['RadioWindowModules/RWMMergedTV.lua', 'ISRadioWindow.lua'],
                  'test_tv_videos.lua': ['RadioWindowModules/RWMMergedTV.lua']},
    },
    'Quartermaster': {
        'owners': ['client/PZSurvivorToolkit/QuartermasterTags.lua',
                   'shared/PZSurvivorToolkit/QuartermasterTagRules.lua',
                   'client/PZSurvivorToolkit/QuartermasterTagRuleClient.lua',
                   'server/PZSurvivorToolkit/QuartermasterTagRuleAuthority.lua',
                   'client/PZSurvivorToolkit/QuartermasterCraftUI.lua'],
        'option': 'quartermaster_source', 'root': 'media/lua',
        'tests': {'test_quartermaster_tags.lua': ['client/LootSorter_Picker.lua'],
                  'test_quartermaster_tag_rules.lua': ['shared/LootSorter_Presets.lua', 'shared/LootSorter_Util.lua',
                                                      'shared/LootSorter_Plan.lua', 'client/LootSorter_Core.lua'],
                  'test_quartermaster_item_routing.lua': ['shared/LootSorter_Plan.lua'],
                  'test_quartermaster_craft_ui.lua': ['client/LootSorter_CraftMenu.lua']},
    },
}


def source_path(root, relative):
    """Resolve the same active B42 layer, common fallback and legacy root as the pack."""
    versions = [(tuple(map(int, child.name.split('.'))), child) for child in root.iterdir()
                if child.is_dir() and native.VERSION.fullmatch(child.name)
                and (42,) <= tuple(map(int, child.name.split('.'))) <= (42, 21)]
    layers = ([max(versions)[1]] if versions else []) + [root / 'common', root]
    path = next((layer / relative for layer in layers if (layer / relative).is_file()), None)
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
                                    ('test_quartermaster_craft_ui.lua', 'native_action_root', 'media/lua')):
        if test in checks:
            value = args.game.resolve() / relative
            previous = getattr(args, option)
            if previous and previous.resolve() != value:
                raise ValueError('--' + option.replace('_', '-') + ' differs from --game')
            setattr(args, option, value)
    requested.update(checks)
