import subprocess
import unittest
from pathlib import Path

EXE=Path(__file__).resolve().parents[1]/'Frontiers修改器.exe'

class ControllerTests(unittest.TestCase):
    def test_protocol_and_window(self):
        self.assertTrue(EXE.exists(),'Windows controller is missing')
        result=subprocess.run([str(EXE),'--self-test'],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

if __name__=='__main__': unittest.main()
