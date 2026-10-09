local root=assert(os.getenv('KR_TRAINER_ROOT'))..'/'
local noop=function()end
local log=setmetatable({},{__index=function()return noop end});log.new=function()return log end
package.loaded['klua.log']=log;package.loaded['hump.signal']={emit=noop}
package.loaded['klua.macros']={}
assert(loadfile(root..'inspection/lib_klua_table.lua'))()
package.loaded['klua.table']=true
package.loaded['klua.persistence']=assert(loadfile(root..'inspection/lib_klua_persistence.lua'))()
local fsroot=root..'tests/ipc/'
local disk_writes=0
love={filesystem={read=function(n)local f=assert(io.open(fsroot..n,'r'));local s=f:read('*a');f:close();return s end,
    write=function(n,s)disk_writes=disk_writes+1;local f=assert(io.open(fsroot..n,'w'));f:write(s);f:close();return true end}}
local sio=assert(loadfile(root..'inspection/all_storage_io_generic.lua'))()
local originalslot=assert(loadfile(fsroot..'sample_slot.lua'))()
assert(sio:write_file('slot_1.lua',originalslot))
local load=assert(loadfile(root..'inspection/all_storage-187.luac'))
debug.setupvalue(load,1,log);debug.setupvalue(load,2,{});debug.setupvalue(load,3,{})
local save=assert(loadfile(root..'inspection/all_storage-242.luac'))
debug.setupvalue(save,1,log);debug.setupvalue(save,2,{emit=noop})
version={string='test'}
local storage={active_slot_idx=1,SLOT_FILE_FMT='slot_%d.lua',load_slot=load,save_slot=save,
    load_lua=function(_,name,force)local ok,data=sio:load_file(name,force);assert(ok);return data end,
    write_lua=function(_,name,data)return sio:write_file(name,data) end,
    new_slot=function()return originalslot end}
local t=assert(loadfile(root..'trainer.lua'))().new(fsroot,'methods')
t:attach_storage(storage)
local baseline=storage:load_slot()
local before=table.deepclone(baseline)
assert(t:set_gems(storage,123456))
local after=storage:load_slot(nil,true)
assert(after.gems==123456,'real persisted gems')
after.gems=before.gems;after.version_string=before.version_string
local function equal(a,b)
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end
    return true
end
assert(equal(before,after),'all other real save fields preserved')
print('PASS real Frontiers load_slot/save_slot/storage_io/persistence; only gems changed')
local gui={game={store={ts=10}}}
local mode=assert(loadfile(root..'inspection/all-desktop_game_gui-1878.luac'))
debug.setupvalue(mode,1,gui);debug.setupvalue(mode,2,{queue=noop})
local update=assert(loadfile(root..'inspection/all-desktop_game_gui-1902.luac'))
debug.setupvalue(update,1,{clamp=function(lo,hi,n)return math.max(lo,math.min(hi,n))end})
debug.setupvalue(update,2,gui)
PowerButton={super={update=noop}}
local button={mode='cooldown',animations={},cooldown_time=50,
    cooldown_view={hidden=false,start_ts=10,scale={x=1,y=-1}},set_mode=mode,
    enable=function(self)self.enabled=true end,disable=function(self)self.enabled=false end}
local game={store={player_gold=100,lives=20},game_gui={power_1=button}}
t.options={power_cd=true};t:apply(game)
assert(button.mode=='ready' and button.enabled and button.cooldown_view.hidden,'real spell readiness')
update(button,0.1)
assert(button.mode=='ready','real update keeps readiness')
t.options={};button:set_mode('cooldown');update(button,0.1)
assert(button.mode=='cooldown' and not button.enabled,'normal cooldown restored on next cast')
print('PASS real PowerButton.set_mode/update; zero CD on and off')
