"""Small class-file fixtures for nonexecuting engine-version source selection."""
import struct
from zipfile import ZipFile


def core_class(major=42, minor=21, *, getter=None, initializer=None):
    pool = []

    def add(tag, payload):
        pool.append(bytes([tag]) + payload)
        return len(pool)

    def utf8(value):
        value = value.encode('utf-8')
        return add(1, struct.pack('>H', len(value)) + value)

    def pair(tag, left, right):
        return add(tag, struct.pack('>HH', left, right))

    core = add(7, struct.pack('>H', utf8('zombie/core/Core')))
    version = add(7, struct.pack('>H', utf8('zombie/core/GameVersion')))
    field_name, field_type = utf8('gameVersion'), utf8('Lzombie/core/GameVersion;')
    field = pair(9, core, pair(12, field_name, field_type))
    constructor = pair(10, version, pair(12, utf8('<init>'), utf8('(IILjava/lang/String;)V')))
    suffix = add(8, struct.pack('>H', utf8('')))
    code_name = utf8('Code')
    getter_name, getter_type = utf8('getGameVersion'), utf8('()Lzombie/core/GameVersion;')
    init_name, init_type = utf8('<clinit>'), utf8('()V')
    prefix = (b'\xbb' + struct.pack('>H', version) + b'\x59\x10' + bytes([major])
              + b'\x10' + bytes([minor]) + b'\x12' + bytes([suffix])
              + b'\xb7' + struct.pack('>H', constructor) + b'\xb3' + struct.pack('>H', field))

    def method(name, descriptor, code):
        payload = struct.pack('>HHI', 5, 1, len(code)) + code + b'\x00\x00\x00\x00'
        return struct.pack('>HHHHHI', 9, name, descriptor, 1, code_name, len(payload)) + payload

    methods = method(getter_name, getter_type, b'\xb2' + struct.pack('>H', field) + b'\xb0' if getter is None else getter)
    methods += method(init_name, init_type, prefix + b'\xb1' if initializer is None else initializer)
    return (b'\xca\xfe\xba\xbe\x00\x00\x00\x45' + struct.pack('>H', len(pool) + 1)
            + b''.join(pool) + struct.pack('>HHHHH', 1, core, 0, 0, 1)
            + struct.pack('>HHHH', 0x0019, field_name, field_type, 0)
            + struct.pack('>H', 2) + methods + b'\x00\x00')


def write_game_jar(game, minor=21, **options):
    game.mkdir(parents=True, exist_ok=True)
    jar = game / 'projectzomboid.jar'
    with ZipFile(jar, 'w') as archive:
        archive.writestr('zombie/core/Core.class', core_class(minor=minor, **options))
    return jar
