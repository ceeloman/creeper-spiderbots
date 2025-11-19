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
        creeper.state = "grouping"
        update_color(entity, "grouping")
        return
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

    -- Leader clears movement during preparation phase only
    if creeper.is_leader and not party.attack_initiated then
        entity.autopilot_destination = nil
        entity.follow_target = nil
        if storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] then
            storage.scheduled_autopilots[entity.unit_number] = nil
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
        -- PHASE 2: SEND DISTRACTOR (After positioning)
        -- ============================================
        if event.tick >= party.preparation_start_tick + 240 and 
           (not party.last_distractor_election_tick or event.tick >= party.last_distractor_election_tick + 1200) then
            
            local target, target_type = behavior_utils.scan_for_enemies(leader_pos, surface, config.tier_configs[entity.name].max_targeting)
            
            if target and target_type == "nest" then
                -- Find closest distractor in guard position
                local closest_distractor = nil
                local min_distance = math.huge
                
                for i, distractor in ipairs(distractors) do
                    if distractor.entity and distractor.entity.valid and distractor.state == "preparing_to_attack" then
                        local pos = guard_positions[i] or {angle = 180, radius = 3}
                        local guard_pos = {
                            x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                            y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                        }
                        local dist_to_guard = calculate_distance(distractor.entity.position, guard_pos)
                        
                        -- Must be in guard position (within 3 tiles)
                        if dist_to_guard < 3 then
                            local dist_to_target = calculate_distance(distractor.entity.position, target.position)
                            if dist_to_target < min_distance then
                                min_distance = dist_to_target
                                closest_distractor = distractor
                            end
                        end
                    end
                end
                
                -- Send distractor
                if closest_distractor then
                    -- Calculate approach direction from distractor to nest
                    -- This gives us the direction the distractor is MOVING (toward nest)
                    local dx = target.position.x - closest_distractor.entity.position.x
                    local dy = target.position.y - closest_distractor.entity.position.y
                    local approach_angle = math.deg(math.atan2(dy, dx))
                    if approach_angle < 0 then approach_angle = approach_angle + 360 end
                    
                    -- Calculate diversion position: 5 tiles away from nest
                    -- Based on approach direction, move perpendicular (not continuing in same direction)
                    local diversion_angle = nil
                    local random = game.create_random_generator()
                    
                    if approach_angle >= 315 or approach_angle < 45 then
                        -- Approaching from east (moving west, angle ~0° or 360°)
                        -- Move northwest (315°) or southwest (225°) - NOT continuing west
                        diversion_angle = random(1, 2) == 1 and 315 or 225
                    elseif approach_angle >= 45 and approach_angle < 135 then
                        -- Approaching from north (moving south, angle ~90°)
                        -- Move northeast (45°) or northwest (315°)
                        diversion_angle = random(1, 2) == 1 and 45 or 315
                    elseif approach_angle >= 135 and approach_angle < 225 then
                        -- Approaching from west (moving east, angle ~180°)
                        -- Move southwest (225°) or southeast (135°)
                        diversion_angle = random(1, 2) == 1 and 225 or 135
                    elseif approach_angle >= 225 and approach_angle < 315 then
                        -- Approaching from south (moving north, angle ~270°)
                        -- Move southwest (225°) or southeast (135°)
                        diversion_angle = random(1, 2) == 1 and 225 or 135
                    else
                        -- Default: move 90 degrees perpendicular
                        diversion_angle = (approach_angle + 90) % 360
                    end
                    
                    -- Calculate diversion position: 5 tiles from nest at calculated angle
                    local diversion_pos = {
                        x = math.floor(target.position.x + math.cos(math.rad(diversion_angle)) * 5),
                        y = math.floor(target.position.y + math.sin(math.rad(diversion_angle)) * 5)
                    }
                    
                    closest_distractor.entity.autopilot_destination = nil
                    closest_distractor.state = "distractor"
                    closest_distractor.target = target
                    closest_distractor.target_position = target.position
                    closest_distractor.diversion_position = diversion_pos
                    distractor_state_module.handle_distractor_state(
                        closest_distractor, 
                        event, 
                        closest_distractor.entity.position, 
                        closest_distractor.entity, 
                        surface, 
                        config.tier_configs[entity.name], 
                        party
                    )
                    closest_distractor.distract_start_tick = event.tick
                    closest_distractor.distract_end_tick = event.tick + 600
                    party.last_distractor_election_tick = event.tick
                    
                    -- CRITICAL: Mark attack as initiated and set delay for other bots
                    -- Other bots wait 120 ticks (2 seconds) to give distractor time to run in
                    party.attack_initiated = true
                    party.attack_start_tick = event.tick
                    party.target_nest = target
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
    -- PHASE 3B: ASSIGN TARGETS AND PATH TO NESTS (After distractor sent + delay)
    -- ============================================
    -- Assign targets to all bots except the active distractor (leader, former guards, and remaining distractors included)
    -- Wait 120 ticks (2 seconds) after distractor is sent to give it time to run in
    -- Exclude only the active distractor (in "distractor" state), not remaining distractors in "preparing_to_attack"
    if party.attack_initiated and 
       party.attack_start_tick and 
       event.tick >= party.attack_start_tick + 120 and
       creeper.state ~= "distractor" and  -- Exclude only the active distractor
       (creeper.state == "preparing_to_attack" or creeper.state == "guard") then
       
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
                -- No target, reform into formation (waking state)
                creeper.target = nil
                creeper.target_position = nil
                creeper.target_health = nil
                if party then party.shared_target = nil end
                
                -- Clear movement state
                entity.follow_target = nil
                entity.autopilot_destination = nil
                if storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] then
                    storage.scheduled_autopilots[entity.unit_number] = nil
                end
                
                -- Reset waking state to start fresh
                creeper.waking_initialized = nil
                
                -- Transition to waking state to reform
                creeper.state = "waking"
                update_color(entity, "waking")
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
        creeper.state = "approaching"
        update_color(entity, "approaching")

        -- Use request_multiple_paths to handle obstacles (cliffs, water, etc.)
        request_multiple_paths(position, assigned_target.position, party, surface, creeper.unit_number)
    end
end

return preparing_to_attack_state
