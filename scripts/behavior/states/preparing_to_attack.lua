-- Creeperbots - Preparing to Attack State Handler (Rewritten)
-- Phase 1: Guard positioning around leader
-- Phase 2: Send distractor
-- Phase 3: After distractor sent, bots path directly to nests
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local config = require "scripts.behavior.config"
local behavior_utils = require "scripts.behavior.utils"
local distractor_state_module = require "scripts.behavior.states.distractor"

local preparing_to_attack_state = {}

function preparing_to_attack_state.handle_preparing_to_attack_state(creeper, event, position, entity, surface, tier, party)
    update_color(entity, "preparing_to_attack")

    if not party then
        creeper.preparing_to_attack_initialized = nil
        creeper.state = "grouping"
        update_color(entity, "grouping")
        return
    end

    -- Check if target is dead - if so, reform
    if party.target_nest then
        if not party.target_nest.valid or party.target_nest.health <= 0 then
            -- Target is dead, clear attack state and reform
            party.target_nest = nil
            party.attack_initiated = false
            party.scout_sent = false
            creeper.target = nil
            creeper.target_position = nil
            creeper.target_health = nil
            creeper.preparing_to_attack_initialized = nil
            entity.follow_target = nil
            entity.autopilot_destination = nil
            if storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number] then
                storage.scheduled_autopilots[creeper.unit_number] = nil
            end
            creeper.state = "grouping"
            update_color(entity, "grouping")
            return
        end
    end

    local leader = storage.creeperbots[party.grouping_leader]
    local leader_pos = nil
    if leader and leader.entity and leader.entity.valid then
        leader_pos = leader.entity.position
    else
        creeper.is_leader = true
        party.grouping_leader = creeper.unit_number
        leader_pos = entity.position
    end

    -- CRITICAL: Clear all autopilot destinations ONCE when first entering preparing_to_attack state
    -- This handles cases where bots were teleported and have old destinations
    -- Only do this once, not every tick, so bots can actually move to their positions
    if not creeper.preparing_to_attack_initialized then
        -- Clear follow_target aggressively - this prevents weird movement
        entity.follow_target = nil
        entity.autopilot_destination = nil
        -- Clear all autopilot destinations (autopilot_destinations is read-only, so we clear current destination repeatedly)
        local attempts = 0
        while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
            entity.autopilot_destination = nil
            attempts = attempts + 1
        end
        if storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number] then
            storage.scheduled_autopilots[creeper.unit_number] = nil
        end
        creeper.preparing_to_attack_initialized = true
    end

    -- Leader clears movement during preparation phase only
    if creeper.is_leader and not party.attack_initiated then
        entity.autopilot_destination = nil
        entity.follow_target = nil
        if storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] then
            storage.scheduled_autopilots[entity.unit_number] = nil
        end
        
        -- Check if leader is being attacked - if so, trigger immediate scout
        local is_being_attacked = false
        if not creeper.last_health then
            creeper.last_health = entity.health
        end
        if not creeper.max_health then
            creeper.max_health = entity.health
        end
        if entity.health > creeper.max_health then
            creeper.max_health = entity.health
        end
        local health_loss = creeper.last_health - entity.health
        local health_threshold = math.max(5, creeper.max_health * 0.01)
        if health_loss > health_threshold then
            is_being_attacked = true
        end
        creeper.last_health = entity.health
        
        -- If leader is being attacked, find attacker and send scout immediately
        if is_being_attacked and not party.scout_sent then
            local nearby_enemies = surface.find_entities_filtered({
                type = {"unit", "turret", "unit-spawner"},
                position = position,
                radius = 30,
                force = "enemy"
            })
            
            if #nearby_enemies > 0 then
                -- Find closest enemy
                local closest_enemy = nil
                local min_dist = math.huge
                for _, enemy in ipairs(nearby_enemies) do
                    if enemy.valid and enemy.health > 0 then
                        local dist = calculate_distance(position, enemy.position)
                        if dist < min_dist then
                            min_dist = dist
                            closest_enemy = enemy
                        end
                    end
                end
                
                if closest_enemy then
                    -- Trigger scout immediately
                    party.target_nest = closest_enemy
                    party.target_health = closest_enemy.health
                    party.target_max_health = closest_enemy.health
                    party.scout_sent = false  -- Will be set to true in Phase 2
                    party.attack_initiated = true
                    party.attack_start_tick = event.tick
                end
            end
        end
    end

    -- Get all party members
    local members = {}
    local distractors = {}
    for unit_number, member in pairs(storage.creeperbots or {}) do
        if member.party_id == creeper.party_id and member.entity and member.entity.valid then
            table.insert(members, member)
            if member.is_distractor then
                table.insert(distractors, member)
            end
        end
    end

    if #members == 1 and creeper.is_leader then
        entity.autopilot_destination = nil
        return
    end

    -- Initialize preparation timing
    if not party.preparation_start_tick then
        party.preparation_start_tick = event.tick
    end

    -- Determine distractor count
    local distractor_count = 0
    if #members >= 6 then distractor_count = 5
    elseif #members >= 5 then distractor_count = 4
    elseif #members >= 4 then distractor_count = 3
    elseif #members >= 3 then distractor_count = 2
    elseif #members >= 2 then distractor_count = 1
    end
    local current_distractors = #distractors

    -- ============================================
    -- PHASE 1: GUARD POSITIONING (Before distractor sent)
    -- ============================================
    if not party.attack_initiated then
        -- Assign distractors (they will guard around leader)
        if current_distractors < distractor_count then
            local candidates = {}
            for _, member in ipairs(members) do
                if member.state == "preparing_to_attack" and not member.is_leader and not member.is_distractor then
                    table.insert(candidates, member)
                end
            end
            table.sort(candidates, function(a, b) return a.tier < b.tier end)

            for _, candidate in ipairs(candidates) do
                if current_distractors < distractor_count then
                    candidate.is_distractor = true
                    update_color(candidate.entity, "distractor")
                    current_distractors = current_distractors + 1
                    table.insert(distractors, candidate)
                end
            end
        end

        -- Guard positions around leader
        local guard_positions = {}
        if distractor_count == 1 then
            guard_positions = {{angle = 180, radius = 3}}
        elseif distractor_count == 2 then
            guard_positions = {{angle = 90, radius = 4}, {angle = 270, radius = 4}}
        elseif distractor_count == 3 then
            guard_positions = {{angle = 120, radius = 5}, {angle = 240, radius = 5}, {angle = 0, radius = 5}}
        elseif distractor_count == 4 then
            guard_positions = {{angle = 45, radius = 6}, {angle = 135, radius = 6}, {angle = 225, radius = 6}, {angle = 315, radius = 6}}
        elseif distractor_count >= 5 then
            guard_positions = {{angle = 0, radius = 8}, {angle = 72, radius = 8}, {angle = 144, radius = 8}, {angle = 216, radius = 8}, {angle = 288, radius = 8}}
        end

        -- Position distractors around leader
        if current_distractors > 0 then
            for i, distractor in ipairs(distractors) do
                if distractor.entity and distractor.entity.valid and distractor.state == "preparing_to_attack" then
                    local pos = guard_positions[i] or {angle = 180, radius = 3}
                    local dest_pos = {
                        x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                        y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                    }
                    local dist_to_current = calculate_distance(distractor.entity.position, dest_pos)
                    if dist_to_current >= 3 then
                        schedule_autopilot_destination(distractor, {dest_pos}, event.tick + 30, false)
                    end
                end
            end
        end

        -- Non-distractor followers move to leader
        if not creeper.is_leader and not creeper.is_distractor then
            local dist_to_leader = calculate_distance(position, leader_pos)
            if dist_to_leader > 3 then
                local dest_pos = {
                    x = math.floor(leader_pos.x),
                    y = math.floor(leader_pos.y)
                }
                schedule_autopilot_destination(creeper, {dest_pos}, event.tick + 30, false)
            end
        end

        -- ============================================
        -- PHASE 2: SEND SCOUT AND CALCULATE REQUIRED BOTS
        -- ============================================
        -- Immediately send one scout bot to get target health, then calculate and send required bots
        if not party.scout_sent then
            local target, target_type = behavior_utils.scan_for_enemies(leader_pos, surface, config.tier_configs[entity.name].max_targeting)
            
            if target and (target_type == "nest" or target_type == "unit" or target_type == "turret") then
                -- Find closest bot to send as scout (prefer non-leader, non-distractor)
                local scout_candidate = nil
                local min_distance = math.huge
                
                for _, member in ipairs(members) do
                    if member.entity and member.entity.valid and 
                       member.state == "preparing_to_attack" and 
                       not member.is_leader and 
                       not member.is_distractor then
                        local dist_to_target = calculate_distance(member.entity.position, target.position)
                        if dist_to_target < min_distance then
                            min_distance = dist_to_target
                            scout_candidate = member
                        end
                    end
                end
                
                -- If no non-distractor found, use any available bot
                if not scout_candidate then
                    for _, member in ipairs(members) do
                        if member.entity and member.entity.valid and 
                           member.state == "preparing_to_attack" and 
                           not member.is_leader then
                            local dist_to_target = calculate_distance(member.entity.position, target.position)
                            if dist_to_target < min_distance then
                                min_distance = dist_to_target
                                scout_candidate = member
                            end
                        end
                    end
                end
                
                -- Send scout immediately
                if scout_candidate then
                    -- Store target info in party
                    party.target_nest = target
                    party.target_health = target.health
                    party.target_max_health = target.health
                    party.scout_sent = true
                    party.scout_unit_number = scout_candidate.unit_number
                    party.attack_initiated = true
                    party.attack_start_tick = event.tick
                    
                    -- Send scout to target
                    scout_candidate.target = target
                    scout_candidate.target_position = target.position
                    scout_candidate.target_health = target.health
                    scout_candidate.preparing_to_attack_initialized = nil
                    scout_candidate.entity.follow_target = nil
                    scout_candidate.entity.autopilot_destination = nil
                    scout_candidate.state = "approaching"
                    update_color(scout_candidate.entity, "approaching")
                    
                    -- Path to target
                    request_multiple_paths(scout_candidate.entity.position, target.position, party, surface, scout_candidate.unit_number)
                end
            end
        end
        
        -- ============================================
        -- PHASE 2B: CALCULATE AND SEND REQUIRED BOTS
        -- ============================================
        -- After scout is sent, calculate how many bots are needed and send them
        if party.scout_sent and party.target_nest and party.target_nest.valid then
            -- Update target health continuously
            local target = party.target_nest
            if target.valid and target.health > 0 then
                party.target_health = target.health
            else
                -- Target is dead, reform
                party.target_nest = nil
                party.attack_initiated = false
                party.scout_sent = false
                return
            end
            
            -- Calculate average damage of all bots in party (including scout)
            local total_damage = 0
            local bot_count = 0
            for _, member in ipairs(members) do
                if member.entity and member.entity.valid then
                    local tier_config = config.tier_configs[member.entity.name] or config.tier_configs["creeperbot-mk1"]
                    total_damage = total_damage + tier_config.damage
                    bot_count = bot_count + 1
                end
            end
            
            local average_damage = bot_count > 0 and (total_damage / bot_count) or 200
            
            -- Calculate required bots: ceil(target_health / average_damage) with 20% safety margin
            local required_bots = math.ceil((party.target_health / average_damage) * 1.2)
            
            -- Count how many bots are already attacking (in approaching or exploding state, including scout)
            local attacking_count = 0
            for _, member in pairs(storage.creeperbots or {}) do
                if member.party_id == creeper.party_id and 
                   member.entity and member.entity.valid and
                   (member.state == "approaching" or member.state == "exploding") and
                   member.target and member.target.valid and
                   member.target == target then
                    attacking_count = attacking_count + 1
                end
            end
            
            -- Send more bots if needed (check every 30 ticks to avoid spam)
            if not party.last_bot_send_tick or event.tick >= party.last_bot_send_tick + 30 then
                local bots_to_send = required_bots - attacking_count
                
                if bots_to_send > 0 then
                    -- Find available bots to send (excluding scout and leader)
                    local available_bots = {}
                    for _, member in ipairs(members) do
                        if member.entity and member.entity.valid and 
                           member.state == "preparing_to_attack" and 
                           member.unit_number ~= party.scout_unit_number and
                           not member.is_leader then
                            table.insert(available_bots, member)
                        end
                    end
                    
                    -- Send bots up to the required count
                    local sent_count = 0
                    for _, bot in ipairs(available_bots) do
                        if sent_count >= bots_to_send then break end
                        
                        -- Send bot to attack
                        bot.target = target
                        bot.target_position = target.position
                        bot.target_health = target.health
                        bot.preparing_to_attack_initialized = nil
                        bot.entity.follow_target = nil
                        bot.entity.autopilot_destination = nil
                        bot.state = "approaching"
                        update_color(bot.entity, "approaching")
                        
                        -- Path to target
                        request_multiple_paths(bot.entity.position, target.position, party, surface, bot.unit_number)
                        
                        sent_count = sent_count + 1
                    end
                    
                    party.last_bot_send_tick = event.tick
                end
            end
        end
    end

    -- ============================================
    -- PHASE 3A: GUARDS STOP BEING GUARDS (60 ticks after distractor)
    -- ============================================
    -- Guards stop being guards 60 ticks after distractor is sent
    -- Guards are either: 1) bots with is_guard=true, or 2) remaining distractors in guard positions
    if party.attack_initiated and 
       party.attack_start_tick and 
       event.tick >= party.attack_start_tick + 60 and
       event.tick < party.attack_start_tick + 120 then
        -- Check if this is a guard (either is_guard flag or remaining distractor in guard position)
        local is_guard_bot = false
        if creeper.is_guard or creeper.state == "guard" then
            is_guard_bot = true
        elseif creeper.is_distractor and creeper.state == "preparing_to_attack" then
            -- This is a remaining distractor that's still in guard position
            -- Check if it's in a guard position (within 10 tiles of leader)
            if leader_pos then
                local dist_to_leader = calculate_distance(position, leader_pos)
                if dist_to_leader <= 10 then
                    is_guard_bot = true
                end
            end
        end
        
        if is_guard_bot and not (creeper.is_distractor and creeper.state == "distractor") then
            -- Clear guard status - guards will move in Phase 3B
            creeper.is_guard = false
            -- If this is a remaining distractor (not the active one), clear distractor flag
            if creeper.is_distractor and creeper.state == "preparing_to_attack" then
                creeper.is_distractor = false
            end
            if creeper.state == "guard" then
                creeper.state = "preparing_to_attack"
            end
            -- Clear movement to prepare for attack
            entity.follow_target = nil
            entity.autopilot_destination = nil
            if storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number] then
                storage.scheduled_autopilots[creeper.unit_number] = nil
            end
        end
    end

    -- ============================================
    -- PHASE 3B: FALLBACK - SEND REMAINING BOTS (If target still alive after initial wave)
    -- ============================================
    -- Only send remaining bots if target is still alive and we haven't sent enough
    -- This is a fallback in case the calculation-based system didn't send enough bots
    if party.attack_initiated and 
       party.attack_start_tick and 
       party.target_nest and
       party.target_nest.valid and
       party.target_nest.health > 0 and
       event.tick >= party.attack_start_tick + 180 and  -- Wait 3 seconds after scout
       creeper.state == "preparing_to_attack" and
       not creeper.is_leader then
       
        -- Re-get members list to ensure it's current
        -- Include all bots except the active distractor (in "distractor" state)
        local current_members = {}
        for unit_number, member in pairs(storage.creeperbots or {}) do
            if member.party_id == creeper.party_id and 
               member.entity and 
               member.entity.valid and 
               member.state ~= "distractor" then  -- Exclude only the active distractor
                table.insert(current_members, member)
            end
        end
        -- Get the target nest
        local target = party.target_nest
        if not target or not target.valid then
            -- Re-find target
            local target_type
            target, target_type = behavior_utils.scan_for_enemies(leader_pos, surface, config.tier_configs[entity.name].max_targeting)
            if target and target_type == "nest" then
                party.target_nest = target
            else
                -- No target - return to grouping state to rejoin party
                creeper.target = nil
                creeper.target_position = nil
                creeper.target_health = nil
                if party then 
                    party.shared_target = nil
                    party.target_nest = nil
                    party.attack_initiated = false
                    party.scout_sent = false
                end
                
                -- Clear movement state
                entity.follow_target = nil
                entity.autopilot_destination = nil
                if storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] then
                    storage.scheduled_autopilots[entity.unit_number] = nil
                end
                
                -- Reset grouping state to rejoin party
                creeper.preparing_to_attack_initialized = nil
                creeper.grouping_initialized = false
                
                -- Transition to grouping state to rejoin party
                creeper.state = "grouping"
                update_color(entity, "grouping")
                return
            end
        end

        -- Find all spawners near the nest
        local spawners = surface.find_entities_filtered({
            type = "unit-spawner",
            position = target.position,
            radius = 20,
            force = "enemy"
        })
        
        -- Get available spawners
        local spawner_targets = {}
        for _, spawner in ipairs(spawners) do
            if spawner.valid and spawner.health > 0 then
                table.insert(spawner_targets, spawner)
            end
        end
        
        -- Assign target to this bot
        local assigned_target = nil
        if #spawner_targets > 0 then
            -- Find a spawner that isn't already assigned to too many bots
            local spawner_assignments = {}
            for _, member in ipairs(current_members) do
                if member.assigned_target and member.assigned_target.valid then
                    local unit_num = member.assigned_target.unit_number
                    spawner_assignments[unit_num] = (spawner_assignments[unit_num] or 0) + 1
                end
            end
            
            -- Find spawner with fewest assignments
            local min_assignments = math.huge
            for _, spawner in ipairs(spawner_targets) do
                local assignments = spawner_assignments[spawner.unit_number] or 0
                if assignments < min_assignments then
                    min_assignments = assignments
                    assigned_target = spawner
                end
            end
            
            -- If no spawner found (shouldn't happen), use first one
            if not assigned_target then
                assigned_target = spawner_targets[1]
            end
        else
            -- No spawners found, use main nest
            assigned_target = target
        end

        -- CRITICAL: Clear all movement state and path directly to nest
        -- Clear follow_target aggressively - this prevents weird movement
        entity.follow_target = nil
        entity.autopilot_destination = nil
        -- Clear all autopilot destinations (autopilot_destinations is read-only, so we clear current destination repeatedly)
        local attempts = 0
        while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
            entity.autopilot_destination = nil
            attempts = attempts + 1
        end
        if storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number] then
            storage.scheduled_autopilots[creeper.unit_number] = nil
        end
        
        -- Clear guard status - guards are now attackers
        creeper.is_guard = false
        
        -- Clear any follower target assignments
        if party and party.follower_targets then
            party.follower_targets[creeper.unit_number] = nil
        end

        -- Assign target and transition to approaching
        creeper.target = assigned_target
        creeper.target_position = assigned_target.position
        creeper.target_health = assigned_target.health
        creeper.assigned_target = assigned_target
        creeper.preparing_to_attack_initialized = nil
        creeper.state = "approaching"
        update_color(entity, "approaching")

        -- Use request_multiple_paths to handle obstacles (cliffs, water, etc.)
        request_multiple_paths(position, assigned_target.position, party, surface, creeper.unit_number)
    end
end

return preparing_to_attack_state
