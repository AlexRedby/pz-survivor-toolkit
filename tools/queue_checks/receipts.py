"""Strict JSON envelopes for native evidence; adapters own event order and verdicts."""
import json
import math


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate receipt JSON key ' + key)
        result[key] = value
    return result


def _nonfinite(value):
    raise ValueError('Nonfinite receipt number ' + value)


def _finite_float(value):
    number = float(value)
    if not math.isfinite(number):
        _nonfinite(value)
    return number


def decode_object(payload):
    """Reject ambiguous keys and nonfinite numbers, including exponent overflow."""
    value = json.loads(payload, object_pairs_hook=_unique, parse_constant=_nonfinite,
                       parse_float=_finite_float)
    if type(value) is not dict:
        raise ValueError('Receipt must be an object')
    return value


def records(text, marker, event):
    """Read one event's objects without rewriting the log or its JSON contents.

    A native timestamp/logger prefix may precede the marker. Keep order and
    duplicate events intact: only the adapter can decide their allowed lifecycle.
    Unrelated events need not carry JSON and must not be decoded here.
    """
    prefix = marker + event + ' '
    rows = []
    for line in text.splitlines():
        offset = line.find(prefix)
        if offset >= 0:
            rows.append(decode_object(line[offset + len(prefix):]))
    return rows
