#!/usr/bin/env python3
"""Run Lua 5.1 behavioural checks with Lupa (a development dependency only)."""

import argparse
import json
import locale
import sys
import time
from pathlib import Path

try:
    from . import mod_integrations, lua_compatibility
except ImportError:
    import mod_integrations
    import lua_compatibility

ROOT = Path(__file__).resolve().parent.parent

# Only these nested scripts are standalone offline checks. Native scenario fixtures
# under tests/native_queue must never be discovered as runnable Lua unit tests.
NATIVE_TAG_TESTS = (
    "native_tags/check_reconnect.lua",
    "native_tags/check_sort_receipts.lua",
    "native_tags/check_barrier.lua",
    "native_tags/check_transfer_source.lua",
    "native_tags/check_placement.lua",
)

# An explicit request must not silently skip its required source checks. Other
# source-dependent tests retain their own optional-input SKIP/fallback behavior.
REQUIRED_INPUTS = {
    "test_action_queue_wring.lua": ("native_action_root", "--game or --native-action-root"),
    "test_device_action_target.lua": ("native_action_root", "--game or --native-action-root"),
    "test_action_queue_device_integration.lua": ("native_action_root", "--game or --native-action-root"),
    "test_action_queue_device_admission.lua": ("native_action_root", "--game or --native-action-root"),
    "test_action_queue_device_targets.lua": ("native_action_root", "--game or --native-action-root"),
    "test_action_queue_spatial_execution.lua": ("native_action_root", "--game or --native-action-root"),
    "test_action_queue_spatial_lease.lua": ("native_action_root", "--game or --native-action-root"),
    "test_action_queue_spatial_edit_lease.lua": ("native_action_root", "--game or --native-action-root"),
    "test_action_queue_spatial_edit_policy.lua": ("native_action_root", "--game or --native-action-root"),
    'test_action_queue_borrowing_composition.lua': (('native_action_root', 'p4_source'),
                                                  '--game and --p4-source (or a complete --pack-lock)'),
    "test_bulk_transfer_binding.lua": ("native_action_root", "--game or --native-action-root"),
    "test_action_queue_deferred_sources.lua": ("native_action_root", "--game or --native-action-root"),
    "test_action_queue_cart_transfer_binding.lua": (("native_action_root", "saucedcarts_source"),
                                                    "--game and --saucedcarts-source (or a complete --pack-lock)"),
    "test_warehouse_workload_affinity.lua": (("cleanui_inventory_pane", "native_action_root"),
                                           "--game and --cleanui-inventory-pane (or a complete --pack-lock)"),
    "test_action_queue_active_edit.lua": ("native_action_root", "--game or --native-action-root"),
    "test_bc_inventory_classes.lua": (("bc_filter_source", "cleanui_inventory_pane"),
                                      "--bc-filter-source and --cleanui-inventory-pane (or a complete --pack-lock)"),
    "test_kahlua_own_fields.lua": ("native_action_root", "--game or --native-action-root"),
    "test_wash_water_rule.lua": ("native_action_root", "--game or --native-action-root, and --wishlist-workshop-root"),
    "test_wash_makeup_sync.lua": ("native_action_root", "--game or --native-action-root"),
    "test_action_queue_makeup_sync.lua": ("native_action_root", "--game or --native-action-root"),
    "test_torch_refill.lua": ("native_action_root", "--game or --native-action-root"),
    "test_action_queue_fridge_compat.lua": ("fridge_source", "--fridge-source"),
    "test_quartermaster_craft_ui.lua": ("native_action_root", "--game or --native-action-root"),
    "test_quartermaster_deposit.lua": ("native_action_root", "--game or --native-action-root"),
    "native_tags/check_transfer_source.lua": ("native_action_root", "--game or --native-action-root"),
    "native_tags/check_placement.lua": ("native_action_root", "--game or --native-action-root"),
}
DEFAULT_NATIVE_ONLY = {
    "test_action_queue_spatial_execution.lua",
    "test_torch_refill.lua",
    "test_quartermaster_craft_ui.lua",
    "native_tags/check_transfer_source.lua",
    "native_tags/check_placement.lua",
}

