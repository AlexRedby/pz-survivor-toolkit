# Native inventory tooltip scenes

The shared `inventory-tooltips/scenes` suite stages this EN/SP B42.21 helper in
a disposable profile using the unchanged full selected mod set.

```sh
python3 tools/check_action_queue.py run /tmp/inventory-tooltips-fresh \
  --suite inventory-tooltips --cases scenes --kind sp --mode toolkit \
  --language EN --mods selected --game "$PZ_GAME" --jdk "$PZ_JDK" \
  --workshop "$PZ_WORKSHOP"
```

Four screenshots cover a native known-growing carrot seed with Large tooltip
font at the screen edge, a real recorded VHS at Small font, the same VHS at
Large font and the screen edge, and native clothing with Better Clothing Info's
comparison against another equipped native garment. The helper chooses VHS
metadata through the selected upstream `SVSIT_logic` public API, preferring a
tape with both skill and recipe entries when one exists. Native
`setRecordedMediaData` assigns the actual recording; display names and public
media tables are unchanged.

Forwarding observers track `ObjectTooltip:setMeasureOnly`, each extension's
append call and actual native background dimensions within one rendered frame.
Each extension must run once in measurement and once in drawing, report equal
dimensions in both passes, and fit inside the native window, background and
screen. Scenes wait for native global/player fade alpha to reach zero; each
screenshot rechecks that the loading fade is gone. A separate actual inventory
pane creates its VHS tooltip through controller selection. Opening a real
player context menu must make the pane's normal `updateTooltip` hide and remove
that tooltip, with zero additional forwarded renders while the menu stays open.
Menu-owned item tooltips retain their native behavior.
Disabling growing information must retain the native seed tooltip. Clothing
must still use the selected BCI owner and its real comparison renderer twice,
with the expected native worn item and no Toolkit extension.

Only successful completion permits the helper to quit. A failed fixture emits
its failure marker and leaves process cleanup to the isolated runner. The
shared log audit and source snapshot guards still apply. Screenshot presence
and layout receipts require manual visual review for text, clipping and style.
These programmatic windows do not cover physical input or Host mode.
