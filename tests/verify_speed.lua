local root=assert(os.getenv('KR_TRAINER_ROOT'))..'/'
local M=assert(loadfile(root..'trainer.lua'))()
local noop=function()end
local log=setmetatable({},{__index=function()return noop end});log.new=function()return log end
package.loaded['klua.log']=log
package.loaded['klua.macros']={clamp=function(lo,hi,n)return math.max(lo,math.min(hi,n))end}
local sim=assert(loadfile(root..'inspection/lib_klove_simulation.lua'))()
local t=M.new(root..'tests/ipc/','speed-test',function()return 100 end)
assert(type(t.attach_speed)=='function','Battle speed has not been implemented')
t:attach_speed(sim);t:attach_speed(sim)
local function config(speed)
    local f=assert(io.open(root..'tests/ipc/control.txt','w'))
    f:write('session=speed-test\ntime=100\nspeed='..speed..'\n');f:close()
    t:poll(nil,nil)
end
local function reset()
    sim.store={tick_length=1/30,tick=0,tick_ts=0,ts=0,to=0,paused=false,step=false,
        entities={},pending_inserts={},pending_removals={}}
    sim.systems_on_update={}
end
for tenths=10,30 do
    local speed=tenths/10
    config(string.format('%.1f',speed));reset()
    assert(t.options.speed==speed,'speed accepted')
    for i=1,360 do sim:update(1/60)end
    assert(math.abs(sim.store.ts-6*speed)<0.00001,'simulation time incorrect')
    assert(math.abs(sim.store.tick_ts-6*speed)<1/30+0.00001,'battle ticks lost')
    print('PASS '..string.format('%.1f',speed)..'x: actual game time and ticks')
end
for _,bad in ipairs({'0.9','3.1','1.15','nan','inf','-1.0','garbage'})do
    config(bad);assert((t.options.speed or 1)==1,'invalid speed accepted: '..bad)
end
config('3.0');reset();sim.store.paused=true;sim:update(1/60)
assert(sim.store.tick==0 and sim.store.ts==0,'pause ignored')
sim.store.step=true;sim:update(0.04)
assert(sim.store.tick==1,'paused single-step multiplied')
config('2.7');reset();sim:update(0.05)
assert(math.abs(sim.store.ts-0.135)<0.00001 and sim.store.tick>=3,'slower frames lose ticks')
local f=assert(io.open(root..'tests/ipc/control.txt','w'));f:write('session=wrong\ntime=100\nspeed=3.0\n');f:close()
t:poll(nil,nil);assert((t.options.speed or 1)==1,'session change keeps speed')
print('PASS precision/range validation, pause, single-step, frame substeps and session reset')
