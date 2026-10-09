-- Local controller protocol. No incoming text is ever evaluated as Lua.
local M = {}
local function read_values(path)
    local f = io.open(path, 'r')
    if not f then return {} end
    local data = f:read(8193); f:close()
    if not data or #data > 8192 then return {} end
    local values = {}
    for line in data:gmatch('[^\r\n]+') do
        local k,v = line:match('^([a-z_]+)=(.*)$')
        if k then values[k]=v end
    end
    return values
end
local function integer(value, maximum)
    local n=tonumber(value)
    if n and n>=0 and n<=maximum and n==math.floor(n) then return n end
end
local function fresh(values, session, now)
    local ts=tonumber(values.time)
    return values.session==session and ts and ts<=now+2 and now-ts<=5
end
local function speed_value(value)
    if type(value)~='string' or not value:match('^[123]%.%d$') then return 1 end
    local n=tonumber(value)
    if n>=1 and n<=3 then return n end
    return 1
end
function M.new(root, session, clock)
    local t={root=root,session=session,clock=clock or os.time,options={},seen={},
        ack='',result='',fault='',last_gems=nil}
    function t:set_gems(storage, value)
        if not storage or not storage.active_slot_idx then return false,'no_slot' end
        local slot=storage:load_slot()
        if type(slot)~='table' then return false,'no_slot' end
        if slot.gems~=value then
            local old=slot.gems; slot.gems=value
            if not storage:save_slot(slot) then
                slot.gems=old
                -- Generic storage updates its cache before its filesystem write.
                -- Reload disk after failure so a later save cannot falsely skip it.
                pcall(storage.load_slot,storage,nil,true)
                return false,'save_failed'
            end
        end
        self.last_gems=value
        return true,'ok'
    end
    function t:poll(game, storage)
        local now=self.clock()
        local v=read_values(self.root..'control.txt')
        local o={}
        if fresh(v,self.session,now) then
            for _,k in ipairs({'double_gold','power_cd','hero_cd','lock_gold','lock_gems','lock_lives'}) do
                o[k]=v[k]=='1'
            end
            o.gold=integer(v.gold,999999999)
            o.gems=integer(v.gems,999999999)
            o.lives=integer(v.lives,9999)
            o.speed=speed_value(v.speed)
            if not o.gold then o.lock_gold=false end
            if not o.gems then o.lock_gems=false end
            if not o.lives or o.lives<1 then o.lock_lives=false end
        end
        self.options=o
        if storage then self:attach_storage(storage) end
        local c=read_values(self.root..'command.txt')
        if fresh(c,self.session,now) and c.id and not self.seen[c.id] then
            self.seen[c.id]=true; self.ack=c.id
            local max=c.action=='set_lives' and 9999 or 999999999
            local n=integer(c.value,max)
            self.result='bad_value'
            if n then
                if c.action=='set_gems' then
                    local ok,result=self:set_gems(storage,n); self.result=result
                elseif c.action=='set_gold' or c.action=='set_lives' then
                    local s=game and game.store
                    self.result='no_battle'
                    if s and type(s.player_gold)=='number' and type(s.lives)=='number' then
                        if c.action=='set_lives' and n<1 then self.result='bad_value'
                        elseif c.action=='set_gold' then s.player_gold=n;self.result='ok'
                        else s.lives=n;self.result='ok' end
                    end
                else self.result='bad_action' end
            end
        end
        if storage and storage.active_slot_idx then
            if o.lock_gems then
                if not self.gems_slot then self.gems_slot=storage.active_slot_idx end
                if self.gems_slot==storage.active_slot_idx then
                    local ok,result=self:set_gems(storage,o.gems)
                    if not ok then self.fault=result;self.options={} end
                end
            else self.gems_slot=nil end
            local slot=storage:load_slot()
            self.last_gems=slot and slot.gems or nil
        else self.last_gems=nil end
    end
    function t:attach_storage(storage)
        if self.storage==storage then return end
        self.storage=storage
        local original=storage.save_slot
        storage.save_slot=function(s,slot,idx,...)
            if slot and self.options.lock_gems and self.gems_slot==s.active_slot_idx
                and (idx==nil or idx==self.gems_slot) then
                slot.gems=self.options.gems
            end
            return original(s,slot,idx,...)
        end
    end
    function t:apply(game)
        local s=game and game.store
        if not s or type(s.player_gold)~='number' then return end
        local o=self.options
        if o.lock_gold then s.player_gold=o.gold end
        if o.lock_lives then s.lives=o.lives end
        if o.power_cd and game.game_gui then
            for i=1,3 do
                local b=game.game_gui['power_'..i]
                if b and b.mode=='cooldown' then b:set_mode('ready') end
            end
        end
        if o.hero_cd and type(s.tick_ts)=='number' then
            for _,e in pairs(s.entities or {}) do
                if e.hero and e.timed_attacks then
                    for _,a in pairs(e.timed_attacks.list or {}) do
                        if type(a.cooldown)=='number' and type(a.ts)=='number' then
                            a.ts=s.tick_ts-a.cooldown-1
                        end
                    end
                end
            end
        end
    end
    function t:attach_rewards(systems, signal)
        if self.health==systems.health then return end
        self.health=systems.health
        local update=systems.health.on_update
        systems.health.on_update=function(s,dt,ts,store)
            self.reward_store=store
            local ok,err=pcall(update,s,dt,ts,store)
            self.reward_store=nil
            if not ok then error(err,0) end
        end
        local emit=signal.emit
        signal.emit=function(event,entity,amount,...)
            if event=='got-enemy-gold' and self.options.double_gold and self.reward_store
                and type(amount)=='number' then
                self.reward_store.player_gold=self.reward_store.player_gold+amount
                amount=amount*2
            end
            return emit(event,entity,amount,...)
        end
    end
    function t:attach_speed(simulation)
        if self.speed_simulation==simulation then return end
        self.speed_simulation=simulation
        local original=simulation.update
        simulation.update=function(sim,dt)
            local factor=self.options.speed or 1
            local store=sim.store
            if factor==1 or not store or store.paused or dt<=0 then
                return original(sim,dt)
            end
            -- Original update advances at most one tick and clamps excess time.
            -- Small substeps preserve every accelerated tick at all 21 rates.
            local total=dt*factor
            local step=math.max((store.tick_length or 1/30)/2,0.0001)
            local count=math.max(1,math.ceil(total/step))
            for i=1,count do original(sim,total/count) end
        end
    end
    function t:status(game, storage)
        local s=game and game.store
        local lines={'version=2','session='..self.session,'time='..self.clock(),
            'speed='..string.format('%.1f',self.options.speed or 1),
            'battle='..(s and type(s.player_gold)=='number' and '1' or '0'),
            'gold='..tostring(s and s.player_gold or ''),'lives='..tostring(s and s.lives or ''),
            'gems='..tostring(self.last_gems or ''),
            'slot='..tostring(storage and storage.active_slot_idx or ''),
            'ack='..self.ack,'result='..self.result,'fault='..self.fault}
        for _,key in ipairs({'double_gold','power_cd','hero_cd','lock_gold','lock_gems','lock_lives'}) do
            lines[#lines+1]=key..'='..(self.options[key] and '1' or '0')
        end
        local path=self.root..'status.txt'
        local f=io.open(path..'.tmp','w')
        if not f then return end
        f:write(table.concat(lines,'\n')..'\n');f:close()
        os.remove(path);os.rename(path..'.tmp',path)
    end
    return t
end
function M.install(root)
    local session=tostring(os.time())..'-'..tostring({}):gsub('[^%w]','')
    local t=M.new(root,session)
    local elapsed=1
    local original=love.update
    local function active_game()
        local director=main and main.handler
        local g=director and director.active_item
        if g and g.item_name=='game' and g.game_gui then return g end
    end
    local function step(dt, force)
        local g=active_game()
        local storage=package.loaded.storage
        local systems=package.loaded.systems
        local signal=package.loaded['hump.signal']
        local simulation=package.loaded['klove.simulation']
        if simulation then t:attach_speed(simulation) end
        if systems and signal then t:attach_rewards(systems,signal) end
        elapsed=elapsed+dt
        if force or elapsed>=0.2 then
            elapsed=0;t:poll(g,storage);t:status(g,storage)
        end
        t:apply(g)
    end
    love.update=function(dt)
        local ok,err=pcall(step,dt,false)
        if not ok then t.options={};t.fault=tostring(err):gsub('[\r\n]',' '):sub(1,240) end
        original(dt)
        ok,err=pcall(t.apply,t,active_game())
        if not ok then t.options={};t.fault=tostring(err):gsub('[\r\n]',' '):sub(1,240) end
    end
    t:status(nil,nil)
    return t
end
return M
