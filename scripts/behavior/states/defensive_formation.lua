-- Creeperbots - Defensive Formation State Handler
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0
-- Triggered when enemies are detected during scouting
-- Leader stops, bots form defensive formation around leader
-- Guards/bots can attack enemies
-- Returns to scouting when enemies are cleared

local config = require "scripts.behavior.config"

local defensive_formation_state = {}

function defensive_formation_state.handle_defensive_formation_state(creeper, event, position, entity, surface, tier, party)
    update_color(entity, creeper.is_guard and "guard" or "defensive_formation")
    
    -- Check if bot is being attacked by bugs - if so, explode immediately
    local is_being_attacked = false
    
    -- Method 1: Track health changes (only trigger on significant damage, > 1% or 5 health)
    if not creeper.last_health then
        creeper.last_health = entity.health
    end
    -- Track initial/max health when first seen
    if not creeper.max_health then
        creeper.max_health = entity.health
    end
    -- Update max_health if current health exceeds it (healing/repair)
    if entity.health > creeper.max_health then
        creeper.max_health = entity.health
    end
    local health_loss = creeper.last_health - entity.health
    local health_threshold = math.max(5, creeper.max_health * 0.01)  -- 1% of max health or 5, whichever is larger
    if health_loss > health_threshold then
        is_being_attacked = true
    end
    creeper.last_health = entity.health
    
    -- Method 2: Check for very close enemies (within 3 tiles) that are actually attacking
    -- Only check if we haven't already detected an attack via health loss
    if not is_being_attacked then
        local nearby_enemies = surface.find_entities_filtered({
            type = "unit",
            position = position,
            radius = 3,
            force = "enemy"
        })
        -- Check if any enemy is actually moving toward us or very close
        for _, enemy in ipairs(nearby_enemies) do
            if enemy.valid then
                local dist = calculate_distance(position, enemy.position)
                if dist <= 2.5 then  -- Very close, likely attacking
                    is_being_attacked = true
                    break
                end
            end
        end
    end
    
    -- If being attacked, transition to exploding
    if is_being_attacked then
        -- Find nearest enemy as target
        local nearby_enemies = surface.find_entities_filtered({
            type = "unit",
            position = position,
            radius = 10,
            force = "enemy"
        })
        if #nearby_enemies > 0 and nearby_enemies[1].valid then
            creeper.target = nearby_enemies[1]
            creeper.target_position = nearby_enemies[1].position
        else
            creeper.target = nil
            creeper.target_position = position
        end
        creeper.state = "exploding"
        update_color(entity, "exploding")
        return
    end
    
    if not party then
        creeper.state = "waking"
        update_color(entity, "waking")
        return
    end
    
    -- Ensure leader stays stopped (clear all autopilot destinations every tick)
    -- Check both is_leader flag and unit_number match for reliability
    if (creeper.is_leader or (party and creeper.unit_number == party.grouping_leader)) and entity.valid then
        entity.autopilot_destination = nil
        entity.follow_target = nil
        -- Clear all autopilot destinations (autopilot_destinations is read-only, so we clear current destination repeatedly)
        local attempts = 0
        while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
            entity.autopilot_destination = nil
            attempts = attempts + 1
        end
        if storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number] then
            storage.scheduled_autopilots[creeper.unit_number] = nil
        end
        -- Also clear autopilot queue
        if storage.autopilot_queue and storage.autopilot_queue[creeper.unit_number] then
            storage.autopilot_queue[creeper.unit_number] = nil
        end
    end
    
    -- Get party members
    local members = {}
    for unit_number, member in pairs(storage.creeperbots or {}) do
        if member.party_id == creeper.party_id and member.entity and member.entity.valid then
            table.insert(members, member)
        end
    end
    
    if #members == 0 then
        creeper.state = "waking"
        update_color(entity, "waking")
        return
    end
    
    -- Get leader position
    local leader = storage.creeperbots[party.grouping_leader]
    if not leader or not leader.entity or not leader.entity.valid then
        -- No leader, return to scouting (will promote new leader)
        party.state = "scouting"
        for _, member in ipairs(members) do
            if member.state == "defensive_formation" then
                member.state = "scouting"
                update_color(member.entity, member.is_guard and "guard" or "scouting")
            end
        end
        return
    end
    
    local leader_pos = leader.entity.position
    
    -- Initialize formation timer if not set
    if not party.defensive_formation_start_tick then
        party.defensive_formation_start_tick = event.tick
    end
    
    local formation_time_elapsed = event.tick - party.defensive_formation_start_tick
    local formation_wait_time = 60  -- Wait 60 ticks before assuming guard positions
    
    -- SIMPLIFIED: Just check if enemies are cleared - return to scouting when all dead
    -- Scan within 60 tiles of leader
    local nearby_enemies = surface.find_entities_filtered({
        type = {"unit", "turret", "unit-spawner"},
        position = leader_pos,
        radius = 60,  -- Check within 60 tiles of leader
        force = "enemy"
    })
    
    -- Only count enemies that are actually alive (valid and health > 0)
    local active_enemies = {}
    for _, enemy in ipairs(nearby_enemies) do
        if enemy.valid and enemy.health > 0 then
            table.insert(active_enemies, enemy)
        end
    end
    
    -- COMMENTED OUT FOR TESTING: Don't return to scouting, just stay in defensive formation
    --[[
    -- If no active enemies (all dead), return to scouting
    if #active_enemies == 0 then
        game.print("DEBUG: No active enemies (all dead), returning to scouting")
        party.state = "scouting"
        party.defensive_formation = false
        party.last_defensive_scan_tick = nil
        for _, member in ipairs(members) do
            if member.state == "defensive_formation" then
                member.state = "scouting"
                update_color(member.entity, member.is_guard and "guard" or "scouting")
                -- Clear defensive targets
                member.defensive_target = nil
            end
        end
        return
    end
    --]]
    
    -- Handle defensive_target attack movement (for bots assigned to attack units)
    if creeper.defensive_target then
        -- CRITICAL: Clear follow_target aggressively - bot is attacking, should NOT follow anyone
        -- Clear it multiple times to ensure it's cleared
        for i = 1, 5 do
            pcall(function() entity.follow_target = nil end)
        end
        
        if creeper.defensive_target.valid and creeper.defensive_target.health > 0 then
            local dist = calculate_distance(position, creeper.defensive_target.position)
            if dist <= 2 then
                -- Close enough - explode
                creeper.target = creeper.defensive_target
                creeper.target_position = creeper.defensive_target.position
                creeper.state = "exploding"
                update_color(entity, "exploding")
                creeper.defensive_target = nil
                return
            else
                -- Move toward target using autopilot only
                if not entity.autopilot_destination or 
                   calculate_distance(entity.position, creeper.defensive_target.position) > 5 then
                    entity.autopilot_destination = nil
                    -- Clear all autopilot destinations
                    local attempts = 0
                    while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
                        entity.autopilot_destination = nil
                        attempts = attempts + 1
                    end
                    if storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number] then
                        storage.scheduled_autopilots[creeper.unit_number] = nil
                    end
                    if storage.autopilot_queue and storage.autopilot_queue[creeper.unit_number] then
                        storage.autopilot_queue[creeper.unit_number] = nil
                    end
                    entity.add_autopilot_destination(creeper.defensive_target.position)
                end
            end
        else
            -- Target is dead or invalid - clear it and return to formation
            creeper.defensive_target = nil
            entity.autopilot_destination = nil
            -- Clear follow_target multiple times
            for i = 1, 5 do
                pcall(function() entity.follow_target = nil end)
            end
        end
        -- Return early - bot is attacking, don't do positioning
        return
    end
    
    -- Handle returning attackers - they should rejoin as guards
    -- Check if bot was attacking but defensive_target is now cleared (target dead or invalid)
    if creeper.defensive_target == nil and not creeper.is_leader and not creeper.is_guard then
        -- Calculate required guard count
        local required_guard_count = 0
        if #members >= 6 then required_guard_count = 5
        elseif #members >= 5 then required_guard_count = 4
        elseif #members >= 4 then required_guard_count = 3
        elseif #members >= 3 then required_guard_count = 2
        elseif #members >= 2 then required_guard_count = 1
        end
        
        -- Count current guards (not attacking)
        local current_guard_count = 0
        for _, member in ipairs(members) do
            if member.is_guard and member.entity and member.entity.valid and not member.defensive_target then
                current_guard_count = current_guard_count + 1
            end
        end
        
        -- If we need more guards, promote this returning attacker
        if current_guard_count < required_guard_count then
            creeper.is_guard = true
            update_color(entity, "guard")
            game.print("DEBUG: Returning attacker " .. creeper.unit_number .. " promoted to guard")
        end
    end
    
    -- Calculate required guard count
    local required_guard_count = 0
    if #members >= 6 then required_guard_count = 5
    elseif #members >= 5 then required_guard_count = 4
    elseif #members >= 4 then required_guard_count = 3
    elseif #members >= 3 then required_guard_count = 2
    elseif #members >= 2 then required_guard_count = 1
    end
    
    -- Count current guards (not attacking)
    local current_guard_count = 0
    local active_guards = {}

    -- First, show ALL members that are marked as guards (before filtering)
    game.print("DEBUG: Checking all members marked as guards:")
    for _, member in ipairs(members) do
        if member and member.is_guard then
            local has_entity = member.entity ~= nil
            local entity_valid = has_entity and member.entity.valid or false
            local has_defensive_target = member.defensive_target ~= nil
            game.print("DEBUG: Guard " .. member.unit_number .. " | has_entity: " .. tostring(has_entity) .. " | entity_valid: " .. tostring(entity_valid) .. " | has_defensive_target: " .. tostring(has_defensive_target))
        end
    end

    -- Now build the active_guards list (only guards that pass all criteria)
    for _, member in ipairs(members) do
        if member.is_guard and member.entity and member.entity.valid and not member.defensive_target then
            current_guard_count = current_guard_count + 1
            table.insert(active_guards, member)
            game.print("DEBUG: Active guard " .. member.unit_number .. " (current guard count: " .. current_guard_count .. ")")
        end
    end
    
    -- If too many guards, demote the lowest tier guard
    game.print("DEBUG: Guard count check - current_guard_count: " .. current_guard_count .. ", required_guard_count: " .. required_guard_count)
    if current_guard_count > required_guard_count then
        game.print("DEBUG: Too many guards, demoting excess guards")
        -- Sort guards by tier (lowest first)
        table.sort(active_guards, function(a, b) return a.tier < b.tier end)
        -- Demote excess guards (starting with lowest tier)
        local excess = current_guard_count - required_guard_count
        game.print("DEBUG: Demoting " .. excess .. " guards (excess)")
        for i = 1, excess do
            if active_guards[i] then
                game.print("DEBUG: Demoting guard " .. active_guards[i].unit_number .. " (tier: " .. active_guards[i].tier .. ")")
                active_guards[i].is_guard = false
                update_color(active_guards[i].entity, "defensive_formation")
                game.print("DEBUG: Demoted guard " .. active_guards[i].unit_number .. " (too many guards)")
            end
        end
    else
        game.print("DEBUG: Guard count OK - not demoting any guards")
    end
    
    -- All non-leader, non-attacking bots should follow the leader (during wait period)
    if not creeper.is_leader and not creeper.defensive_target and leader.entity and leader.entity.valid then
        -- During wait period (first 60 ticks), all bots follow leader
        if formation_time_elapsed < formation_wait_time then
            if creeper.is_guard then
                local guard_ids = {}
                for i, guard in ipairs(active_guards) do
                    table.insert(guard_ids, tostring(guard.unit_number))
                end
                game.print("DEBUG: WAIT PERIOD - Guard " .. creeper.unit_number .. " following leader (elapsed: " .. formation_time_elapsed .. "/" .. formation_wait_time .. ") | Active guards: " .. #active_guards .. " | IDs: [" .. table.concat(guard_ids, ", ") .. "]")
            end
            -- Clear autopilot destinations first
            entity.autopilot_destination = nil
            -- Clear all autopilot destinations
            local attempts = 0
            while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
                entity.autopilot_destination = nil
                attempts = attempts + 1
            end
            
            -- Clear follow_target first (multiple times to ensure it's cleared), then set it to leader
            for i = 1, 5 do
                pcall(function() entity.follow_target = nil end)
            end
            
            local success, err = pcall(function()
                entity.follow_target = leader.entity
            end)
            if not success then
                game.print("DEBUG: Failed to set follow_target for unit " .. creeper.unit_number .. ": " .. tostring(err))
            end
        else
            -- After wait period, guards take positions, followers continue following
            -- Log all party members and their is_guard status BEFORE the guard check
            game.print("DEBUG: AFTER WAIT PERIOD - Checking all party members for is_guard status:")
            game.print("DEBUG: required_guard_count: " .. required_guard_count)
            local guards_still_active = 0
            local guards_in_defensive_formation = 0
            for _, member in ipairs(members) do
                if member then
                    local is_guard_status = member.is_guard or false
                    local is_in_defensive_formation = (member.state == "defensive_formation")
                    if is_guard_status then
                        guards_still_active = guards_still_active + 1
                        if is_in_defensive_formation then
                            guards_in_defensive_formation = guards_in_defensive_formation + 1
                        end
                    end
                    local has_entity = member.entity ~= nil
                    local entity_valid = has_entity and member.entity.valid or false
                    local has_defensive_target = member.defensive_target ~= nil
                    -- Only log guards to reduce spam
                    if is_guard_status then
                        game.print("DEBUG: Guard " .. member.unit_number .. " | is_guard: " .. tostring(is_guard_status) .. " | state: " .. tostring(member.state) .. " | in_defensive_formation: " .. tostring(is_in_defensive_formation) .. " | has_entity: " .. tostring(has_entity) .. " | entity_valid: " .. tostring(entity_valid) .. " | has_defensive_target: " .. tostring(has_defensive_target))
                    end
                end
            end
            game.print("DEBUG: Total guards still active: " .. guards_still_active)
            game.print("DEBUG: Guards in defensive_formation state: " .. guards_in_defensive_formation)
            game.print("DEBUG: Current creeper " .. creeper.unit_number .. " | is_guard: " .. tostring(creeper.is_guard) .. " | state: " .. tostring(creeper.state))
            
            if creeper.is_guard then
                game.print("DEBUG: STAGE 1 - Guard " .. creeper.unit_number .. " entering positioning phase")
                
                -- First, list all members with is_guard flag
                local guard_ids = {}
                for _, member in ipairs(members) do
                    if member and member.is_guard then
                        table.insert(guard_ids, tostring(member.unit_number))
                    end
                end
                game.print("DEBUG: Members with is_guard=true: [" .. table.concat(guard_ids, ", ") .. "] (count: " .. #guard_ids .. ")")
                
                -- Guard positioning after wait period (similar to grouping state)
                local guards = {}
                for _, member in ipairs(members) do
                    if member.is_guard and member.entity and member.entity.valid and not member.defensive_target then
                        table.insert(guards, member)
                    end
                end
                
                -- List guard IDs that passed all criteria
                local passed_guard_ids = {}
                for _, guard in ipairs(guards) do
                    table.insert(passed_guard_ids, tostring(guard.unit_number))
                end
                game.print("DEBUG: Guards that passed criteria: [" .. table.concat(passed_guard_ids, ", ") .. "] (count: " .. #guards .. ")")
                game.print("DEBUG: STAGE 2 - Guard " .. creeper.unit_number .. " found " .. #guards .. " total guards")
                
                local guard_positions = {}
                local actual_guard_count = #guards
                if actual_guard_count == 1 then
                    guard_positions = {{angle = 180, radius = 3}}
                elseif actual_guard_count == 2 then
                    guard_positions = {{angle = 90, radius = 4}, {angle = 270, radius = 4}}
                elseif actual_guard_count == 3 then
                    guard_positions = {{angle = 120, radius = 5}, {angle = 240, radius = 5}, {angle = 0, radius = 5}}
                elseif actual_guard_count == 4 then
                    guard_positions = {{angle = 45, radius = 6}, {angle = 135, radius = 6}, {angle = 225, radius = 6}, {angle = 315, radius = 6}}
                elseif actual_guard_count >= 5 then
                    guard_positions = {{angle = 0, radius = 8}, {angle = 72, radius = 8}, {angle = 144, radius = 8}, {angle = 216, radius = 8}, {angle = 288, radius = 8}}
                end
                
                if actual_guard_count > 0 then
                    game.print("DEBUG: STAGE 3 - Guard " .. creeper.unit_number .. " checking for guard index")
                    -- Find this guard's index
                    local guard_index = nil
                    for i, guard in ipairs(guards) do
                        if guard.unit_number == creeper.unit_number then
                            guard_index = i
                            game.print("DEBUG: STAGE 3 SUCCESS - Guard " .. creeper.unit_number .. " found at index " .. guard_index)
                            break
                        end
                    end
                    
                    if guard_index then
                        local pos = guard_positions[guard_index] or {angle = 180, radius = 3}
                        local dest_pos = {
                            x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                            y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                        }
                        local dist_to_current = math.sqrt((dest_pos.x - entity.position.x)^2 + (dest_pos.y - entity.position.y)^2)
                        
                        game.print("DEBUG: STAGE 4 - Guard " .. creeper.unit_number .. " calculating position (dist: " .. string.format("%.1f", dist_to_current) .. ")")
                        -- CRITICAL: ALWAYS clear follow_target when entering positioning phase (guards were following leader during wait period)
                        -- This must happen for ALL guards, not just ones that need to move
                        if entity.follow_target then
                            game.print("DEBUG: STAGE 4a - Guard " .. creeper.unit_number .. " clearing follow_target (was: " .. tostring(entity.follow_target ~= nil) .. ")")
                            for i = 1, 5 do
                                pcall(function() entity.follow_target = nil end)
                            end
                            game.print("DEBUG: STAGE 4a - Guard " .. creeper.unit_number .. " follow_target cleared (now: " .. tostring(entity.follow_target ~= nil) .. ")")
                        else
                            game.print("DEBUG: STAGE 4a - Guard " .. creeper.unit_number .. " no follow_target to clear")
                        end
                        
                        -- Clear autopilot destinations if they exist
                        if entity.autopilot_destination or (#entity.autopilot_destinations > 0) then
                            game.print("DEBUG: STAGE 4b - Guard " .. creeper.unit_number .. " clearing autopilot destinations")
                            entity.autopilot_destination = nil
                            -- Clear scheduled autopilots and queue
                            if storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number] then
                                storage.scheduled_autopilots[creeper.unit_number] = nil
                            end
                            if storage.autopilot_queue and storage.autopilot_queue[creeper.unit_number] then
                                storage.autopilot_queue[creeper.unit_number] = nil
                            end
                            game.print("DEBUG: STAGE 4b - Guard " .. creeper.unit_number .. " cleared movement targets")
                        else
                            game.print("DEBUG: STAGE 4b - Guard " .. creeper.unit_number .. " no autopilot destinations to clear")
                        end
                        
                        -- Early return if already in position and all movement targets cleared
                        if dist_to_current <= 1.5 and not entity.follow_target and not entity.autopilot_destination and (#entity.autopilot_destinations == 0) then
                            game.print("DEBUG: STAGE 4c - Guard " .. creeper.unit_number .. " already in position, skipping movement")
                            return
                        end
                        
                        game.print("DEBUG: STAGE 5 - Guard " .. creeper.unit_number .. " dist to position: " .. string.format("%.1f", dist_to_current))
                        
                        -- Only move if significantly out of position (> 1.5 tiles) to prevent micro-movements
                        -- Throttle movement requests (similar to grouping state)
                        local can_move = not creeper.last_path_request or creeper.last_path_request == 0 or event.tick >= creeper.last_path_request + 120
                        game.print("DEBUG: STAGE 6 - Guard " .. creeper.unit_number .. " can_move: " .. tostring(can_move) .. " (last_path_request: " .. tostring(creeper.last_path_request) .. ", tick: " .. event.tick .. ")")
                        
                        if dist_to_current > 1.5 then
                            game.print("DEBUG: STAGE 7 - Guard " .. creeper.unit_number .. " needs to move (dist > 1.5)")
                            if can_move then
                                game.print("DEBUG: STAGE 7a - Guard " .. creeper.unit_number .. " can move, checking for active destinations")
                                -- Check if guard is already moving toward destination
                                local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number]
                                local has_active_destination = entity.autopilot_destination ~= nil or (#entity.autopilot_destinations > 0)
                                game.print("DEBUG: STAGE 7b - Guard " .. creeper.unit_number .. " has_active_destination: " .. tostring(has_active_destination) .. ", queue: " .. tostring(queue ~= nil))
                                
                                -- Only set destination if not already moving or scheduled
                                if queue and event.tick < queue.tick then
                                    game.print("DEBUG: STAGE 7c - Guard " .. creeper.unit_number .. " has scheduled destination, skipping")
                                elseif not has_active_destination then
                                    game.print("DEBUG: STAGE 7d - Guard " .. creeper.unit_number .. " setting destination to (" .. dest_pos.x .. "," .. dest_pos.y .. ")")
                                    -- Set destination
                                    local success, err = pcall(function()
                                        entity.add_autopilot_destination(dest_pos)
                                    end)
                                    if success then
                                        creeper.last_path_request = event.tick
                                        game.print("DEBUG: STAGE 7e SUCCESS - Guard " .. creeper.unit_number .. " destination set")
                                    else
                                        game.print("DEBUG: STAGE 7e FAILED - Guard " .. creeper.unit_number .. " failed to set destination: " .. tostring(err))
                                    end
                                else
                                    game.print("DEBUG: STAGE 7c - Guard " .. creeper.unit_number .. " already has active destination, skipping")
                                end
                            else
                                game.print("DEBUG: STAGE 7a FAILED - Guard " .. creeper.unit_number .. " cannot move (throttled)")
                            end
                        else
                            game.print("DEBUG: STAGE 7 - Guard " .. creeper.unit_number .. " already in position (dist <= 1.5)")
                        end
                    else
                        game.print("DEBUG: STAGE 3 FAILED - Guard " .. creeper.unit_number .. " not found in guards list (count: " .. actual_guard_count .. ")")
                    end
                else
                    game.print("DEBUG: STAGE 2 FAILED - Guard " .. creeper.unit_number .. " no guards found (actual_guard_count: 0)")
                end
            else
                -- Follower continues following leader after wait period
                -- Clear autopilot destinations first
                entity.autopilot_destination = nil
                -- Clear all autopilot destinations
                local attempts = 0
                while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
                    entity.autopilot_destination = nil
                    attempts = attempts + 1
                end
                
                -- Clear follow_target first (multiple times to ensure it's cleared), then set it to leader
                for i = 1, 5 do
                    pcall(function() entity.follow_target = nil end)
                end
                
                local success, err = pcall(function()
                    entity.follow_target = leader.entity
                end)
                if not success then
                    game.print("DEBUG: Failed to set follow_target for unit " .. creeper.unit_number .. ": " .. tostring(err))
                end
            end
        end
    end
    
    -- COMMENTED OUT: All complex enemy assignment and attack logic
    --[[
    -- Periodic scanning for enemies (every 60 ticks, only by leader)
    local should_scan = false
    local is_leader = creeper.is_leader or (party and creeper.unit_number == party.grouping_leader)
    if is_leader then
        if not party.last_defensive_scan_tick then
            party.last_defensive_scan_tick = event.tick
            should_scan = true
        elseif event.tick >= party.last_defensive_scan_tick + 60 then
            party.last_defensive_scan_tick = event.tick
            should_scan = true
        end
    end
    
    -- If leader is scanning, check for untargeted enemies and assign bots
    if should_scan and is_leader then
        game.print("DEBUG: Leader scanning for enemies within 60 tiles...")
        game.print("DEBUG: Found " .. #active_enemies .. " active enemies")
        
        -- Check each enemy and assign bots if needed
        for _, enemy in ipairs(active_enemies) do
            if enemy.valid and enemy.health > 0 then
                -- Count how many bots are already targeting this enemy
                local attacking_count = 0
                for _, member in ipairs(members) do
                    if (member.defensive_target and member.defensive_target.valid and member.defensive_target.unit_number == enemy.unit_number) or
                       (member.guard_target and member.guard_target.valid and member.guard_target.unit_number == enemy.unit_number) then
                        attacking_count = attacking_count + 1
                    end
                end
                
                game.print("DEBUG: Enemy " .. enemy.unit_number .. " has " .. attacking_count .. " bots attacking")
                
                -- If enemy is not being targeted, assign a bot to attack it
                if attacking_count == 0 then
                    game.print("DEBUG: Enemy " .. enemy.unit_number .. " needs assignment")
                    
                    -- Get available bots (not currently attacking anything, EXCLUDE LEADER)
                    local available_bots = {}
                    for unit_number, member in pairs(storage.creeperbots or {}) do
                        local member_is_leader = member.is_leader or (party and member.unit_number == party.grouping_leader)
                        if member.party_id == creeper.party_id and 
                           member.entity and 
                           member.entity.valid and
                           not member_is_leader and  -- EXCLUDE LEADER
                           not member.defensive_target and
                           not member.target and  -- Don't assign if already approaching a nest
                           not member.guard_target then
                            table.insert(available_bots, member)
                        end
                    end
                    
                    if #available_bots > 0 then
                        -- Calculate how many bots needed based on enemy health
                        local average_damage = 200  -- Default, could be calculated from party
                        local bots_needed = math.ceil(enemy.health / average_damage)
                        if bots_needed < 1 then bots_needed = 1 end
                        
                        game.print("DEBUG: Enemy " .. enemy.unit_number .. " needs " .. bots_needed .. " bots (health: " .. enemy.health .. ", avg damage: " .. average_damage .. ")")
                        game.print("DEBUG: Found " .. #available_bots .. " available bots")
                        
                        -- Assign bots to attack
                        local assigned = 0
                        for _, bot in ipairs(available_bots) do
                            if assigned < bots_needed then
                                bot.defensive_target = enemy
                                update_color(bot.entity, "approaching")
                                game.print("DEBUG: Assigned bot " .. bot.unit_number .. " to enemy " .. enemy.unit_number)
                                assigned = assigned + 1
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Guard behavior - guards detect bugs and run towards them to explode
    -- This is separate from regular approaching logic - guards stay in defensive_formation state
    -- Check for enemies and assign guards only when needed
    if creeper.is_guard and not creeper.guard_target then
        -- Guard is not attacking - check for enemies that need guards
        local nearby_enemies = surface.find_entities_filtered({
            type = {"unit", "turret", "unit-spawner"},
            position = position,
            radius = 30,
            force = "enemy"
        })
        
        if #nearby_enemies > 0 and party then
            -- Find enemies that don't have guards assigned
            local unassigned_enemies = {}
            for _, enemy in ipairs(nearby_enemies) do
                if enemy.valid and enemy.health > 0 then
                    local has_guard = false
                    if party.guard_assignments then
                        for enemy_unit_number, guard_unit_number in pairs(party.guard_assignments) do
                            if enemy_unit_number == enemy.unit_number then
                                local guard_creeper = storage.creeperbots[guard_unit_number]
                                if guard_creeper and guard_creeper.entity and guard_creeper.entity.valid and
                                   guard_creeper.guard_target and guard_creeper.guard_target.valid then
                                    has_guard = true
                                    break
                                end
                            end
                        end
                    end
                    if not has_guard then
                        table.insert(unassigned_enemies, enemy)
                    end
                end
            end
            
            if #unassigned_enemies > 0 then
                -- Find closest unassigned enemy
                local closest_enemy = nil
                local min_dist = math.huge
                for _, enemy in ipairs(unassigned_enemies) do
                    local dist = calculate_distance(position, enemy.position)
                    if dist < min_dist then
                        min_dist = dist
                        closest_enemy = enemy
                    end
                end
                
                if closest_enemy then
                    -- Get all available guards (not currently attacking)
                    local available_guards = {}
                    if party then
                        for unit_number, member in pairs(storage.creeperbots or {}) do
                            if member.party_id == creeper.party_id and 
                               member.is_guard and 
                               member.entity and 
                               member.entity.valid and
                               (member.state == "defensive_formation" or member.state == "guard") and
                               not member.guard_target then
                                table.insert(available_guards, member)
                            end
                        end
                    end
                    
                    -- Find which guard is closest to the enemy
                    local closest_guard = nil
                    local closest_guard_dist = math.huge
                    for _, guard in ipairs(available_guards) do
                        if guard.entity and guard.entity.valid then
                            local dist = calculate_distance(guard.entity.position, closest_enemy.position)
                            if dist < closest_guard_dist then
                                closest_guard_dist = dist
                                closest_guard = guard
                            end
                        end
                    end
                    
                    -- Only this guard attacks if it's the closest
                    if closest_guard and closest_guard.unit_number == creeper.unit_number then
                        -- This guard is closest - start attack (stay in defensive_formation state)
                        creeper.guard_target = closest_enemy
                        creeper.guard_target_position = closest_enemy.position
                        
                        -- Track assignment in party
                        if party then
                            party.guard_assignments = party.guard_assignments or {}
                            party.guard_assignments[closest_enemy.unit_number] = creeper.unit_number
                        end
                    end
                end
            end
        end
    end
    
    -- Handle guard attack movement (if guard has a target)
    if creeper.is_guard and creeper.guard_target then
        if creeper.guard_target.valid and creeper.guard_target.health > 0 then
            local dist = calculate_distance(position, creeper.guard_target.position)
            if dist <= 2 then
                -- Close enough - explode
                creeper.target = creeper.guard_target
                creeper.target_position = creeper.guard_target.position
                creeper.state = "exploding"
                update_color(entity, "exploding")
                -- Clear guard assignment
                if party and party.guard_assignments then
                    party.guard_assignments[creeper.guard_target.unit_number] = nil
                end
                creeper.guard_target = nil
                return
            else
                -- Move toward target using autopilot only
                if not entity.autopilot_destination or 
                   (creeper.guard_target_position and 
                    calculate_distance(entity.position, creeper.guard_target_position) > 5) then
                    entity.autopilot_destination = nil
                    entity.follow_target = nil
                    if storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number] then
                        storage.scheduled_autopilots[creeper.unit_number] = nil
                    end
                    entity.add_autopilot_destination(creeper.guard_target.position)
                    creeper.guard_target_position = creeper.guard_target.position
                end
            end
        else
            -- Target is dead or invalid - clear assignment
            if party and party.guard_assignments and creeper.guard_target.unit_number then
                party.guard_assignments[creeper.guard_target.unit_number] = nil
            end
            creeper.guard_target = nil
            creeper.guard_target_position = nil
            entity.autopilot_destination = nil
            entity.follow_target = nil
        end
    end
    
    -- Handle defensive_target attack movement (for bots assigned to attack units)
    if creeper.defensive_target then
        -- CRITICAL: Clear follow_target aggressively - bot is attacking, should NOT follow anyone
        -- Clear it multiple times to ensure it's cleared
        for i = 1, 5 do
            pcall(function() entity.follow_target = nil end)
        end
        
        if creeper.defensive_target.valid and creeper.defensive_target.health > 0 then
            local dist = calculate_distance(position, creeper.defensive_target.position)
            if dist <= 2 then
                -- Close enough - explode
                creeper.target = creeper.defensive_target
                creeper.target_position = creeper.defensive_target.position
                creeper.state = "exploding"
                update_color(entity, "exploding")
                creeper.defensive_target = nil
                return
            else
                -- Move toward target using autopilot only
                if not entity.autopilot_destination or 
                   calculate_distance(entity.position, creeper.defensive_target.position) > 5 then
                    entity.autopilot_destination = nil
                    -- Clear all autopilot destinations
                    local attempts = 0
                    while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
                        entity.autopilot_destination = nil
                        attempts = attempts + 1
                    end
                    if storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number] then
                        storage.scheduled_autopilots[creeper.unit_number] = nil
                    end
                    if storage.autopilot_queue and storage.autopilot_queue[creeper.unit_number] then
                        storage.autopilot_queue[creeper.unit_number] = nil
                    end
                    entity.add_autopilot_destination(creeper.defensive_target.position)
                end
            end
        else
            -- Target is dead or invalid - clear it and return to formation
            creeper.defensive_target = nil
            entity.autopilot_destination = nil
            -- Clear follow_target multiple times
            for i = 1, 5 do
                pcall(function() entity.follow_target = nil end)
            end
        end
        -- Return early - bot is attacking, don't do positioning
        return
    end
    
    -- All non-leader, non-attacking bots should follow the leader
    if not creeper.is_leader and not creeper.defensive_target and leader.entity and leader.entity.valid then
        -- Clear autopilot destinations first
        entity.autopilot_destination = nil
        -- Clear all autopilot destinations
        local attempts = 0
        while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
            entity.autopilot_destination = nil
            attempts = attempts + 1
        end
        
        -- Clear follow_target first (multiple times to ensure it's cleared), then set it to leader
        for i = 1, 5 do
            pcall(function() entity.follow_target = nil end)
        end
        
        local success, err = pcall(function()
            entity.follow_target = leader.entity
            entity.follow_offset = nil
        end)
        if not success then
            game.print("DEBUG: Failed to set follow_target for unit " .. creeper.unit_number .. ": " .. tostring(err))
        else
            -- Verify it was set correctly
            if entity.follow_target ~= leader.entity then
                game.print("DEBUG: WARNING: follow_target not set correctly for unit " .. creeper.unit_number .. ", current: " .. (entity.follow_target and tostring(entity.follow_target.unit_number) or "nil") .. ", expected: " .. leader.entity.unit_number)
            end
        end
    end
    
--]]
end

return defensive_formation_state