# Completion receipts are separate from input availability. A supplied source
# cannot prove that its conditional assertions actually ran.
SOURCE_CHECKS = {'test_device_action_target.lua': ('source-contract',), 'test_action_queue_spatial_execution.lua': ('source-contract',),
 'test_action_queue_device_integration.lua': ('source-contract',),
 'test_action_queue_device_admission.lua': ('source-contract',),
 'test_action_queue_device_targets.lua': ('native-stale-device',),
 'test_action_queue_spatial_lease.lua': ('source-contract',),
 'test_action_queue_spatial_edit_lease.lua': ('source-contract',),
 'test_action_queue_spatial_edit_policy.lua': ('source-contract',),
 'test_action_queue.lua': ('source-contract',),
 'test_action_queue_borrowing_composition.lua': ('plain', 'singleton-guarded', 'merge-preserving', 'return-failure'),
 'test_bulk_transfer_binding.lua': ('source-contract',),
 'test_action_queue_deferred_sources.lua': ('source-contract',),
 'test_action_queue_cart_transfer_binding.lua': ('native-branch-contract',),
 'test_action_queue_active_edit.lua': ('source-contract',),
 'test_action_queue_animal_stops.lua': ('source-contract',),
 'test_action_queue_animals.lua': ('source-contract',),
 'test_action_queue_appliances.lua': ('source-contract',),
 'test_action_queue_batch_controller.lua': ('source-contract',),
 'test_action_queue_batches.lua': ('source-contract',),
 'test_action_queue_book_controls.lua': ('source-contract',),
 'test_action_queue_carts.lua': ('source-contract',),
 'test_action_queue_compat.lua': ('source-contract',),
 'test_action_queue_craft.lua': ('source-contract',),
 'test_action_queue_denial_details.lua': ('source-contract',),
 'test_action_queue_dismantle.lua': ('source-contract',),
 'test_action_queue_dispatch.lua': ('native-contracts', 'project-cook-callback'),
 'test_action_queue_edit_adapters.lua': ('source-contract',),
 'test_action_queue_edit_policy.lua': ('source-contract',),
 'test_action_queue_fire.lua': ('source-contract',),
 'test_action_queue_firearms.lua': ('source-contract',),
 'test_action_queue_fitness.lua': ('source-contract',),
 'test_action_queue_fridge_compat.lua': ('source-contract',),
 'test_action_queue_fuel.lua': ('source-contract',),
 'test_action_queue_generator_overlay.lua': ('source-contract',),
 'test_action_queue_generators.lua': ('source-contract',),
 'test_action_queue_grab_compat.lua': ('source-contract',),
 'test_action_queue_grooming.lua': ('source-contract',),
 'test_action_queue_grooming_active.lua': ('source-contract',),
 'test_action_queue_grooming_costs.lua': ('source-contract',),
 'test_action_queue_grooming_pending.lua': ('source-contract',),
 'test_action_queue_grooming_recovery.lua': ('source-contract',),
 'test_action_queue_health.lua': ('native-contracts',
                                  'health-cleanui-bandage',
                                  'minihealthplus-contracts'),
 'test_action_queue_hygiene.lua': ('source-contract',),
 'test_action_queue_item_edit_adapters.lua': ('native-contracts', 'p4-transfer-offset'),
 'test_action_queue_lifecycle.lua': ('native-lifecycle-toggle',),
 'test_action_queue_makeup.lua': ('source-contract',),
 'test_action_queue_makeup_sync.lua': ('source-contract',),
 'test_action_queue_manifest.lua': ('source-contract',),
 'test_action_queue_media.lua': ('source-contract',),
 'test_action_queue_wring.lua': ('source-contract',),
 'test_action_queue_native_continuations.lua': ('source-contract',),
 'test_action_queue_operations.lua': ('source-contract',),
 'test_action_queue_pickup_merge.lua': ('source-contract',),
 'test_action_queue_pickup_policy.lua': ('source-contract',),
 'test_action_queue_policy.lua': ('source-contract',),
 'test_action_queue_priority.lua': ('source-contract',),
 'test_action_queue_recovery.lua': ('source-contract',),
 'test_action_queue_recovery_adapters.lua': ('native-contracts',
                                             'constructor-call-trace',
                                             'custom-light-switch'),
 'test_action_queue_repair.lua': ('source-contract',),
 'test_action_queue_resource_comparisons.lua': ('source-contract',),
 'test_action_queue_return_decision_scope.lua': ('source-contract',),
 'test_action_queue_targets.lua': ('source-contract',),
 'test_action_queue_text_binding.lua': ('source-contract',),
 'test_action_queue_vegetation.lua': ('source-contract',),
 'test_action_queue_world.lua': ('source-contract',),
 'test_action_queue_wreck.lua': ('source-contract',),
 'test_alarm_clock.lua': ('source-contract',),
 'test_animal_info.lua': ('source-contract',),
 'test_bc_filter_compat.lua': ('source-contract',),
 'test_bc_inventory_classes.lua': ('source-contract',),
 'test_cart_impact_release.lua': ('installed-instant-drop',),
 'test_cart_spawns.lua': ('source-contract',),
 'test_clothing_inspection.lua': ('source-contract',),
 'test_clothing_tooltip.lua': ('source-contract',),
 'test_device_media_native_order.lua': ('source-contract',),
 'test_drink_fluid_boundary.lua': ('source-contract',),
 'test_empty_fluid_action.lua': ('source-contract',),
 'test_food_cart_compat.lua': ('source-contract',),
 'test_food_eatsmart_compat.lua': ('source-contract',),
 'test_food_goal_labels.lua': ('source-contract',),
 'test_functional_food_roles.lua': ('native-additive-flags',),
 'test_inventory_button_checks.lua': ('native-ui-element-setters',),
 'test_inventory_freshness.lua': ('better-containers-freshness-parity',),
 'test_inventory_refresh.lua': ('native-page',
                                'bc-proximity',
                                'cleanui-page',
                                'cleanui-vanilla-page',
                                'cleanui-bc-discovery',
                                'cleanui-bc-player',
                                'bc-pane-selection'),
 'test_inventory_tooltips.lua': ('source-contract',),
 'test_inventory_transfer_operations.lua': ('source-contract',),
 'test_item_action_capabilities.lua': ('native-eat-menu',),
 'test_item_bait_tags.lua': ('native-bait-sources',),
 'test_item_broken_tags.lua': ('native-broken-declarations',),
 'test_item_cooking_states.lua': ('native-cooking-state-declarations',),
 'test_item_cooking_tags.lua': ('native-cooking-declarations',),
 'test_item_disassembly_tags.lua': ('native-disassembly-declarations',),
 'test_item_fluid_tags.lua': ('native-fluid-declarations',),
 'test_item_laundry_tags.lua': ('native-laundry-sources',),
 'test_item_media_tags.lua': ('native-recorded-media',),
 'test_item_repair_tags.lua': ('native-repair-declarations',),
 'test_item_sharpening_tags.lua': ('native-sharpening-declarations',),
 'test_item_smelting_tags.lua': ('native-furnace-declarations',),
 'test_item_usage_tags.lua': ('native-usage-declarations',),
 'test_kahlua_own_fields.lua': ('source-contract',),
 'test_mpff_compat.lua': ('source-contract',),
 'test_quartermaster_deposit.lua': ('source-contract',),
 'test_quartermaster_preset_transactions.lua': ('source-contract',),
 'test_quartermaster_sync.lua': ('source-contract',),
 'test_queue_equipment_slots.lua': ('source-contract',),
 'test_saucedcarts_compat.lua': ('source-contract',),
 'test_set_stove_state.lua': ('source-contract',),
 'test_tv_videos.lua': ('source-contract',),
 'test_vehicle_doors.lua': ('source-contract',),
 'test_vehicle_glass.lua': ('upstream-vro-sources',),
 'test_warehouse_walking_lock.lua': ('source-contract',),
 'test_wash_makeup_sync.lua': ('source-contract',),
 'test_wash_water_rule.lua': ('source-contract',),
 'test_wishlist_client.lua': ('native-collapse-lifecycle',),
 'test_wishlist_sharing.lua': ('source-contract',)}


