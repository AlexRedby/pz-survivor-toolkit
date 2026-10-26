"""Reviewed upstream inputs, their Toolkit owners and focused source checks."""
import os
from pathlib import Path
from typing import NamedTuple

try:
    from .queue_checks import native, pack
    from .queue_checks.mod_selection import mod_layers
except ImportError:
    from queue_checks import native, pack
    from queue_checks.mod_selection import mod_layers


class Source(NamedTuple):
    variable: str
    path: str
    optional: bool = False


GAME_SOURCES = {
    'native_mod_options': 'media/lua/client/PZAPI/ModOptions.lua',
    'native_inventory_pane': 'media/lua/client/ISUI/ISInventoryPane.lua',
    'native_inventory_context_menu': 'media/lua/client/ISUI/ISInventoryPaneContextMenu.lua',
    'native_radio_root': 'media/lua/client',
    'native_uninstall': 'media/lua/shared/Vehicles/TimedActions/ISUninstallVehiclePart.lua',
    'native_vehicles': 'media/lua/server/Vehicles/Vehicles.lua',
    'native_action_root': 'media/lua',
    'wishlist_game_root': '.',
}

CLEAN_PANE = Source('CleanUIInventoryPaneSource', 'ISUI/ISInventoryPane.lua')
CLEAN_PAGES = (
    Source('CleanUIInventoryPageSource', 'ISUI/ISInventoryPage.lua'),
    Source('CleanUIVanillaInventoryPageSource', 'CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryPage.lua'),
)
INTEGRATIONS = {
    'VehicleRepairOverhaul': {
        'owners': ['shared/PZSurvivorToolkit/VehicleGlass.lua',
                   'shared/000ToolkitVROGlassCompatibility.lua', 'client/000ToolkitVROGlassRecipes.lua'],
        'option': 'vro_source', 'root': '.',
        'tests': {'test_vehicle_glass.lua': (
            Source('VRORecipesSource', 'media/lua/client/VRO_Recipes.lua'),
            Source('VROPartListsSource', 'media/lua/client/VRO_PartLists.lua'),
            Source('VROFixingRegistrationSource', 'media/lua/shared/FixingRecipeHandler.lua'),
            Source('VROScriptFixingsSource', 'media/scripts/vehicles/vehiclesfixing.txt'),
        )},
    },
    'CleanUI': {
        'owners': ['client/PZSurvivorToolkit/InventoryClasses.lua', 'client/PZSurvivorToolkit/InventoryFilter.lua',
                   'client/PZSurvivorToolkit/InventorySearch.lua',
                   'client/PZSurvivorToolkit/InventoryLayout.lua', 'client/PZSurvivorToolkit/InventoryInteraction.lua',
                   'client/PZSurvivorToolkit/InventoryTags.lua',
                   'client/PZSurvivorToolkit/ActionQueueOperations.lua',
                   'client/PZSurvivorToolkit/ContainerConfigurationMenus.lua',
                   'client/PZSurvivorToolkit/SmartDeposit.lua'],
        'option': 'cleanui_inventory_pane', 'root': 'media/lua/client', 'argument': 'ISUI/ISInventoryPane.lua',
        'tests': {
            'test_inventory_tags.lua': (CLEAN_PANE,),
            'test_inventory_filter.lua': (CLEAN_PANE, Source('CleanUIInventoryTransferHandlerSource',
                                                          'ISUI/ISInventoryPageTransferHandler.lua', optional=True)),
            'test_inventory_search.lua': (CLEAN_PANE,),
            'test_inventory_layout.lua': (CLEAN_PANE,),
            'test_inventory_interaction.lua': (CLEAN_PANE,),
            'test_inventory_transfer_operations.lua': (CLEAN_PANE, Source('CleanUIVanillaInventoryPaneSource',
                                                                       'CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryPane.lua')),
            'test_container_configuration_menus.lua': CLEAN_PAGES,
            'test_smart_deposit.lua': CLEAN_PAGES,
            'test_inventory_refresh.lua': CLEAN_PAGES,
        },
        'game_inputs': {
            **{test: ('native_inventory_pane',) for test in ('test_inventory_tags.lua', 'test_inventory_filter.lua',
                                                           'test_inventory_layout.lua', 'test_inventory_interaction.lua')},
            **{test: ('native_action_root',) for test in ('test_inventory_transfer_operations.lua',
                                                        'test_container_configuration_menus.lua', 'test_smart_deposit.lua',
                                                        'test_inventory_refresh.lua')},
        },
    },
    'Navigator': {
        'owners': ['client/PZSurvivorToolkit/Navigator.lua'],
        'option': 'navigator_source', 'root': 'media/lua/client/NavigatorRadio',
        'tests': {'test_navigator.lua': (Source('NativeNavigatorConfig', 'MonitorConfig.lua'),
                                         Source('NativeNavigatorRender', 'MonitorRender.lua'),
                                         Source('NativeNavigatorDrag', 'NavigatorMonitorDrag.lua'))},
    },
    'TVRadio_ReInvented': {
        'owners': ['client/PZSurvivorToolkit/TVRadio.lua', 'JavaPatches/src/net/alexredby/pztoolkitjavapatches/TVVideoPaths.kt',
                   'client/PZSurvivorToolkit/TVDeviceResolver.lua'],
        'option': 'tv_source', 'root': 'media/lua/client/RadioCom',
        'argument': 'RadioWindowModules/RWMMergedTV.lua',
        'tests': {'test_tv_controls.lua': (Source('TVSource', 'RadioWindowModules/RWMMergedTV.lua'),
                                           Source('NativeTVWindowSource', 'ISRadioWindow.lua')),
                  'test_tv_videos.lua': (Source('TVSource', 'RadioWindowModules/RWMMergedTV.lua'),)},
        'game_inputs': {'test_tv_controls.lua': ('native_radio_root',)},
    },
    'MoodleFramework': {
        'owners': ['client/PZSurvivorToolkit/MedicineMoodles.lua',
                   'shared/PZSurvivorToolkit/MedicineEffects.lua',
                   'server/PZSurvivorToolkit/MedicineMoodles.lua'],
        'option': 'medicine_framework_source', 'root': 'media/lua/client', 'argument': 'MF_ISMoodle.lua',
        'tests': {'test_medicine_moodles.lua': (Source('NativeMedicineFrameworkSource', 'MF_ISMoodle.lua'),)},
    },
    'MPFastForward': {
        'owners': ['server/000ToolkitMPFFCompatibility.lua', 'client/PZSurvivorToolkit/AlarmClock.lua'],
        'option': 'mpff_source', 'root': 'media/lua',
        'tests': {'test_mpff_compat.lua': (Source('NativeMPFFConfigSource', 'shared/MPFastForward_Config.lua'),
                                          Source('NativeMPFFServerSource', 'server/MPFastForward_Server.lua')),
                  'test_alarm_clock.lua': (Source('NativeMPFFConfigSource', 'shared/MPFastForward_Config.lua'),
                                           Source('NativeMPFFClientSource', 'client/MPFastForward_Client.lua'),
                                           Source('NativeMPFFPanelSource', 'client/ui/MPFF_Panel.lua'))},
    },
    'EURY_CONTAINERS': {
        'owners': ['client/000ToolkitBCCompatibility.lua', 'client/000ToolkitBCSmartDepositCompatibility.lua',
                   'client/PZSurvivorToolkit/ContainerConfigurationMenus.lua'],
        'option': 'bc_filter_source', 'root': 'media/lua/client/BetterContainers',
        'argument': 'Categorize/CategoryFilters.lua',
        'tests': {'test_bc_filter_compat.lua': (
                      Source('NativeBCFilterSource', 'Categorize/CategoryFilters.lua'),
                      Source('NativeBCInventoryCategorySource', 'Categorize/InventoryCategory.lua'),
                      Source('NativeBCCategoryStoreSource', 'Categorize/CategoryStore.lua'),
                      Source('NativeBCIniWriterSource', '_IO/IniWriter.lua'),
                      Source('NativeBCIOSource', '_IO/_IO.lua')),
                  'test_smart_deposit.lua': (Source('NativeBCSmartDepositSource', 'Proximity/Proximity_SmartDeposit.lua'),),
                  'test_inventory_refresh.lua': (Source('NativeBCProximitySource', 'Proximity.lua'),
                                                 Source('NativeBCProximityPaneSource', 'Proximity/Proximity_ISInventoryPane.lua')),
                  'test_container_configuration_menus.lua': (Source('NativeBCPageCustomizerSource',
                                                                    'Customize/Customize_ISInventoryPage.lua'),)},
        'game_inputs': {test: ('native_action_root',) for test in ('test_smart_deposit.lua',
                                                                 'test_container_configuration_menus.lua', 'test_inventory_refresh.lua')},
    },
}


