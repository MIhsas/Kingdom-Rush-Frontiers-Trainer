local root = assert(os.getenv('KR_TRAINER_ROOT'))..'/'
assert(io.open(root..'trainer.lua', 'r'), 'Runtime switches have not been implemented')
local M = assert(loadfile(root..'trainer.lua'))()
local clock = 100
local t = M.new(root..'tests/ipc/', 'test-session', function() return clock end)
local function write(name, text)
    local f=assert(io.open(root..'tests/ipc/'..name,'w')); f:write(text); f:close()
end
local function check(name, actual, expected)
    assert(actual == expected, name..': '..tostring(actual)..' ~= '..tostring(expected))
    print('PASS '..name)
end
local function config(extra)
    write('control.txt', 'session=test-session\ntime=100\n'..extra)
end
local saves=0
local slot={gems=25, bag={bomb=7}, progress='preserve'}
local storage={active_slot_idx=1,load_slot=function() return slot end,
    save_slot=function(_, value) saves=saves+1; slot=value; return true end}
local store={player_gold=100,lives=20,tick_ts=5,entities={}}
local button={mode='cooldown',set_mode=function(self, mode) self.mode=mode end}
local locked={mode='locked',set_mode=button.set_mode}
local game={store=store,game_gui={power_1=button,power_2=locked}}
config('double_gold=1\npower_cd=1\nlock_gold=1\ngold=800\nlock_lives=1\nlives=60\n')
t:poll(game,storage); t:apply(game)
check('gold lock',store.player_gold,800)
check('life lock',store.lives,60)
check('spell ready',button.mode,'ready')
check('locked spell remains locked',locked.mode,'locked')
check('double reward switch',t.options.double_gold,true)
write('command.txt','session=test-session\nid=one\ntime=100\naction=set_gems\nvalue=456\n')
t:poll(game,storage)
check('gems saved',slot.gems,456)
check('inventory preserved',slot.bag.bomb,7)
check('one save',saves,1)
t:poll(game,storage); check('command exactly once',saves,1)
write('command.txt','session=old-session\nid=two\ntime=100\naction=set_gems\nvalue=999\n')
t:poll(game,storage); check('old session refused',slot.gems,456)
write('command.txt','session=test-session\nid=three\ntime=100\naction=set_gold\nvalue=-1\n')
t:poll(game,storage); check('negative gold refused',store.player_gold,800)
write('command.txt','session=test-session\nid=four\ntime=100\naction=set_gold\nvalue=1.5\n')
t:poll(game,storage); check('fractional gold refused',store.player_gold,800)
write('command.txt','session=test-session\nid=five\ntime=100\naction=set_gold\nvalue=999999999999\n')
t:poll(game,storage); check('oversized gold refused',store.player_gold,800)
write('command.txt','session=test-session\nid=six\ntime=90\naction=set_gold\nvalue=250\n')
t:poll(game,storage); check('expired command refused',store.player_gold,800)
write('command.txt','session=test-session\nid=seven\ntime=100\naction=set_gold\nvalue=250\n')
t:poll(nil,storage); check('outside battle refused',store.player_gold,800)
config('lock_gems=1\ngems=1000\n')
t:poll(game,storage)
check('gems lock',slot.gems,1000)
local prior=saves;t:poll(game,storage);check('no redundant disk save',saves,prior)
slot.gems=999;t:poll(game,storage);check('gems lock replenishes',slot.gems,1000)
config('hero_cd=1\n')
local attack={cooldown=15,ts=4}
local basic={cooldown=1,ts=4}
store.entities={ {hero={},timed_attacks={list={attack}},melee={attacks={basic}}},
    {enemy={},timed_attacks={list={{cooldown=20,ts=4}}}} }
t:poll(game,storage);t:apply(game)
check('hero cooldown elapsed',attack.ts,store.tick_ts-attack.cooldown-1)
check('hero base attack unchanged',basic.ts,4)
check('enemy skill unchanged',store.entities[2].timed_attacks.list[1].ts,4)
clock=106;t:poll(game,storage)
check('controller expiry disables switches',t.options.hero_cd,nil)
local reloaded=false
local failedslot={gems=30}
local failedstorage={active_slot_idx=1,
    load_slot=function(_,idx,force) if force then reloaded=true end;return failedslot end,
    save_slot=function() return false end}
local ok,why=t:set_gems(failedstorage,900)
check('failed save reported',ok,false)
check('failed save rollback',failedslot.gems,30)
check('failed save invalidates game cache',reloaded,true)
print('All IPC, numeric, cooldown and persistence checks passed')