def discover_tests(root):
    """Top-level test_*.lua files are runnable without a second registration."""
    return sorted({path.name for path in (root / "tests").glob("test_*.lua") if path.is_file()}
                  | set(NATIVE_TAG_TESTS))


def grouped_tests(name, available):
    if name == "action-queue":
        shared_guards = {test for test in available
                         if test.startswith("test_wash_") or test in (
                             "test_empty_fluid_action.lua", "test_source_proof.lua", "test_kahlua_own_fields.lua")}
        return {test for test in available if test.startswith("test_action_queue")} | shared_guards
    return set()


def configure_game_sources(args):
    if not args.game:
        return
    game = args.game.resolve()
    if not (game / 'projectzomboid.jar').is_file():
        raise ValueError('--game must contain projectzomboid.jar: ' + str(game))
    for option, relative in mod_integrations.GAME_SOURCES.items():
        if getattr(args, option) is None:
            setattr(args, option, game / relative)


def configure_test_sources(lua, name, args):
    """Give every isolated runtime the same paths; read only this test's inputs."""
    inputs = mod_integrations.bind_sources(lua, name, args)
    lua.globals().ProjectRoot = str(ROOT)
    if name == 'test_action_queue_borrowing_composition.lua':
        toolkit = getattr(args, 'toolkit_source', None) or ROOT / 'PZSurvivorToolkit'
        layers = mod_integrations.mod_layers(toolkit.resolve())
        if not layers:
            raise ValueError('--toolkit-source requires a Build 42 mod root with common/version layers')
        lua.globals().ToolkitLuaRoots = lua.table_from([str(layer / 'media/lua') for layer in layers])
        inputs.append({'integration': 'PZSurvivorToolkit', 'variable': 'ToolkitLuaRoots',
                       'required': True, 'status': 'bound'})
    lua.globals().NativeQuartermasterLuaRoot = str(ROOT / "PZSurvivorToolkit/42/media/lua")
    for option, variable in (
        ("native_action_root", "NativeActionRoot"),
        ("wishlist_game_root", "NativeWishlistGameRoot"),
        ("wishlist_workshop_root", "NativeWishlistWorkshopRoot"),
        ("saucedcarts_source", "SaucedCartsSource"),
    ):
        value = getattr(args, option)
        if value is not None:
            lua.globals()[variable] = str(value)
    if name == "test_tag_filter_presets_menu.lua" and args.native_action_root:
        lua.globals().NativeTextBoxSource = (args.native_action_root / "client/ISUI/ISTextBox.lua").read_text(encoding="utf-8")
        lua.globals().NativeModalDialogSource = (args.native_action_root / "client/ISUI/ISModalDialog.lua").read_text(encoding="utf-8")
    if name in ("test_inventory_planting.lua", "test_inventory_indicators.lua") and args.native_action_root:
        lua.globals().NativePlantingLuaRoot = str(args.native_action_root)
    if name == "test_item_disassembly_tags.lua":
        media = args.native_action_root.parent if args.native_action_root else args.game / "media" if args.game else None
        if media:
            lua.globals().NativeDisassemblyScriptsRoot = str(media / "scripts/generated/recipes")
    if name == "test_inventory_tooltips.lua":
        if args.native_action_root:
            lua.globals().NativeTooltipLuaRoot = str(args.native_action_root)
        if args.vhs_tooltip_root:
            lua.globals().NativeVHSTooltipRoot = str(args.vhs_tooltip_root)
    if name == "test_clothing_tooltip.lua":
        if args.native_action_root:
            lua.globals().NativeTooltipLuaRoot = str(args.native_action_root)
        if args.bci_tooltip_root:
            lua.globals().NativeBCITooltipRoot = str(args.bci_tooltip_root)
    if name in ("test_quartermaster_craft_ui.lua", "native_tags/check_transfer_source.lua", "native_tags/check_placement.lua"):
        lua.globals().NativePZLuaRoot = str(args.native_action_root)
    if name == 'test_container_appearance_controls.lua' and args.native_action_root:
        lua.globals().NativeColorPickerSource = (args.native_action_root / 'client/ISUI/ISColorPickerHSB.lua').read_text(encoding='utf-8')
    if name in ('test_container_configuration_menus.lua', 'test_smart_deposit.lua', 'test_inventory_refresh.lua'):
        if args.native_action_root:
            lua.globals().NativeInventoryPageSource = (args.native_action_root / 'client/ISUI/ISInventoryPage.lua').read_text(encoding='utf-8')
    if name in ("test_highlighter.lua", "test_item_details.lua") and args.native_mod_options:
        lua.globals().NativeModOptionsSource = args.native_mod_options.read_text(encoding="utf-8")
    if name == "test_highlighter.lua" and args.native_action_root:
        lua.globals().NativeMainOptionsSource = (args.native_action_root / "client/OptionScreens/MainOptions.lua").read_text(encoding="utf-8")
    if name == "test_cart_spawns.lua" and args.wheelbarrow_source:
        lua.globals().WheelbarrowSource = str(args.wheelbarrow_source)
    if name == "test_clothing_repair_menu.lua" and args.native_inventory_context_menu:
        lua.globals().NativeGarmentSource = (args.native_inventory_context_menu.parent / "ISGarmentUI.lua").read_text(encoding="utf-8")
    if name == "test_clothing_inspection.lua" and args.native_inventory_context_menu and args.native_action_root:
        lua.globals().NativeInventoryContextMenuSource = args.native_inventory_context_menu.read_text(encoding="utf-8")
        lua.globals().NativeGarmentSource = (args.native_inventory_context_menu.parent / "ISGarmentUI.lua").read_text(encoding="utf-8")
        lua.globals().NativeTransferSource = (args.native_action_root / "client/TimedActions/ISInventoryTransferAction.lua").read_text(encoding="utf-8")
    if name == "test_tv_controls.lua":
        if args.native_radio_root:
            lua.globals().NativeMediaSource = (args.native_radio_root / "RadioCom/RadioWindowModules/RWMMedia.lua").read_text(encoding="utf-8")
            lua.globals().NativeDropBoxSource = (args.native_radio_root / "RadioCom/ISUIRadio/ISItemDropBox.lua").read_text(encoding="utf-8")
    if name == "test_vehicle_ground.lua":
        if args.native_uninstall:
            lua.globals().NativeUninstallSource = args.native_uninstall.read_text(encoding="utf-8")
        if args.native_vehicles:
            lua.globals().NativeVehicleItemsSource = args.native_vehicles.read_text(encoding="utf-8")
    if name == "test_action_queue_fridge_compat.lua" and args.fridge_source:
        lua.globals().FridgeSource = str(args.fridge_source.resolve())
    if name == "test_vva_compat.lua" and args.vva_source:
        lua.globals().NativeVVASourceRoot = str(args.vva_source.resolve())
    if name == "test_action_queue_dispatch.lua" and args.project_cook_picker:
        lua.globals().ProjectCookPickerSourcePath = str(args.project_cook_picker)
    if name in ("test_action_queue_labels.lua", "test_food_goal_labels.lua"):
        translations = {}
        for language in ("EN", "RU"):
            values = {}
            if args.native_action_root:
                for path in sorted((args.native_action_root / "shared/Translate" / language).glob("*.json")):
                    values.update(json.loads(path.read_text(encoding="utf-8")))
            values.update(json.loads((ROOT / "PZSurvivorToolkit/42/media/lua/shared/Translate" / language / "UI.json").read_text(encoding="utf-8")))
            translations[language] = values
        lua.globals().ActionQueueTranslations = lua.table_from(translations, recursive=True)
        if name == "test_food_goal_labels.lua":
            lua.globals().FoodGoalTranslations = lua.table_from(translations, recursive=True)
    if name == "test_quantity_transfers.lua" and args.oc_stick_source:
        lua.globals().OCItemStickSource = args.oc_stick_source.read_text(encoding="utf-8")
    if name == "test_inventory_filter.lua" and args.oc_display_source:
        lua.globals().OCDisplayOverrideSource = args.oc_display_source.read_text(encoding="utf-8")
    if name in ("test_action_queue_operations.lua", "test_quantity_transfers.lua", "test_item_retention.lua") and args.native_inventory_context_menu:
        lua.globals().NativeInventoryContextMenuSource = args.native_inventory_context_menu.read_text(encoding="utf-8")
        if name == "test_quantity_transfers.lua":
            lua.globals().NativeTextBoxSource = (args.native_inventory_context_menu.parent / "ISTextBox.lua").read_text(encoding="utf-8")
    if name in ("test_inventory_tags.lua", "test_inventory_filter.lua", "test_inventory_layout.lua", "test_inventory_interaction.lua") and args.native_inventory_pane:
        lua.globals().NativeInventoryPaneSource = args.native_inventory_pane.read_text(encoding="utf-8")
    return inputs


