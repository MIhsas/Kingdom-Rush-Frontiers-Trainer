"""Install a reversible, version-pinned script bridge in the fused LÖVE archive."""
import hashlib
import json
import shutil
import subprocess
import zipfile
from datetime import datetime
from pathlib import Path

ROOT=Path(__file__).resolve().parent
GAME=Path(r'D:\Steam\steamapps\common\Kingdom Rush Frontiers')
EXE=GAME/'Kingdom Rush Frontiers.exe'
ORIGINAL_HASH='5670a08282f54481099d6d0a80f02669b85a26cbdb73525091e4bb625a9035da'
BACKUP=GAME/'codex-frontiers-trainer-backup-20261010'

def sha(path):
    with path.open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()

def patch_archive(source, target, root):
    with zipfile.ZipFile(source) as z:
        if 'codex_frontiers_trainer.lua' in z.namelist(): raise ValueError('Already installed')
        if len(z.namelist())!=len(set(z.namelist())): raise ValueError('Duplicate archive members')
        info=z.getinfo('main.lua'); original=z.read(info)
    bridge_path=(root/'ipc').as_posix()+'/'
    wrapper=("local original = assert(love.filesystem.load('codex_original_main.luac'))\n"
             "original(...)\n"
             "local ok, err = pcall(function()\n"
             "  local trainer = assert(love.filesystem.load('codex_frontiers_trainer.lua'))()\n"
             f"  trainer.install('{bridge_path}')\n"
             "end)\n"
             "if not ok then print('Frontiers trainer startup failed: '..tostring(err)) end\n")
    if target.exists(): raise FileExistsError(target)
    shutil.copy2(source,target)
    with zipfile.ZipFile(target,'a') as z:
        previous=z.NameToInfo.pop('main.lua');z.filelist.remove(previous)
        z.writestr(info,wrapper.encode('utf-8'))
        z.writestr('codex_original_main.luac',original,compress_type=zipfile.ZIP_DEFLATED)
        z.writestr('codex_frontiers_trainer.lua',(root/'trainer.lua').read_bytes(),compress_type=zipfile.ZIP_DEFLATED)

def not_running():
    result=subprocess.run(['powershell','-NoProfile','-Command',
        "@(Get-Process -Name 'Kingdom Rush Frontiers' -ErrorAction SilentlyContinue).Count"],
        capture_output=True,text=True,check=True)
    if result.stdout.strip()!='0': raise RuntimeError('Close Frontiers before installation/restoration')

def install():
    not_running()
    if sha(EXE)!=ORIGINAL_HASH: raise ValueError('Game version/hash differs; refuse to overwrite')
    (ROOT/'ipc').mkdir(exist_ok=True)
    BACKUP.mkdir(exist_ok=True)
    backup_exe=BACKUP/EXE.name
    if backup_exe.exists():
        if sha(backup_exe)!=ORIGINAL_HASH: raise ValueError('Existing backup hash differs')
    else: shutil.copy2(EXE,backup_exe)
    saves=Path.home()/'AppData/Roaming/kingdom_rush_frontiers'
    save_backup=BACKUP/'save-before-install'
    if saves.exists() and not save_backup.exists(): shutil.copytree(saves,save_backup)
    staged=ROOT/'Frontiers.staged.exe'
    patch_archive(EXE,staged,ROOT)
    from lua_runtime import lib
    state=lib.luaL_newstate()
    try:
        with zipfile.ZipFile(EXE) as old, zipfile.ZipFile(staged) as new:
            original_member_count=len(old.namelist())
            assert new.testzip() is None
            assert len(new.namelist())==len(old.namelist())+2
            assert len(new.namelist())==len(set(new.namelist()))
            for info in old.infolist():
                if info.filename!='main.lua':
                    revised=new.getinfo(info.filename)
                    assert (info.CRC,info.file_size)==(revised.CRC,revised.file_size),info.filename
            assert new.read('codex_original_main.luac')==old.read('main.lua')
            count=0
            for n in new.namelist():
                if n.endswith(('.lua','.luac')):
                    data=new.read(n)
                    status=lib.luaL_loadbuffer(state,data,len(data),n.encode())
                    assert status==0,(n,lib.lua_tolstring(state,-1,None))
                    lib.lua_settop(state,0);count+=1
            prefix=min(i.header_offset for i in old.infolist())
        with EXE.open('rb') as old, staged.open('rb') as new:
            assert old.read(prefix)==new.read(prefix),'Native code changed'
    finally: lib.lua_close(state)
    not_running()
    temp=GAME/'Frontiers.trainer.installing'
    if temp.exists(): raise FileExistsError(temp)
    shutil.copy2(staged,temp)
    temp.replace(EXE)
    report={'installed':True,'game':str(EXE),'backup':str(backup_exe),
            'save_backup':str(save_backup),'original_sha256':ORIGINAL_HASH,
            'installed_sha256':sha(EXE),'changed_members':['main.lua'],
            'added_members':['codex_original_main.luac','codex_frontiers_trainer.lua'],
            'original_archive_members':original_member_count,'lua_chunks_loaded':count,
            'crc':'passed','native_prefix':'unchanged','restart_required':True,
            'installed_at':datetime.now().isoformat()}
    (ROOT/'install-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))
    staged.unlink()

if __name__=='__main__': install()