def describe():
    return {id: {**spec, 'tests': {test: [source._asdict() for source in sources]
                                  for test, sources in spec['tests'].items()}}
            for id, spec in INTEGRATIONS.items()}


def source_path(root, relative, optional=False):
    """Resolve one effective file; a version file overrides common independently."""
    path = next((layer / relative for layer in reversed(mod_layers(root)) if (layer / relative).is_file()), None)
    if path is None and not optional:
        raise ValueError('Missing upstream source: ' + str(root / relative))
    return path


def manual_source(spec, value, source):
    value = Path(value)
    argument = spec.get('argument')
    if not argument:
        return value / source.path
    if source.path == argument:
        return value
    relative = os.path.relpath(source.path, str(Path(argument).parent))
    return Path(os.path.normpath(value.parent / relative))


def bind_sources(lua, name, args):
    """Use the same per-test declarations for explicit inputs and locked files."""
    locked = getattr(args, 'integration_sources', {}).get(name, {})
    for spec in INTEGRATIONS.values():
        value = getattr(args, spec['option'], None)
        for source in spec['tests'].get(name, ()):
            if source.variable in locked:
                path = locked[source.variable]
            elif value is not None:
                path = manual_source(spec, value, source)
                if source.optional and not path.is_file():
                    continue
            else:
                continue
            if path is not None:
                lua.globals()[source.variable] = path.read_text(encoding='utf-8')


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
    args.integration_sources = {}
    for id in sorted(selected):
        if id not in locations:
            raise ValueError('Integration mod is absent from the locked pack: ' + id)
        spec = INTEGRATIONS[id]
        for test in sorted(checks.intersection(spec['tests'])):
            resolved = args.integration_sources.setdefault(test, {})
            for source in spec['tests'][test]:
                path = source_path(Path(locations[id]), str(Path(spec['root']) / source.path), source.optional)
                previous = getattr(args, spec['option'], None)
                if previous is not None:
                    manual = manual_source(spec, previous, source)
                    if (path is not None and manual.resolve() != path.resolve()
                            or path is None and manual.is_file()):
                        raise ValueError('--' + spec['option'].replace('_', '-') + ' differs from locked integration inputs')
                if source.variable in resolved and resolved[source.variable] != path:
                    raise ValueError('Conflicting locked input: ' + source.variable)
                resolved[source.variable] = path
            for option in spec.get('game_inputs', {}).get(test, ()):
                value = args.game.resolve() / GAME_SOURCES[option]
                previous = getattr(args, option, None)
                if previous and previous.resolve() != value:
                    raise ValueError('--' + option.replace('_', '-') + ' differs from --game')
                setattr(args, option, value)
        print('Upstream ' + id + ' -> ' + ', '.join(spec['owners']) + ' -> '
              + ', '.join(test for test in spec['tests'] if test in checks))
    requested.update(checks)