def test_variants(name, args):
    """Each flag selects an independent execution, never a reused Lua state."""
    flags = [None]
    if name == "native_tags/check_reconnect.lua":
        flags += ["BaselineTagReconnect", "RestartTagReconnect", "PlantingTagReconnect"]
    if name == "test_action_queue_fire.lua" and args.native_action_root and args.wishlist_workshop_root:
        flags += ["FireTestBCPreinstalled", "FireTestBCForeignPredecessor", "FireTestQMBeforeBC",
                  "FireTestQMPreloaded", "FireTestQMForeignPredecessor", "FireTestQMForeignGather"]
    if name == "test_action_queue_ownership.lua" and args.native_action_root:
        flags += ["OwnershipRadio", "OwnershipItems", "OwnershipMedia", "OwnershipRecovery",
                  "OwnershipGenerators", "OwnershipApproach", "OwnershipHealth", "OwnershipLifecycle", "OwnershipSettlement", "OwnershipGrooming", "OwnershipGroomingActive", "OwnershipGroomingPending", "OwnershipGroomingCosts", "OwnershipGroomingRecovery", "OwnershipMakeup", "OwnershipMakeupSync", "OwnershipTextBinding", "OwnershipAnimalStops"]
    return flags


class _Coverage:
    def __init__(self, name):
        self.expected = SOURCE_CHECKS.get(name, ())
        self.completed = {}
        self.errors = []

    def record(self, check, status, reason=None):
        if (check not in self.expected or check in self.completed
                or status not in ('passed', 'skipped')
                or reason is not None and not isinstance(reason, str)
                or status == 'skipped' and (not reason or not reason.strip())):
            error = f'Invalid or duplicate coverage receipt: {check!r}, {status!r}, {reason!r}'
            self.errors.append(error)
            raise ValueError(error)
        self.completed[check] = {'id': check, 'status': status, 'reason': reason}

    def results(self):
        return [self.completed.get(check, {'id': check, 'status': 'not-run',
                                          'reason': 'No completion receipt; source assertions did not finish.'})
                for check in self.expected]


