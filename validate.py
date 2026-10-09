import json
import subprocess
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parent
checks=[]
for name in ['verify_core.lua','verify_rewards.lua','verify_game_methods.lua','verify_speed.lua','test_install.py','test_controller.py']:
    args=[sys.executable]
    if name.endswith('.lua'): args+=[str(ROOT/'lua_runtime.py')]
    args+=[str(ROOT/'tests'/name)]
    result=subprocess.run(args,capture_output=True,text=True,cwd=ROOT)
    checks.append({'name':name,'exit_code':result.returncode,'output':result.stdout+result.stderr})
    print(name+': '+('PASS' if result.returncode==0 else 'FAIL'))
    if result.returncode:print(checks[-1]['output'])
report={'engine':'Installed Frontiers lua51.dll','checks':checks,
        'boundary':'Actual game functions in isolated tests; actual startup heartbeat; no full live level verification.'}
(ROOT/'validation-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if any(c['exit_code'] for c in checks):sys.exit(1)
