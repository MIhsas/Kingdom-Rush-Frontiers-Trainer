local root=assert(os.getenv('KR_TRAINER_ROOT'))..'/'
local noop=function() end
local log=setmetatable({},{__index=function() return noop end});log.new=function() return log end
package.loaded['klua.log']=log
local events={}
local signal={emit=function(...) events[#events+1]={...} end}
package.loaded['hump.signal']=signal
package.loaded['klua.macros']={round=function(n) return math.floor(n+0.5) end,
    clamp=function(lo,hi,n) return math.max(lo,math.min(hi,n)) end}
local db={}
function db:filter_iter(entities,component)
    local key
    return function()
        while true do local value;key,value=next(entities,key)
            if key==nil then return end
            if value[component] then return key,value end
        end
    end
end
package.loaded.entity_db=db
package.loaded.path_db={path_connections={},get_end_node=function() return 10 end}
package.loaded.game_settings={}
for _,n in ipairs({'wave_db','klua.table','klua.dump','klove.animation_db','achievements',
 'difficulty','klove.image_db','klove.shader_db','klove.font_db','grid_db','sound_db',
 'upgrades','utils','script_utils','level_utils','klua.vector','storage','constants'}) do
    package.loaded[n]={}
end
FPS=30;GAME_MODE_CAMPAIGN=1;GAME_MODE_ENDLESS=4
simulation={queue_remove_entity=noop,queue_insert_entity=noop}
local systems=assert(loadfile(root..'inspection/all_systems.lua'))()
local t=assert(loadfile(root..'trainer.lua'))().new(root..'tests/ipc/','rewards')
t:attach_rewards(systems,signal)
for _,enabled in ipairs({false,true,false}) do
    t.options={double_gold=enabled}
    for _,gold in ipairs({0,1,7,40,125}) do
        local enemy={id=1,enemy={gold=gold,gems=0},health={hp=0,dead_lifetime=10}}
        local s={player_gold=100,entities={[1]=enemy},damage_queue={},tick_ts=1,level_mode=1}
        events={};systems.health:on_update(0.1,1,s)
        local expected=gold*(enabled and 2 or 1)
        assert(s.player_gold==100+expected,'kill reward')
        assert(events[#events][3]==expected,'reward display')
        assert(enemy.enemy.gold==gold,'enemy template untouched')
        systems.health:on_update(0.1,1,s)
        assert(s.player_gold==100+expected,'no duplicate payout')
        print('PASS actual Frontiers kill reward '..gold..', double='..tostring(enabled))
    end
end
t.options={double_gold=true}
local live={id=1,enemy={gold=7,gems=0},health={hp=10,dead_lifetime=10}}
local s={player_gold=100,entities={[1]=live},damage_queue={},tick_ts=1,level_mode=1}
systems.health:on_update(0.1,1,s);assert(s.player_gold==100,'live enemy no reward')
local escaped={id=1,enemy={gold=7,lives_cost=1,remove_at_goal_line=true},nav_path={pi=1,ni=11}}
s={player_gold=100,entities={[1]=escaped},lives=20}
systems.goal_line:on_update(0.1,1,s)
assert(s.player_gold==107 and s.lives==19,'escape payout stays original')
print('PASS live and escaped enemies; only kills are doubled')