def _run_variant(name, flag, args, LuaRuntime):
    started = time.perf_counter()
    inputs = []
    coverage = _Coverage(name)
    try:
        lua = LuaRuntime(unpack_returned_tuples=True)
        inputs = configure_test_sources(lua, name, args)
        if coverage.expected:
            lua.globals()['TestCoverage'] = coverage.record
        if flag:
            lua.globals()[flag] = True
    except Exception as error:
        result = {"test": name, "variant": flag or "default", "status": "failed",
                  "elapsed_seconds": round(time.perf_counter() - started, 6),
                  "error": str(error) or type(error).__name__, "skip_reasons": [],
                  "source_inputs": inputs, "checks": coverage.results()}
        if not args.keep_going:
            error._lua_runner_result = result
            raise
        return result
    try:
        if hasattr(lua, "eval"):
            to_string = lua.eval("tostring")
            def lua_print(*values):
                print("\t".join(to_string(value) for value in values))
            lua.globals()["print"] = lua_print
        lua.execute((ROOT / "tests" / name).read_text(encoding="utf-8"))
        if coverage.errors:
            raise ValueError('; '.join(coverage.errors))
        partial = [f"Missing {item['integration']} source: {item['variable']}"
                   for item in inputs if item['status'] == 'missing']
        checks = coverage.results()
        partial.extend(f"{item['id']}: {item['reason']}" for item in checks if item['status'] != 'passed')
        return {"test": name, "variant": flag or "default",
                "status": "partial" if partial else "passed",
                "elapsed_seconds": round(time.perf_counter() - started, 6),
                "error": None, "partial_reasons": partial,
                "source_inputs": inputs, "checks": checks}
    except Exception as error:
        result = {"test": name, "variant": flag or "default", "status": "failed",
                  "elapsed_seconds": round(time.perf_counter() - started, 6),
                  "error": str(error) or type(error).__name__, "skip_reasons": [],
                  "source_inputs": inputs, "checks": coverage.results()}
        if not args.keep_going:
            error._lua_runner_result = result
            raise
        return result


