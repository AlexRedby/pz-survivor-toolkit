"""Independent acceptance of local placement and ordinary replicated arrival."""
import math


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def validate(proof, target, mode):
    """A receipt proves one past transition, not the actor's current position."""
    def require(condition, detail):
        if not condition:
            raise ValueError('Invalid fixture placement proof: ' + detail)

    require(mode in ('local', 'replica'), 'unknown role')
    require(isinstance(target, dict) and set(target) == {'x', 'y', 'z'}
            and all(type(v) is int and abs(v) < 1000000 for v in target.values()), 'target')
    require(isinstance(proof, dict) and set(proof) == {
        'mode', 'target', 'actual', 'teleports', 'stableMs', 'quietMs', 'elapsedMs'}, 'fields')
    require(proof['mode'] == mode and isinstance(proof['target'], dict)
            and all(type(v) is int for v in proof['target'].values())
            and proof['target'] == target, 'role/target differs')
    require(type(proof['teleports']) is int and proof['teleports'] == (1 if mode == 'local' else 0), 'teleports')
    stable, quiet, elapsed = (proof[key] for key in ('stableMs', 'quietMs', 'elapsedMs'))
    require(all(_number(v) for v in (stable, quiet, elapsed)), 'invalid timing')
    require(stable >= 500 and elapsed >= stable + quiet and elapsed < 30000
            and (quiet >= 500 if mode == 'local' else quiet == 0), 'unsettled/deadline')
    actual = proof['actual']
    fields = {'x', 'y', 'z', 'square', 'currentSquare'}
    if mode == 'local':
        fields |= {'queued', 'timed', 'moving', 'hasPath', 'deferredX', 'deferredY'}
    require(isinstance(actual, dict) and set(actual) == fields, 'actual fields')
    require(all(_number(actual[k]) for k in ('x', 'y', 'z')), 'actual coordinates')
    require(math.floor(actual['x']) == target['x'] and math.floor(actual['y']) == target['y']
            and abs(actual['z'] - target['z']) <= .01, 'actual coordinates differ')
    for key in ('square', 'currentSquare'):
        square = actual[key]
        require(isinstance(square, dict) and set(square) == {'x', 'y', 'z'}
                and all(type(v) is int for v in square.values()) and square == target, key + ' differs')
    if mode == 'local':
        require(type(actual['queued']) is int and actual['queued'] == 0
                and all(actual[k] is False for k in ('timed', 'moving', 'hasPath'))
                and all(_number(actual[k]) and actual[k] == 0 for k in ('deferredX', 'deferredY')), 'native work/motion remains')
    return proof
