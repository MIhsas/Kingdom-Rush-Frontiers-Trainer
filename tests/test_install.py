import importlib.util
import tempfile
import unittest
import zipfile
from unittest.mock import patch
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class ArchiveTests(unittest.TestCase):
    def test_module_exists(self):
        self.assertTrue((ROOT / 'install.py').exists(), 'Backup and archive installer is missing')

    def test_preserves_native_prefix_and_other_members(self):
        if not (ROOT / 'install.py').exists(): self.fail('Installer is missing')
        spec=importlib.util.spec_from_file_location('installer', ROOT / 'install.py')
        m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
        with tempfile.TemporaryDirectory() as d:
            source=Path(d)/'game.exe'; target=Path(d)/'staged.exe'
            prefix=b'MZ-native-prefix'*20
            source.write_bytes(prefix)
            with zipfile.ZipFile(source,'a') as z:
                z.writestr('main.lua',b'return "original"')
                z.writestr('asset.bin',b'keep me exactly')
            m.patch_archive(source,target,ROOT)
            self.assertEqual(target.read_bytes()[:len(prefix)],prefix)
            with zipfile.ZipFile(target) as z:
                self.assertEqual(z.read('asset.bin'),b'keep me exactly')
                self.assertEqual(z.read('codex_original_main.luac'),b'return "original"')
                self.assertIsNone(z.testzip())
                self.assertEqual(len(z.namelist()),len(set(z.namelist())))
            with self.assertRaises(ValueError):
                m.patch_archive(target,Path(d)/'again.exe',ROOT)

    def test_install_finishes_report_after_replacement(self):
        spec=importlib.util.spec_from_file_location('installer', ROOT / 'install.py')
        m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
        with tempfile.TemporaryDirectory() as d:
            base=Path(d); source=base/'game.exe'
            source.write_bytes(b'MZ-native-prefix')
            with zipfile.ZipFile(source,'a') as z:
                z.writestr('main.lua',b'return "original"')
                z.writestr('asset.bin',b'preserve')
            (base/'trainer.lua').write_bytes((ROOT/'trainer.lua').read_bytes())
            m.ROOT=base;m.GAME=base;m.EXE=source;m.BACKUP=base/'backup';m.ORIGINAL_HASH=m.sha(source)
            import sys
            sys.path.insert(0,str(ROOT))
            with patch.object(m,'not_running',lambda:None):
                m.install()
            import json
            report=json.loads((base/'install-report.json').read_text())
            self.assertTrue(report['installed'])
            self.assertEqual(report['original_archive_members'],2)
            self.assertEqual(report['installed_sha256'],m.sha(source))

if __name__=='__main__': unittest.main()
