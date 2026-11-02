"""Explicit subprocess calls that preserve an active preparation's isolation."""
from contextlib import contextmanager
from contextvars import ContextVar
import subprocess

_ACTIVE = ContextVar('native_preparation_process_scope', default=None)


@contextmanager
def inherit(descriptors=(), *, windows_job=None):
    """Keep POSIX leases in workers, or launch them inside the owned Windows Job."""
    token = _ACTIVE.set((tuple(descriptors), windows_job))
    try:
        yield
    finally:
        _ACTIVE.reset(token)


def _options(kwargs, descriptors):
    options = dict(kwargs)
    options['pass_fds'] = tuple(dict.fromkeys((*options.get('pass_fds', ()), *descriptors)))
    return options


def run(*args, **kwargs):
    scope = _ACTIVE.get()
    if scope is None:
        return subprocess.run(*args, **kwargs)
    descriptors, job = scope
    if job is not None:
        return job.run(*args, **kwargs)
    return subprocess.run(*args, **_options(kwargs, descriptors))


def check_output(*args, **kwargs):
    scope = _ACTIVE.get()
    if scope is None:
        return subprocess.check_output(*args, **kwargs)
    descriptors, job = scope
    if job is None:
        return subprocess.check_output(*args, **_options(kwargs, descriptors))
    if 'stdout' in kwargs or 'check' in kwargs:
        raise ValueError('stdout and check arguments are not allowed with check_output')
    # Match check_output's special case: input=None means empty input rather than
    # inheriting stdin. Text mode determines the corresponding empty value.
    if 'input' in kwargs and kwargs['input'] is None:
        kwargs['input'] = '' if any(kwargs.get(key) for key in ('text', 'encoding', 'errors', 'universal_newlines')) else b''
    return job.run(*args, stdout=subprocess.PIPE, check=True, **kwargs).stdout
