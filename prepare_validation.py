"""Extract private validation fixtures from the user's own installed game."""
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
GAME = Path(r'D:\Steam\steamapps\common\Kingdom Rush Frontiers')
FILES = ['all/systems.lua', 'all/storage.lua', 'all-desktop/game_gui.lua',
         'all/storage_io_generic.lua', 'lib/klove/simulation.lua',
         'lib/klua/persistence.lua', 'lib/klua/table.lua']

def read_uint(data, pos):
    value = shift = 0
    while True:
        byte = data[pos]; pos += 1
        value |= (byte & 127) << shift
        if byte < 128: return value, pos
        shift += 7

def uint(value):
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128); value >>= 7
    result.append(value)
    return bytes(result)

def extract_probe(data, line):
    if data[:4] != b'\x1bLJ\x01': raise ValueError('Unsupported LuaJIT version')
    flags, pos = read_uint(data, 4)
    if flags != 0: raise ValueError('Expected unstripped little-endian bytecode')
    size, pos = read_uint(data, pos); pos += size
    header = data[:pos]
    while True:
        size, pos = read_uint(data, pos)
        if size == 0: break
        body = data[pos:pos+size]; pos += size
        at = 4
        for _ in range(3): _, at = read_uint(body, at)
        debug, at = read_uint(body, at)
        if debug:
            source_line, at = read_uint(body, at)
            if source_line == line: return header + uint(len(body)) + body + b'\0'
    raise ValueError(f'Original function at line {line} missing; game version differs')

def prepare():
    inspection = ROOT/'inspection'; inspection.mkdir(exist_ok=True)
    fixture_dir = ROOT/'tests/ipc'; fixture_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(GAME/'Kingdom Rush Frontiers.exe') as archive:
        for name in FILES:
            (inspection/name.replace('/', '_')).write_bytes(archive.read(name))
    for filename, lines in {'all_storage.lua': [187, 242],
                            'all-desktop_game_gui.lua': [1878, 1902]}.items():
        data = (inspection/filename).read_bytes()
        for line in lines:
            (inspection/f'{filename[:-4]}-{line}.luac').write_bytes(extract_probe(data, line))
    backup = GAME/'codex-frontiers-trainer-backup-20261010/save-before-install/slot_1.lua'
    current = Path.home()/'AppData/Roaming/kingdom_rush_frontiers/slot_1.lua'
    source = backup if backup.exists() else current
    if not source.exists(): raise FileNotFoundError('Create game save slot 1 before running storage validation')
    shutil.copy2(source, fixture_dir/'sample_slot.lua')
    print('Local game fixtures prepared in ignored inspection/ and tests/ipc/ directories')

if __name__ == '__main__': prepare()