def _counts(results):
    return {status: sum(result['status'] == status for result in results)
            for status in ('passed', 'partial', 'failed', 'skipped')}


def _write_report(path, results, require_complete=False):
    counts = _counts(results)
    report = {"status": "failed" if counts["failed"] else "partial" if counts["partial"] or counts["skipped"] else "passed",
              "counts": {**counts, "total": len(results)}, "results": results,
              "require_complete": require_complete,
              "scope": "Offline Lua assertions; this report does not establish live gameplay or exhaustive branch coverage.",
              "limitations": (["Some source checks did not run or did not report completion; partial results are not full integration coverage."]
                              if counts["partial"] else []) +
                             (["Skipped results indicate optional source checks did not run; this report does not claim full source coverage."]
                              if counts["skipped"] else [])}
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test", action="append", default=[], metavar="NAME",
                        help="run only this test relative to tests/ (optional .lua suffix); repeatable")
    parser.add_argument("--group", action="append", default=[], choices=("action-queue",),
                        help="run a named related test group; checks still require --game and selected mod source inputs where declared")
    parser.add_argument("--list", action="store_true", help="list available test names without running checks")
    parser.add_argument("--keep-going", action="store_true", help="continue after an offline Lua test or variant fails")
    parser.add_argument("--report", type=Path, metavar="PATH", help="write per-test JSON results to PATH")
    parser.add_argument('--require-complete', action='store_true',
                        help='fail on partial/skipped coverage; automatic with --integration or --pack-lock')
    parser.add_argument('--integration', action='append', default=[], choices=mod_integrations.INTEGRATIONS,
                        help='run this integration against its locked upstream sources; repeatable')
    parser.add_argument('--list-integrations', action='store_true', help='show upstream inputs, Toolkit owners and focused checks')
    parser.add_argument('--pack-lock', type=Path, help='validated selected-pack lock supplying integration source paths')
    parser.add_argument('--game', type=Path,
                        help='directory containing projectzomboid.jar; supplies native Lua paths, and must match --pack-lock when used')
    parser.add_argument('--p4-source', type=Path,
                        help='effective P4 Tidy Up Meister content root containing media/ for borrowing composition checks')
    parser.add_argument('--toolkit-source', type=Path,
                        help='candidate Toolkit mod root for borrowing composition checks; defaults to this checkout and must match --pack-lock')
    parser.add_argument('--jdk', type=Path, help='JDK for the installed-Kahlua compatibility check')
    parser.add_argument('--check-lua', type=Path, action='append', default=[], metavar='SOURCE',
                        help='compile runtime Lua file/directory with installed Kahlua and reject absent standard globals; repeatable, requires --game and --jdk; alone runs no behavioural tests')
    parser.add_argument('--lua-report', type=Path, help='write the --check-lua compatibility report, including rejected sources')
    parser.add_argument("--native-mod-options", type=Path,
                        help="test against an extracted vanilla PZAPI/ModOptions.lua")
    parser.add_argument("--cleanui-inventory-pane", type=Path, help="test against CleanUI ISInventoryPane.lua")
    parser.add_argument("--native-inventory-pane", type=Path, help="test against vanilla ISInventoryPane.lua")
    parser.add_argument("--tv-source", type=Path, help="test VHS controls against TVRadio Reinvented RWMMergedTV.lua")
    parser.add_argument("--native-radio-root", type=Path, help="vanilla media/lua/client directory for RWMMedia and ISItemDropBox checks")
    parser.add_argument("--navigator-source", type=Path, help="NavigatorRadio source directory for upstream render/input checks")
    parser.add_argument("--native-uninstall", type=Path, help="vanilla ISUninstallVehiclePart.lua for ground-placement checks")
    parser.add_argument("--native-vehicles", type=Path, help="vanilla Vehicles.lua for mechanics item-collection checks")
    parser.add_argument("--medicine-framework-source", type=Path, help="installed MF_ISMoodle.lua")
    parser.add_argument("--mpff-source", type=Path, help="MP Fast Forward media/lua directory")
    parser.add_argument("--fridge-source", type=Path, help="Nick's Turn Off Fridges active media/lua directory")
    parser.add_argument("--vva-source", type=Path, help="Vanilla Vehicles Animated effective content root containing media/")
    parser.add_argument("--vro-source", type=Path, help="Vehicle Repair Overhaul effective content root containing media/")
    parser.add_argument("--bc-filter-source", type=Path, help="Better Containers CategoryFilters.lua")
    parser.add_argument("--oc-stick-source", type=Path, help="organizedCategories_itemStick.lua for Quantity transfer protection checks")
    parser.add_argument("--oc-display-source", type=Path, help="organizedCategories_displayOverride.lua for inventory stack splitting checks")
    parser.add_argument("--vhs-tooltip-root", type=Path, help="active Show VHS Skills in Tooltip media/lua/client directory")
    parser.add_argument("--bci-tooltip-root", type=Path, help="active Better Clothing Info media/lua/client directory")
    parser.add_argument("--native-inventory-context-menu", type=Path, help="vanilla inventory callbacks and sibling garment inspection UI")
    parser.add_argument("--native-action-root", type=Path, help="vanilla media/lua for queue/base/read contracts")
    parser.add_argument("--wishlist-game-root", type=Path, help="game Java directory for native wishlist menu callbacks")
    parser.add_argument("--wishlist-workshop-root", type=Path, help="Workshop content/108600 for wishlist UI source checks")
    parser.add_argument("--project-cook-picker", type=Path, help="Project Cook ItemPicker.lua for queued stove controls")
    parser.add_argument("--saucedcarts-source", type=Path, help="SaucedCarts shared module directory for server hook checks")
    parser.add_argument("--wheelbarrow-source", type=Path, help="SaucedWheelbarrow registration init.lua for spawn checks")
    args = parser.parse_args()
    args.require_complete = bool(args.require_complete or args.integration or args.pack_lock)
    available = discover_tests(ROOT)
    requested = {name if name.endswith(".lua") else name + ".lua" for name in args.test}
    for group in args.group:
        requested.update(grouped_tests(group, available))

    def validate_selection():
        unknown = requested - set(available)
        if unknown:
            parser.error("unknown tests: " + ", ".join(sorted(unknown)) + "; see --list")

    validate_selection()
    if args.list:
        print("\n".join(sorted(requested) if args.group else available))
        return
    if args.list_integrations:
        print(json.dumps(mod_integrations.describe(), indent=2))
        return
    if args.lua_report and not args.check_lua:
        parser.error('--lua-report requires --check-lua')
    if args.check_lua:
        if not args.game or not args.jdk:
            parser.error('--check-lua requires --game and --jdk')
        sources = []
        for path in args.check_lua:
            if path.is_dir():
                found = sorted(path.rglob('*.lua'))
                if not found:
                    parser.error('No runtime Lua sources in: ' + str(path))
                sources.extend(found)
            else:
                sources.append(path)
        try:
            checked = lua_compatibility.check_sources(sources, game=args.game, jdk=args.jdk, output=args.lua_report)
        except (OSError, ValueError) as error:
            parser.error(str(error))
        print('Installed-Kahlua compatibility passed for ' + str(len(checked['sources'])) + ' runtime Lua files.', flush=True)
        if not args.test and not args.group and not args.integration:
            return
    if args.integration or args.pack_lock:
        try:
            mod_integrations.configure(args, ROOT, requested)
        except (OSError, ValueError, KeyError) as error:
            parser.error(str(error))
        validate_selection()
    try:
        configure_game_sources(args)
    except ValueError as error:
        parser.error(str(error))
    for name in sorted(requested):
        if name in REQUIRED_INPUTS:
            option, help_text = REQUIRED_INPUTS[name]
            options = (option,) if isinstance(option, str) else option
            if any(not mod_integrations.has_required_input(name, item, args) for item in options):
                parser.error(name.removesuffix(".lua") + " requires " + help_text)
    if args.require_complete:
        missing = []
        for name in sorted(requested or available):
            for identifier, spec in mod_integrations.INTEGRATIONS.items():
                if name in spec['tests'] and not mod_integrations.has_required_input(name, spec['option'], args):
                    missing.append(f"{name}: {identifier} requires --{spec['option'].replace('_', '-')} or --pack-lock")
        if missing:
            parser.error('Complete source coverage requires inputs before execution:\n' + '\n'.join(missing))

    # Lua 5.1 character classes inspect bytes; host UTF-8 locales can misclassify them.
    locale.setlocale(locale.LC_CTYPE, "C")
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError as error:
        raise SystemExit("Set up the project Python with: uv sync --locked; then run uv run --locked python tools/run_tests.py") from error
    if args.require_complete:
        # Use the normal binder, including native paths, before any selected
        # assertions run. Presence of a manual option alone is not a valid file.
        for name in sorted(requested or available):
            try:
                configure_test_sources(LuaRuntime(unpack_returned_tuples=True), name, args)
            except (OSError, ValueError, KeyError) as error:
                parser.error(f'{name}: source preparation failed: {error}')
    if not requested:
        syntax = LuaRuntime(unpack_returned_tuples=True)
        for path in sorted((ROOT / "PZSurvivorToolkit").rglob("*.lua")):
            syntax.execute("assert(loadstring(...))", path.read_text(encoding="utf-8"))
        print("All mod files compile as Lua 5.1.", flush=True)
    results = []
    for name in available:
        if requested and name not in requested:
            continue
        if name in DEFAULT_NATIVE_ONLY and not args.native_action_root:
            results.append({"test": name, "variant": "default", "status": "skipped",
                            "elapsed_seconds": 0, "error": None,
                            "skip_reasons": ["optional native source checks unavailable; pass --native-action-root"]})
            print(f'SKIPPED {name}: requires --game or --native-action-root', file=sys.stderr)
            continue
        for flag in test_variants(name, args):
            try:
                result = _run_variant(name, flag, args, LuaRuntime)
            except Exception as error:
                result = getattr(error, "_lua_runner_result", None)
                if result is not None and args.report:
                    _write_report(args.report, results + [result], args.require_complete)
                raise
            results.append(result)
            if result["status"] == "failed":
                print(f"FAILED {result['test']} [{result['variant']}]: {result['error']}", file=sys.stderr)
            elif result['status'] == 'partial':
                print(f"PARTIAL {result['test']} [{result['variant']}]: "
                      + '; '.join(result['partial_reasons']), file=sys.stderr)
            if result["status"] == "failed" and not args.keep_going:
                if args.report:
                    _write_report(args.report, results, args.require_complete)
                raise SystemExit(1)
    if args.report:
        _write_report(args.report, results, args.require_complete)
    counts = _counts(results)
    print('Lua results: ' + ', '.join(f'{count} {status}' for status, count in counts.items()), file=sys.stderr)
    incomplete = counts['partial'] or counts['skipped']
    if args.require_complete and incomplete:
        print('Complete coverage required; partial/skipped results do not pass this run.', file=sys.stderr)
    if counts['failed'] or args.require_complete and incomplete:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
