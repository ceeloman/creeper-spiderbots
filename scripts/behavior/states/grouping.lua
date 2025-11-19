-- Creeperbots - Grouping State Handler
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local grouping_state = {}

function grouping_state.handle_grouping_state(creeper, event, position, entity, surface, tier, party)
    update_color(entity, creeper.is_guard and "guard" or "grouping")

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
            radius = 3,  -- Reduced from 5 to 3 - only very close enemies
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
    
    -- Guard distraction behavior - guards detect bugs and distract them
    if creeper.is_guard then
        -- Check for nearby enemy units within 20 tiles
        local nearby_enemies = surface.find_entities_filtered({
            type = "unit",
            position = position,
            radius = 20,
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
                -- Initialize distraction state if not set
                if not creeper.distraction_state then
                    creeper.distraction_state = "approaching"  -- approaching, distracting, exploding
                    creeper.distraction_target = closest_enemy
                    creeper.distraction_start_tick = event.tick
                end
                
                local dist_to_enemy = calculate_distance(position, closest_enemy.position)
                
                if creeper.distraction_state == "approaching" then
                    -- Run towards enemy until within 10 tiles
                    if dist_to_enemy > 10 then
                        -- Move towards enemy
                        local dx = closest_enemy.position.x - position.x
                        local dy = closest_enemy.position.y - position.y
                        local distance = math.sqrt(dx * dx + dy * dy)
                        local dir_x = dx / distance
                        local dir_y = dy / distance
                        
                        local next_pos = {
                            x = position.x + dir_x * 5,
                            y = position.y + dir_y * 5
                        }
                        entity.autopilot_destination = nil
                        local success, err = pcall(function()
                            entity.add_autopilot_destination(next_pos)
                        end)
                    else
                        -- Close enough, start distracting
                        creeper.distraction_state = "distracting"
                        local random = game.create_random_generator()
                        creeper.distraction_direction = random(1, 2) == 1 and "left" or "right"
                        creeper.distraction_last_change = event.tick
                    end
                elseif creeper.distraction_state == "distracting" then
                    -- Move left/right perpendicular to enemy direction
                    local dx = closest_enemy.position.x - position.x
                    local dy = closest_enemy.position.y - position.y
                    local angle = math.atan2(dy, dx)
                    
                    -- Perpendicular direction (left or right)
                    local perp_angle = angle + (creeper.distraction_direction == "left" and -math.pi/2 or math.pi/2)
                    
                    -- Change direction every 60 ticks
                    if event.tick >= (creeper.distraction_last_change or 0) + 60 then
                        creeper.distraction_direction = creeper.distraction_direction == "left" and "right" or "left"
                        creeper.distraction_last_change = event.tick
                    end
                    
                    local move_pos = {
                        x = position.x + math.cos(perp_angle) * 3,
                        y = position.y + math.sin(perp_angle) * 3
                    }
                    entity.autopilot_destination = nil
                    local success, err = pcall(function()
                        entity.add_autopilot_destination(move_pos)
                    end)
                    
                    -- Check if enemy is very close - explode
                    -- Units need to be within 2 tiles, nests would be 5 tiles (but guards only target units)
                    local explode_distance = 2  -- Guards only target units
                    if dist_to_enemy <= explode_distance then
                        creeper.distraction_state = "exploding"
                        creeper.target = closest_enemy
                        creeper.target_position = closest_enemy.position
                        creeper.state = "exploding"
                        update_color(entity, "exploding")
                        return
                    end
                end
            end
        end
    end

    storage.parties = storage.parties or {}

    if not creeper.grouping_initialized then
        -- Clear any old attack/target data when entering grouping
        creeper.target = nil
        creeper.target_position = nil
        creeper.target_health = nil
        
        creeper.party_id = assign_to_party(entity)
        local party = storage.parties[creeper.party_id]
        if not party then
            local party_id = entity.unit_number .. "-" .. event.tick
            party = {
                members = {},
                grouping_leader = nil,
                grouping_start_tick = event.tick,
                last_join_tick = event.tick,
                state = "grouping",
                follower_targets = {},
                visited_chunks = {},
                surface = entity.surface  -- Store surface reference for territory tracking
            }
            storage.parties[party_id] = party
            creeper.party_id = party_id
        else
            -- Bot is joining an existing party - reset the grouping timer so countdown starts fresh
            party.grouping_start_tick = event.tick
            party.last_join_tick = event.tick
        end
        creeper.is_leader = not party.grouping_leader and true or false
        if creeper.is_leader then
            party.grouping_leader = entity.unit_number
            party.grouping_start_tick = event.tick
            party.last_join_tick = event.tick
        end
        creeper.grouping_initialized = true
        party.last_join_tick = event.tick
        --ame.print("Debug: Initialized party " .. creeper.party_id .. " for unit " .. creeper.unit_number .. ", leader: " .. tostring(creeper.is_leader))
    end

    party = storage.parties[creeper.party_id]
    if not party then
        creeper.grouping_initialized = false
        creeper.party_id = nil
        --game.print("Error: Party not found for unit " .. creeper.unit_number .. ", resetting grouping")
        return handle_grouping_state(creeper, event, position, entity, surface, tier, party)
    end

    local leader = storage.creeperbots[party.grouping_leader]
    local leader_pos = nil
    if leader and leader.entity and leader.entity.valid then
        leader_pos = leader.entity.position
    else
        creeper.is_leader = true
        creeper.is_guard = false
        update_color(entity, "grouping")
        party.grouping_leader = entity.unit_number
        party.grouping_start_tick = event.tick
        party.last_join_tick = event.tick
        leader_pos = entity.position
        --game.print("Debug: Leader invalid, unit " .. creeper.unit_number .. " became leader")
    end

    local members = {}
    local guards = {}
    for unit_number, member in pairs(storage.creeperbots or {}) do
        if member.party_id == creeper.party_id and member.entity and member.entity.valid then
            table.insert(members, member)
            if member.is_guard then
                table.insert(guards, member)
            end
        end
    end
    --game.print("Debug: Party " .. creeper.party_id .. " - Members: " .. #members .. ", Guards: " .. #guards .. ", Ticks elapsed: " .. (event.tick - (party.grouping_start_tick or event.tick)))

    if #members == 1 and creeper.is_leader then
        entity.autopilot_destination = nil
        --game.print("Debug: Leader " .. creeper.unit_number .. " alone, cleared autopilot_destination")
        return
    end

    local required_guard_count = 0
    if #members >= 6 then required_guard_count = 5
    elseif #members >= 5 then required_guard_count = 4
    elseif #members >= 4 then required_guard_count = 3
    elseif #members >= 3 then required_guard_count = 2
    elseif #members >= 2 then required_guard_count = 1
    end
    local current_guards = #guards

    if current_guards < required_guard_count then
        local candidates = {}
        for _, member in ipairs(members) do
            if member.state == "grouping" and not member.is_leader and not member.is_guard then
                table.insert(candidates, member)
            end
        end
        table.sort(candidates, function(a, b) return a.tier < b.tier end)
        
        for _, candidate in ipairs(candidates) do
            if current_guards < required_guard_count then
                candidate.is_guard = true
                update_color(candidate.entity, "guard")
                current_guards = current_guards + 1
                table.insert(guards, candidate)
                -- Force guard to take position immediately by clearing any existing destinations
                if candidate.entity and candidate.entity.valid then
                    candidate.entity.autopilot_destination = nil
                    candidate.last_path_request = 0  -- Set to 0 so they can move immediately (0 < current tick)
                    -- Clear any scheduled autopilots from previous state
                    if storage.scheduled_autopilots and storage.scheduled_autopilots[candidate.unit_number] then
                        storage.scheduled_autopilots[candidate.unit_number] = nil
                    end
                end
                --game.print("Debug: Unit " .. candidate.unit_number .. " became guard")
            end
        end
        
        if current_guards > 0 then
            local new_members = {}
            for _, member in ipairs(members) do
                if member.state == "grouping" and not member.is_leader and not member.is_guard then
                    table.insert(new_members, member)
                end
            end
            table.sort(new_members, function(a, b) return a.tier < b.tier end)
            
            for _, new_member in ipairs(new_members) do
                for i = #guards, 1, -1 do
                    local guard = guards[i]
                    if guard.tier > new_member.tier then
                        guard.is_guard = false
                        update_color(guard.entity, "grouping")
                        new_member.is_guard = true
                        update_color(new_member.entity, "guard")
                        guards[i] = new_member
                        -- Force newly assigned guard to take position immediately
                        if new_member.entity and new_member.entity.valid then
                            new_member.entity.autopilot_destination = nil
                            new_member.last_path_request = 0  -- Set to 0 so they can move immediately
                            -- Clear any scheduled autopilots from previous state
                            if storage.scheduled_autopilots and storage.scheduled_autopilots[new_member.unit_number] then
                                storage.scheduled_autopilots[new_member.unit_number] = nil
                            end
                        end
                        --game.print("Debug: Swapped guard " .. guard.unit_number .. " with " .. new_member.unit_number)
                        break
                    end
                end
            end
        end
    end
    
    -- Rebuild guards array after assignment to ensure all guards are included
    guards = {}
    for _, member in ipairs(members) do
        if member.is_guard then
            table.insert(guards, member)
        end
    end

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
        for i, guard in ipairs(guards) do
            if guard.entity and guard.entity.valid then
                local pos = guard_positions[i] or {angle = 180, radius = 3}
                local dest_pos = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                }
                local dist_to_current = math.sqrt((dest_pos.x - guard.entity.position.x)^2 + (dest_pos.y - guard.entity.position.y)^2)
                -- Only move if significantly out of position (> 1.5 tiles) to prevent micro-movements
                -- And ensure we don't spam path requests
                local can_move = (not guard.last_path_request or guard.last_path_request == 0 or event.tick >= guard.last_path_request + 120)
                if dist_to_current > 1.5 and can_move then
                    -- Check if guard is already moving toward destination (including scheduled autopilots)
                    local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[guard.unit_number]
                    local has_active_destination = guard.entity.autopilot_destination ~= nil or (#guard.entity.autopilot_destinations > 0)
                    -- Only skip if there's an active destination OR a scheduled one that hasn't expired yet
                    if queue and event.tick < queue.tick then
                        -- Has a scheduled destination that hasn't been applied yet, skip
                    elseif not has_active_destination then
                        -- No active destination, set it directly (like distraction behavior does)
                        guard.entity.autopilot_destination = nil  -- Clear first
                        local success, err = pcall(function()
                            guard.entity.add_autopilot_destination(dest_pos)
                        end)
                        guard.last_path_request = event.tick
                    end
                end
            end
        end
    end

    -- REMOVED: This was clearing guard destinations that were just set directly
    -- The original logic was meant to clear stale destinations, but it was clearing
    -- destinations that guards need to reach their positions
    -- if event.tick % 60 == 0 then
    --     for _, guard in ipairs(guards) do
    --         if guard.entity and guard.entity.valid then
    --             local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[guard.unit_number]
    --             if not queue and #guard.entity.autopilot_destinations > 0 then
    --                 guard.entity.autopilot_destination = nil
    --                -- game.print("Debug: Guard " .. guard.unit_number .. " cleared autopilot_destination")
    --             end
    --         end
    --     end
    -- end

    if event.tick % 60 == 0 and actual_guard_count > 0 then
        local random = game.create_random_generator()
        local out_of_position = nil
        local out_of_position_index = nil
        
        for i, guard in ipairs(guards) do
            if guard.entity and guard.entity.valid then
                local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[guard.unit_number]
                if not queue and #guard.entity.autopilot_destinations == 0 then
                    local pos = guard_positions[i] or {angle = 180, radius = 3}
                    local dest_pos = {
                        x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                        y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                    }
                    local dist_to_dest = math.sqrt((dest_pos.x - guard.entity.position.x)^2 + (dest_pos.y - guard.entity.position.y)^2)
                    -- Only consider out of position if significantly off (> 1.5 tiles) to prevent micro-movements
                    if dist_to_dest > 1.5 then
                        out_of_position = guard
                        out_of_position_index = i
                        break
                    end
                end
            end
        end
        
        if out_of_position then
            local stationary_guards = {}
            for i, guard in ipairs(guards) do
                if guard.entity and guard.entity.valid and i ~= out_of_position_index then
                    local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[guard.unit_number]
                    if not queue and #guard.entity.autopilot_destinations == 0 then
                        table.insert(stationary_guards, {guard = guard, index = i})
                    end
                end
            end
            
            if #stationary_guards > 0 then
                local swap = stationary_guards[random(1, #stationary_guards)]
                local swap_guard = swap.guard
                local swap_index = swap.index
                
                guards[out_of_position_index], guards[swap_index] = swap_guard, out_of_position
                
                local pos1 = guard_positions[out_of_position_index] or {angle = 180, radius = 3}
                local dest_pos1 = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos1.angle)) * pos1.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos1.angle)) * pos1.radius)
                }
                local pos2 = guard_positions[swap_index] or {angle = 180, radius = 3}
                local dest_pos2 = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos2.angle)) * pos2.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos2.angle)) * pos2.radius)
                }
                
                local dist1 = math.sqrt((dest_pos1.x - swap_guard.entity.position.x)^2 + (dest_pos1.y - swap_guard.entity.position.y)^2)
                -- Only move if significantly out of position (> 1.5 tiles)
                if dist1 > 1.5 and (not swap_guard.last_path_request or event.tick >= swap_guard.last_path_request + 120) then
                    local has_destination = swap_guard.entity.autopilot_destination ~= nil or (#swap_guard.entity.autopilot_destinations > 0)
                    if not has_destination then
                        schedule_autopilot_destination(swap_guard, {dest_pos1}, event.tick + 30, false)
                        swap_guard.last_path_request = event.tick
                        --game.print("Debug: Swapped guard " .. swap_guard.unit_number .. " to (" .. dest_pos1.x .. "," .. dest_pos1.y .. ")")
                    end
                end
                
                local dist2 = math.sqrt((dest_pos2.x - out_of_position.entity.position.x)^2 + (dest_pos2.y - out_of_position.entity.position.y)^2)
                -- Only move if significantly out of position (> 1.5 tiles)
                if dist2 > 1.5 and (not out_of_position.last_path_request or event.tick >= out_of_position.last_path_request + 120) then
                    local has_destination = out_of_position.entity.autopilot_destination ~= nil or (#out_of_position.entity.autopilot_destinations > 0)
                    if not has_destination then
                        schedule_autopilot_destination(out_of_position, {dest_pos2}, event.tick + 30, false)
                        out_of_position.last_path_request = event.tick
                        --game.print("Debug: Swapped guard " .. out_of_position.unit_number .. " to (" .. dest_pos2.x .. "," .. dest_pos2.y .. ")")
                    end
                end
            end
        end
    end

    for _, member in ipairs(members) do
        if member.state == "grouping" and not member.is_leader and not member.is_guard and member.entity and member.entity.valid then
            local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[member.unit_number]
            local has_destination = member.entity.autopilot_destination ~= nil or (#member.entity.autopilot_destinations > 0)
            
            -- First, ensure followers are within reasonable distance of leader (approach phase)
            local dist_to_leader = calculate_distance(member.entity.position, leader_pos)
            local approach_distance = 15  -- Get within 15 tiles of leader first
            
            -- Create unique random generator for each member to ensure different random values
            local random = game.create_random_generator(member.unit_number * event.tick)
            
            -- Always check and move if needed, don't wait for queue to be empty
            -- Clear any old destinations from waking state if too far from leader
            if dist_to_leader > approach_distance then
                -- Too far from leader - clear old destinations and approach
                if has_destination then
                    member.entity.autopilot_destination = nil
                    if storage.scheduled_autopilots and storage.scheduled_autopilots[member.unit_number] then
                        storage.scheduled_autopilots[member.unit_number] = nil
                    end
                end
                -- Approach leader (only if not already scheduled)
                if not queue then
                    local approach_pos = {
                        x = leader_pos.x + (random(1, 10) - 5),  -- -5 to +5
                        y = leader_pos.y + (random(1, 10) - 5)   -- -5 to +5
                    }
                    schedule_autopilot_destination(member, {approach_pos}, event.tick + 30, false)
                    --game.print("Debug: Follower " .. member.unit_number .. " approaching leader from " .. math.floor(dist_to_leader) .. " tiles away")
                end
            elseif not queue and not has_destination then
                -- Close enough and no active movement - do occasional random movements around leader
                if random(1, 100) <= 30 then
                    local destinations = generate_random_destinations(
                        leader_pos,
                        1,
                        3,
                        5,
                        surface,
                        member.entity.name,
                        member.entity.position,
                        member.unit_number,
                        event.tick
                    )
                    if #destinations > 0 then
                        schedule_autopilot_destination(member, {destinations[1]}, event.tick + 30, false)
                        --game.print("Debug: Follower " .. member.unit_number .. " scheduled random destination (" .. destinations[1].x .. "," .. destinations[1].y .. ")")
                    end
                end
            end
        end
    end

    -- Reset grouping_start_tick when new members join (so timer starts fresh when party is ready)
    if party.last_join_tick and party.last_join_tick > (party.grouping_start_tick or 0) then
        -- New member joined after timer started - reset timer
        party.grouping_start_tick = event.tick
    elseif not party.grouping_start_tick then
        -- First time - set grouping_start_tick
        party.grouping_start_tick = event.tick
    end
    
    -- Fallback: If bot has been in grouping for 60+ seconds and still can't transition, go solo
    local time_elapsed = event.tick - party.grouping_start_tick
    if time_elapsed >= 3600 and not party.started_scouting and #members == 1 then
        -- Bot is stuck solo in grouping - go to scouting
        party.started_scouting = true
        party.state = "scouting"
        creeper.state = "scouting"
        update_color(entity, "scouting")
        if creeper.debug_text_id then
            if type(creeper.debug_text_id) == "userdata" then
                if creeper.debug_text_id.valid then
                    creeper.debug_text_id.destroy()
                end
            elseif type(creeper.debug_text_id) == "number" then
                local old_text = rendering.get_object_by_id(creeper.debug_text_id)
                if old_text and old_text.valid then
                    old_text.destroy()
                end
            end
            creeper.debug_text_id = nil
        end
        return
    end
    
    -- Show debug message above leader's head
    if creeper.is_leader and entity.valid then
        -- Clear old debug text
        if creeper.debug_text_id then
            if type(creeper.debug_text_id) == "userdata" then
                -- It's a rendering object directly
                if creeper.debug_text_id.valid then
                    creeper.debug_text_id.destroy()
                end
            elseif type(creeper.debug_text_id) == "number" then
                -- It's a numeric ID
                local old_text = rendering.get_object_by_id(creeper.debug_text_id)
                if old_text and old_text.valid then
                    old_text.destroy()
                end
            end
        end
        
        -- Create new debug text
        local min_time = (#members >= 3) and 600 or 900
        local time_remaining = math.max(0, min_time - time_elapsed)
        local debug_msg = string.format("Grouping: %d members, %ds left", #members, math.ceil(time_remaining / 60))
        
        creeper.debug_text_id = rendering.draw_text{
            text = debug_msg,
            surface = surface,
            target = entity,
            target_offset = {0, -2},
            color = {r = 1, g = 1, b = 1},
            scale = 1.0,
            alignment = "center"
        }
    end
    
    -- Transition to scouting after timeout (reduced from 1200 to 600 ticks = 10 seconds)
    -- Also allow transition with fewer members (at least 1, or wait longer if solo)
    local min_time = (#members >= 3) and 600 or 900  -- 10 seconds for groups, 15 seconds for smaller groups
    local has_leader = party.grouping_leader and storage.creeperbots[party.grouping_leader] and storage.creeperbots[party.grouping_leader].entity and storage.creeperbots[party.grouping_leader].entity.valid
    
    if not party.started_scouting and party.grouping_start_tick and time_elapsed >= min_time and has_leader and #members >= 1 then
        -- Clear debug text
        if creeper.is_leader and creeper.debug_text_id then
            if type(creeper.debug_text_id) == "userdata" then
                if creeper.debug_text_id.valid then
                    creeper.debug_text_id.destroy()
                end
            elseif type(creeper.debug_text_id) == "number" then
                local old_text = rendering.get_object_by_id(creeper.debug_text_id)
                if old_text and old_text.valid then
                    old_text.destroy()
                end
            end
            creeper.debug_text_id = nil
        end
        party.started_scouting = true
        party.state = "scouting"
        party.follower_targets = party.follower_targets or {}
    
        -- Update all members in the party, including those in other states
        for unit_number, member in pairs(storage.creeperbots or {}) do
            if member.party_id == creeper.party_id and member.entity and member.entity.valid then
                -- Only transition bots that are in grouping state (not exploding/approaching)
                if member.state == "grouping" then
                    member.state = member.is_guard and "guard" or "scouting"
                    update_color(member.entity, member.state)
                    --game.print("Debug: Unit " .. member.unit_number .. " transitioned to state " .. member.state)
                elseif member.state == "exploding" then
                    -- Bots in exploding state should clear party and continue hunting
                    -- They'll transition to waking when they find no targets
                    member.party_id = nil
                    member.is_leader = false
                    member.is_guard = false
                    member.is_distractor = false
                    -- Keep exploding state and color - they'll handle transition themselves
                end
            end
        end
    
        if creeper.is_leader then
            entity.autopilot_destination = nil
            local target_pos = get_unvisited_chunk(entity.position, party)
            if target_pos.x ~= entity.position.x or target_pos.y ~= entity.position.y then
                request_multiple_paths(entity.position, target_pos, party, surface, creeper.unit_number)
                --game.print("Debug: Leader " .. creeper.unit_number .. " set path to (" .. target_pos.x .. "," .. target_pos.y .. ")")
            else
                --game.print("Error: Leader " .. creeper.unit_number .. " no valid chunk found")
            end
        end
    end
    
end

return grouping_state

