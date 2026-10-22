"""Exact cart-only root aliases; no prefix, substring or guessed gait matching.

Raw names remain in parsed evidence. Only gait comparisons use this table;
unknown/misspelled names retain their identity and cannot satisfy a stock gait.
"""
ALIASES = {
    'Toolkit_CartPivot_Idle': 'Bob_Idle',
    'Toolkit_CartPivot_Walk': 'Bob_Walk',
    'Toolkit_CartPivot_Run': 'Bob_Run',
    'Toolkit_CartPivot_Sprint': 'Bob_Sprint',
    'Toolkit_CartPivot_Backward': 'Bob_WalkBwdNoAim1Hand',
    'Toolkit_CartPivot_StrafeLeft': 'Bob_StrafeNoAim_Left',
    'Toolkit_CartPivot_StrafeRight': 'Bob_StrafeNoAim_Right',
    'Toolkit_CartPivot_WoodLeft': 'Bob_StrafeNoAim_Left',
    'Toolkit_CartPivot_WoodRight': 'Bob_StrafeNoAim_Right',
    'Toolkit_CartPivot_StopRun': 'Bob_RunToStop2H_Heavy',
    'Toolkit_CartPivot_StopSprint': 'Bob_SprintToStop2h_Heavy',
    'Toolkit_WoodCartPivot_Left': 'Bob_StrafeNoAim_Left',
    'Toolkit_WoodCartPivot_Right': 'Bob_StrafeNoAim_Right',
}


def native_clip(name):
    return ALIASES.get(name, name)


def clip_aliases(name):
    native = native_clip(name)
    return tuple(sorted({native, *(alias for alias, stock in ALIASES.items() if stock == native)}))
