"""Read the engine's mod-layer version without loading or initializing game classes."""
from pathlib import Path
import struct
from zipfile import ZipFile, BadZipFile


class _Reader:
    def __init__(self, data):
        self.data, self.offset = data, 0

    def take(self, size):
        if size < 0 or self.offset + size > len(self.data):
            raise ValueError('Truncated game version class')
        value = self.data[self.offset:self.offset + size]
        self.offset += size
        return value

    def integer(self, size):
        return int.from_bytes(self.take(size), 'big')


def _class(data):
    """Only the constant pool and method Code attributes needed by the version probe."""
    reader = _Reader(data)
    if reader.take(4) != b'\xca\xfe\xba\xbe':
        raise ValueError('Invalid game version class')
    reader.take(4)
    pool = [None] * reader.integer(2)
    index = 1
    while index < len(pool):
        tag = reader.integer(1)
        if tag == 1:
            # Preserve modified-UTF8 bytes; all identifiers used here are ASCII.
            value = reader.take(reader.integer(2))
        elif tag in (3, 4):
            value = reader.take(4)
        elif tag in (5, 6):
            value = reader.take(8)
        elif tag in (7, 8, 16, 19, 20):
            value = reader.integer(2)
        elif tag in (9, 10, 11, 12, 17, 18):
            value = (reader.integer(2), reader.integer(2))
        elif tag == 15:
            value = (reader.integer(1), reader.integer(2))
        else:
            raise ValueError('Unknown game version constant-pool tag')
        pool[index] = (tag, value)
        index += 2 if tag in (5, 6) else 1

    def constant(index, tag):
        if not 0 < index < len(pool) or pool[index] is None or pool[index][0] != tag:
            raise ValueError('Invalid game version constant-pool reference')
        return pool[index][1]

    def member(index, tag):
        owner, signature = constant(index, tag)
        name, descriptor = constant(signature, 12)
        return (constant(constant(owner, 7), 1), constant(name, 1), constant(descriptor, 1))

    reader.take(6)
    reader.take(reader.integer(2) * 2)
    methods = {}
    for method in (False, True):
        for _ in range(reader.integer(2)):
            reader.take(2)
            name, descriptor = constant(reader.integer(2), 1), constant(reader.integer(2), 1)
            for _ in range(reader.integer(2)):
                attribute = constant(reader.integer(2), 1)
                payload = reader.take(reader.integer(4))
                if method and attribute == b'Code':
                    code = _Reader(payload)
                    code.take(4)
                    key = (name, descriptor)
                    if key in methods:
                        raise ValueError('Ambiguous game version method')
                    methods[key] = code.take(code.integer(4))
    return constant, member, methods


def _version(data):
    constant, member, methods = _class(data)
    code = _Reader(methods[(b'<clinit>', b'()V')])
    if code.integer(1) != 0xbb or constant(constant(code.integer(2), 7), 1) != b'zombie/core/GameVersion' or code.integer(1) != 0x59:
        raise ValueError('Unsupported Core version initializer')

    def number():
        opcode = code.integer(1)
        if 0x02 <= opcode <= 0x08:
            return opcode - 0x03
        if opcode in (0x10, 0x11):
            return int.from_bytes(code.take(1 if opcode == 0x10 else 2), 'big', signed=True)
        if opcode in (0x12, 0x13):
            return struct.unpack('>i', constant(code.integer(1 if opcode == 0x12 else 2), 3))[0]
        raise ValueError('Unsupported Core version number')

    major, minor = number(), number()
    opcode = code.integer(1)
    if opcode not in (0x12, 0x13):
        raise ValueError('Unsupported Core version suffix')
    constant(constant(code.integer(1 if opcode == 0x12 else 2), 8), 1)
    if code.integer(1) != 0xb7 or member(code.integer(2), 10) != (b'zombie/core/GameVersion', b'<init>', b'(IILjava/lang/String;)V'):
        raise ValueError('Unsupported Core version constructor')
    if code.integer(1) != 0xb3:
        raise ValueError('Missing Core version assignment')
    field = code.integer(2)
    if member(field, 9) != (b'zombie/core/Core', b'gameVersion', b'Lzombie/core/GameVersion;'):
        raise ValueError('Unexpected Core version field')
    getter = methods[(b'getGameVersion', b'()Lzombie/core/GameVersion;')]
    if getter != b'\xb2' + field.to_bytes(2, 'big') + b'\xb0' or b'\xb3' + field.to_bytes(2, 'big') in code.data[code.offset:]:
        raise ValueError('Ambiguous Core game version')
    # The layer selector/minimum were inspected in these SDKs. A literal
    # future version alone cannot establish unchanged selection semantics.
    if (major, minor) not in ((42, 21), (42, 22)):
        raise ValueError('Unreviewed engine mod-layer version; inspect the game selector first')
    return major, minor


def game_version(game):
    """Use Core's literal GameVersion, never a path name or a running game JVM."""
    if game is None:
        raise ValueError('Layered mod sources require --game with projectzomboid.jar')
    jar = Path(game) / 'projectzomboid.jar'
    try:
        with ZipFile(jar) as archive:
            name = 'zombie/core/Core.class'
            if archive.namelist().count(name) != 1:
                raise ValueError('Missing or ambiguous Core.class')
            return _version(archive.read(name))
    except (OSError, BadZipFile, KeyError, ValueError, IndexError, struct.error) as error:
        raise ValueError('Cannot determine engine mod-layer version from ' + str(jar) + ': ' + str(error)) from error
