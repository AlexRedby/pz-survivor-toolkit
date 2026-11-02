"""Shared admission constraints and precise diagnostics for recovery banks."""


def validate(selection, *, suite, cases, mods, grooming=False):
    errors = []

    def require(field, actual, expected, accepted):
        if not accepted:
            errors.append(f'{field}: actual={actual!r}; expected={expected}')

    require('cases', selection.get('cases'), repr(list(cases)) + ' (ordered)',
            selection.get('cases') == list(cases))
    require('kind', selection.get('kind'), "'sp' or 'mp'", selection.get('kind') in ('sp', 'mp'))
    require('mode', selection.get('mode'), "'native' or 'toolkit'",
            selection.get('mode') in ('native', 'toolkit'))
    require('languages', selection.get('languages'), "['EN']", selection.get('languages') == ['EN'])
    require('clients', selection.get('clients'), '1 (int, not bool)',
            type(selection.get('clients')) is int and selection['clients'] == 1)
    require('mods', selection.get('mods'), repr(mods) + ' (ordered full selected pack)',
            selection.get('mods') == mods)
    options = selection.get('options', {})
    require('options', options, 'an object', isinstance(options, dict))
    if isinstance(options, dict):
        require('options.world_template', options.get('world_template'), 'unset or falsey (fresh world)',
                not options.get('world_template'))
        if selection.get('kind') == 'mp':
            require('options.mp_host', options.get('mp_host'), 'True (menu Host)',
                    options.get('mp_host') is True)
        if grooming:
            require('options.grooming_recovery', options.get('grooming_recovery'), 'True (explicit opt-in)',
                    options.get('grooming_recovery') is True)
    if errors:
        raise ValueError(suite + ' selection rejected: ' + '; '.join(errors))
