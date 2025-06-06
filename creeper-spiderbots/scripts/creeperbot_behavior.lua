-- Creeperbots - Behavior script
-- Defines tier-specific behaviors and state machine logic
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

-- Tier configurations
tier_configs = {
    ["creeperbot-mk1"] = { tier = 1, damage = 200, radius = 3.5, max_targeting = 3, explosion = "big-explosion" },
    ["creeperbot-mk2"] = { tier = 2, damage = 400, radius = 5.0, max_targeting = 2, explosion = "massive-explosion" },
    ["creeperbot-mk3-nuclear"] = { tier = 3, damage = 900, radius = 20, max_targeting = 1, explosion = "nuke-explosion", extra_effect = "nuclear-smoke" },
}

function get_creeperbot_tier(entity_name)
    game.print("Debug: get_creeperbot_tier called for: " .. tostring(entity_name))
    local tier_config = tier_configs[entity_name]
    if tier_config then
        return tier_config.tier
    end
    game.print("Debug: Unknown entity: " .. tostring(entity_name) .. ", using default tier (mk1)")
    return tier_configs["creeperbot-mk1"].tier
end

function get_guard_positions(guard_count)
    local positions = {}
    if guard_count == 1 then
        positions = {{angle = 180, radius = 3}}
    elseif guard_count == 2 then
        positions = {{angle = 90, radius = 4}, {angle = 270, radius = 4}}
    elseif guard_count == 3 then
        positions = {{angle = 120, radius = 5}, {angle = 240, radius = 5}, {angle = 0, radius = 5}}
    elseif guard_count == 4 then
        positions = {{angle = 45, radius = 6}, {angle = 135, radius = 6}, {angle = 225, radius = 6}, {angle = 315, radius = 6}}
    elseif guard_count >= 5 then
        positions = {{angle = 0, radius = 8}, {angle = 72, radius = 8}, {angle = 144, radius = 8}, {angle = 216, radius = 8}, {angle = 288, radius = 8}}
    end
    return positions
end

-- Calculate distance between two positions
function calculate_distance(pos1, pos2)
    return ((pos1.x - pos2.x)^2 + (pos1.y - pos2.y)^2)^0.5
end

-- Find the nearest enemy nest or turret
function scan_for_enemies(position, surface, max_targeting, waking)
    -- Default max_targeting to 3 if nil
    max_targeting = max_targeting or 3
    
    -- Proximity limits for waking state
    local unit_radius = waking and 20 or 50
    local nest_radius = waking and 50 or 150
    
    -- Search for enemy units
    local units = surface.find_entities_filtered{
        position = position,
        radius = unit_radius,
        force = "enemy",
        type = "unit"
    }

    local nearest_unit = nil
    local nearest_unit_distance = unit_radius

    for _, unit in pairs(units) do
        local targeting_count = 0
        for _, creeper in pairs(storage.creeperbots or {}) do
            if creeper.target and creeper.target.valid and creeper.target.unit_number == unit.unit_number then
                targeting_count = targeting_count + 1
            end
        end
        if targeting_count < max_targeting then
            local distance = calculate_distance(position, unit.position)
            if distance < nearest_unit_distance then
                nearest_unit_distance = distance
                nearest_unit = unit
            end
        end
    end

    -- If an enemy unit is found, return it
    if nearest_unit then
        game.print("Found enemy unit at (" .. nearest_unit.position.x .. "," .. nearest_unit.position.y .. "), distance: " .. nearest_unit_distance)
        return nearest_unit, "unit"
    end

    -- Otherwise, search for enemy nests
    local nests = surface.find_entities_filtered{
        position = position,
        radius = nest_radius,
        force = "enemy",
        type = {"unit-spawner", "turret"}
    }

    local nearest_nest = nil
    local nearest_nest_distance = nest_radius

    for _, nest in pairs(nests) do
        local targeting_count = 0
        for _, creeper in pairs(storage.creeperbots or {}) do
            if creeper.target and creeper.target.valid and creeper.target.unit_number == nest.unit_number then
                targeting_count = targeting_count + 1
            end
        end
        if targeting_count < max_targeting then
            local distance = calculate_distance(position, nest.position)
            if distance < nearest_nest_distance then
                nearest_nest_distance = distance
                nearest_nest = nest
            end
        end
    end

    if nearest_nest then
        --game.print("Found enemy nest at (" .. nearest_nest.position.x .. "," .. nearest_nest.position.y .. "), distance: " .. nearest_nest_distance)
        return nearest_nest, "nest"
    end

    --game.print("No enemies found within range")
    return nil, nil
end

--[[
function scan_for_enemies_waking(position, surface, max_targeting)
    -- First try spawners and turrets
    local enemies = surface.find_entities_filtered{
        position = position,
        radius = 30, -- Reduced to 30 tiles for waking state
        force = "enemy",
        type = {"unit-spawner", "turret"},
    }

    local nearest_distance = 30
    local nearest_entity = nil

    for _, entity in pairs(enemies) do
        local targeting_count = 0
        for _, creeper in pairs(storage.creeperbots or {}) do
            if creeper.target and creeper.target.valid and creeper.target.unit_number == entity.unit_number then
                targeting_count = targeting_count + 1
            end
        end

        if targeting_count < max_targeting then
            local distance = calculate_distance(position, entity.position)
            if distance < nearest_distance then
                nearest_distance = distance
                nearest_entity = entity
            end
        end
    end

    -- Fallback to units if no spawners/turrets found
    if not nearest_entity then
        enemies = surface.find_entities_filtered{
            position = position,
            radius = 30,
            force = "enemy",
            type = {"unit"},
        }

        for _, entity in pairs(enemies) do
            local targeting_count = 0
            for _, creeper in pairs(storage.creeperbots or {}) do
                if creeper.target and creeper.target.valid and creeper.target.unit_number == entity.unit_number then
                    targeting_count = targeting_count + 1
                end
            end

            if targeting_count < max_targeting then
                local distance = calculate_distance(position, entity.position)
                if distance < nearest_distance then
                    nearest_distance = distance
                    nearest_entity = entity
                end
            end
        end
    end

    return nearest_entity
end
]]

-- Broadcast target to nearby Creeperbots
function broadcast_target(target, position, surface, sender_unit_number)
    local nearby_bots = surface.find_entities_filtered{
        position = position,
        radius = 100,
        name = {"creeperbot-mk1", "creeperbot-mk2", "creeperbot-mk3-nuclear"},
    }

    for _, bot in pairs(nearby_bots) do
        if bot.valid and bot.unit_number ~= sender_unit_number then
            for _, creeper in pairs(storage.creeperbots or {}) do
                if creeper.entity.unit_number == bot.unit_number and creeper.state == "scouting" then
                    local party = storage.parties[creeper.party_id]
                    if not party.shared_target and math.random() < 0.5 then
                        local targeting_count = 0
                        for _, c in pairs(storage.creeperbots or {}) do
                            if c.target and c.target.valid and c.target.unit_number == target.unit_number then
                                targeting_count = targeting_count + 1
                            end
                        end
                        if targeting_count < creeper.tier.max_targeting then
                            party.shared_target = target
                            creeper.target = target
                            creeper.state = "approaching"
                            creeper.entity.color = {r = 1, g = 0, b = 0}
                            request_multiple_paths(creeper.entity.position, target.position, party, surface, creeper.entity.unit_number)
                        end
                    end
                end
            end
        end
    end
end

-- Main update function acting as a state machine dispatcher
function update_creeperbot(creeper, event)
    local entity = creeper.entity
    local position = entity.position
    local surface = entity.surface
    local tier = creeper.tier
    local party = creeper.party_id and storage.parties[creeper.party_id] or nil
--[[
    if creeper.state == "approaching" and creeper.target and creeper.target.valid then
        local target_distance = calculate_distance(position, creeper.target.position)
        if target_distance <= 20 then
            creeper.state = "exploding"
            clear_renderings(creeper)
        end
    end
]]

    local has_valid_path = false

    local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] or {}

    if creeper.state == "waking" then
        handle_waking_state(creeper, event, position, entity, surface, tier)
        local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] or {}
        if not queue.destination and not entity.autopilot_destination and not creeper.waking_initialized then
            local random = game.create_random_generator()
            local roll = random(1, 100)
            if roll > 75 then
                storage.leader_candidates = storage.leader_candidates or {}
                storage.leader_candidates[entity.unit_number] = {creeper = creeper, position = position}
                game.print("CreeperBot " .. entity.unit_number .. " is a leader candidate (roll: " .. roll .. ")")
            else
                local party_id = assign_to_party(entity)
                local new_party = storage.parties[party_id]
                if new_party and new_party.grouping_leader then
                    creeper.party_id = party_id
                    creeper.state = "grouping"
                    update_color(entity, "grouping")
                    new_party.last_join_tick = game.tick
                    game.print("CreeperBot " .. entity.unit_number .. " joined group, leader: " .. new_party.grouping_leader)
                else
                    game.print("CreeperBot " .. entity.unit_number .. " failed to join group, no leader found")
                end
            end
        end
    elseif creeper.state == "grouping" then
        handle_grouping_state(creeper, event, position, entity, surface, tier, party)
    elseif creeper.state == "scouting" or creeper.state == "guard" and not creeper.is_leader then
        handle_scouting_state(creeper, event, position, entity, party)
    elseif creeper.state == "scouting" and creeper.is_leader then
        handle_scouting_state(creeper, event, position, entity, party, process_waypoints(creeper))
    elseif creeper.state == "approaching" then
        handle_approaching_state(creeper, event, position, entity, surface, tier, party)
    elseif creeper.state == "preparing_to_attack" then
        handle_preparing_to_attack_state(creeper, event, position, entity, surface, tier, party)
    elseif creeper.state == "exploding" then
        handle_exploding_state(creeper, entity, position, surface, tier, party)
    end

    if party then
        party.pending_path_requests = party.pending_path_requests or {}
    end
end

-- Handler for remote_controlled state
function handle_remote_controlled_state(creeper, entity)
    -- Minimal handling as most logic is handled in waypoint processing
    entity.color = {r = 0, g = 0, b = 1}
    game.print("CreeperBot " .. entity.unit_number .. "251")
end

-- Handler for waking state
function handle_waking_state(creeper, event, position, entity, surface, tier)
    -- Set color for waking state
    update_color(entity, "waking")
    
    -- Initialize and schedule all movements
    if not creeper.waking_initialized then
        local random = game.create_random_generator()
        local rand = random(1, 100)
        local move_count = rand <= 50 and 2 or (rand <= 80 and 3 or 4)
        
        -- Generate random destinations
        local destinations = generate_random_destinations(
            position, 
            move_count + 1, -- Extra destination for after scan
            3, 
            6, 
            surface, 
            entity.name
        )
        
        
        -- Log and schedule all destinations
        local current_tick = event.tick
        local scan_at_move = move_count -- Which move to perform the scan after
        
        -- First movement has longer delay (1-3 seconds)
        local first_delay = random(30, 180)
        current_tick = current_tick + first_delay
        
        -- Before scheduling, make sure the bot has a queue in storage
        if not storage.autopilot_queue then
            storage.autopilot_queue = {}
        end
        
        -- Clear any existing queue for this bot
        storage.autopilot_queue[entity.unit_number] = {}
        
        -- Schedule all movements
        for i = 1, #destinations do
            local dest = destinations[i]
            local actual_distance = calculate_distance(position, dest)
            
            -- Determine if we should scan after reaching this destination
            local should_scan = (i == scan_at_move)
            
            -- Add this destination to the queue
            table.insert(storage.autopilot_queue[entity.unit_number], {
                destination = dest,
                tick = current_tick,
                should_scan = should_scan,
                sequence = i
            })
            
            -- Add random delay for next movement (0.5-2 seconds)
            if i < #destinations then
                current_tick = current_tick + random(30, 120)
            end
        end
        
        creeper.waking_initialized = true
    end
    
    -- No need to check for destination completion or schedule new ones
    -- All destinations are scheduled at initialization
end

function handle_scouting_state(creeper, event, position, entity, party, has_valid_path)
    -- Validate inputs
    if not entity or not entity.valid then
        game.print("Error: Invalid entity for unit " .. (creeper.unit_number or "unknown"))
        return
    end
    if not party then
        game.print("Error: Invalid party for unit " .. (creeper.unit_number or "unknown"))
        return
    end
    local surface = entity.surface
    if not surface or not surface.valid then
        game.print("Error: Invalid surface for unit " .. (creeper.unit_number or "unknown"))
        return
    end
    --game.print("Debug: handle_scouting_state for unit " .. creeper.unit_number .. ", party: " .. (creeper.party_id or "none") .. ", surface: " .. surface.name)

    local members = {}
    local guards = {}
    local followers = {}
    for unit_number, member in pairs(storage.creeperbots or {}) do
        if member.party_id == creeper.party_id and member.entity and member.entity.valid then
            table.insert(members, member)
            if member.is_guard then
                table.insert(guards, member)
            elseif not member.is_leader then
                table.insert(followers, member)
            end
        end
    end
    --game.print("Debug: Party " .. creeper.party_id .. " - Members: " .. #members .. ", Guards: " .. #guards .. ", Followers: " .. #followers)

    local leader = storage.creeperbots[party.grouping_leader]
    if not leader or not leader.entity or not leader.entity.valid then
        local new_leader = nil
        for _, member in ipairs(members) do
            if member.entity and member.entity.valid then
                new_leader = member
                break
            end
        end
        if new_leader then
            new_leader.is_leader = true
            new_leader.is_guard = false
            update_color(new_leader.entity, "scouting")
            party.grouping_leader = new_leader.unit_number
            game.print("Debug: New leader assigned - Unit " .. new_leader.unit_number)
        else
            game.print("Error: No valid leader or members for party " .. creeper.party_id)
            return
        end
        leader = new_leader
    end

    if creeper.is_leader then
        local success, err = pcall(function()
            creeper.entity.follow_target = nil
        end)
        if not success then
            entity.autopilot_destination = nil
           -- game.print("Debug: Leader " .. creeper.unit_number .. " cleared autopilot_destination due to follow_target failure")
        else
            --game.print("Debug: Leader " .. creeper.unit_number .. " follow_target set to nil, has path: " .. (has_valid_path and "yes" or "no"))
        end
    elseif creeper.is_guard then
        local guard_index = nil
        for i, guard in ipairs(guards) do
            if guard.unit_number == creeper.unit_number then
                guard_index = i
                break
            end
        end
        if guard_index then
            --game.print("Debug: Guard " .. creeper.unit_number .. " found at guard_index: " .. guard_index)
            local current_follow_target = creeper.entity.follow_target
            --game.print("Debug: Guard " .. creeper.unit_number .. " current follow_target: " .. (current_follow_target and (current_follow_target.valid and "valid" or "invalid") or "none"))
            
            local success, err = pcall(function()
                creeper.entity.follow_target = leader.entity
                creeper.entity.follow_offset = nil
                --game.print("Debug: Guard " .. creeper.unit_number .. " setting follow_target to leader unit " .. party.grouping_leader)
            end)
            if not success then
                --game.print("Error: Guard " .. creeper.unit_number .. " failed to set follow_target to leader unit " .. party.grouping_leader .. ", error: " .. tostring(err))
            else
                entity.autopilot_destination = nil
               -- game.print("Debug: Guard " .. creeper.unit_number .. " follow_target successfully set to leader")
            end
        else
            --game.print("Error: Guard " .. creeper.unit_number .. " not found in guards list")
        end
    elseif creeper.state == "scouting" then
        party.follower_targets = party.follower_targets or {}
        local target_unit_number = party.follower_targets[creeper.unit_number]
        --game.print("Debug: Follower " .. creeper.unit_number .. " assigned to target unit: " .. (target_unit_number or "none"))
    
        -- Log all available follow targets (leader and guards)
        local available_targets = {}
        if leader and leader.entity and leader.entity.valid then
            table.insert(available_targets, {unit_number = party.grouping_leader, type = "leader"})
        end
        for _, guard in ipairs(guards) do
            if guard.entity and guard.entity.valid then
                table.insert(available_targets, {unit_number = guard.unit_number, type = "guard"})
            end
        end
        local target_list = #available_targets > 0 and table.concat(table.map(available_targets, function(t) return t.unit_number .. "(" .. t.type .. ")" end), ", ") or "none"
        --game.print("Debug: Follower " .. creeper.unit_number .. " available follow targets: " .. target_list)
    
        -- Determine follow target (leader or guard)
        local target = nil
        if target_unit_number and storage.creeperbots[target_unit_number] and storage.creeperbots[target_unit_number].entity and storage.creeperbots[target_unit_number].entity.valid then
            target = storage.creeperbots[target_unit_number]
            --game.print("Debug: Follower " .. creeper.unit_number .. " existing target unit: " .. target_unit_number .. ", type: " .. (target.is_leader and "leader" or "guard"))
        else
            -- Count followers per target to balance assignment
            local follower_counts = {}
            for _, t in ipairs(available_targets) do
                follower_counts[t.unit_number] = 0
            end
            for follower_unit, assigned_target in pairs(party.follower_targets) do
                if follower_unit ~= creeper.unit_number and storage.creeperbots[follower_unit] and storage.creeperbots[follower_unit].entity and storage.creeperbots[follower_unit].entity.valid then
                    if follower_counts[assigned_target] then
                        follower_counts[assigned_target] = follower_counts[assigned_target] + 1
                    end
                end
            end
    
            -- Assign to target with fewest followers, randomize if equal
            local min_followers = math.huge
            local candidates = {}
            for _, t in ipairs(available_targets) do
                if follower_counts[t.unit_number] < min_followers then
                    min_followers = follower_counts[t.unit_number]
                    candidates = {t}
                elseif follower_counts[t.unit_number] == min_followers then
                    table.insert(candidates, t)
                end
            end
    
            if #candidates > 0 then
                local random = game.create_random_generator()
                local selected_target = candidates[random(1, #candidates)]
                target = storage.creeperbots[selected_target.unit_number]
                target_unit_number = selected_target.unit_number
                party.follower_targets[creeper.unit_number] = target_unit_number
                --game.print("Debug: Follower " .. creeper.unit_number .. " assigned to " .. selected_target.type .. " unit: " .. target_unit_number .. " (followers: " .. (follower_counts[target_unit_number] + 1) .. ")")
            end
        end
    
        if target and target.entity and target.entity.valid then
            local current_follow_target = creeper.entity.follow_target
            --game.print("Debug: Follower " .. creeper.unit_number .. " current follow_target: " .. (current_follow_target and (current_follow_target.valid and "valid" or "invalid") or "none"))
    
            local success, err = pcall(function()
                creeper.entity.follow_target = target.entity
                creeper.entity.follow_offset = nil -- because the offset is not set it is not success to clears follow targets (but it claars teh storage of follow targets, not the actual follow targets fromthe factorio api)
                --game.print("Debug: Follower " .. creeper.unit_number .. " setting follow_target to unit " .. target_unit_number)
            end)
            if not success then
                --game.print("Error: Follower " .. creeper.unit_number .. " failed to set follow_target to unit " .. target_unit_number .. ", error: " .. tostring(err))
                --party.follower_targets[creeper.unit_number] = nil -- by commenting this out, the bots assign to the potential targets as intended so we dont need to cancle the follow if the offset is not there, thats a bit myuch
                --game.print("Debug: Follower " .. creeper.unit_number .. " cleared follower_targets due to follow_target failure")
            else
                --game.print("Debug: Follower " .. creeper.unit_number .. " follow_target successfully set to unit " .. target_unit_number)
            end
        else
            party.follower_targets[creeper.unit_number] = nil
            --game.print("Debug: Follower " .. creeper.unit_number .. " no valid target (leader or guard), cleared follower_targets")
        end
    end
end

function handle_grouping_state(creeper, event, position, entity, surface, tier, party)
    update_color(entity, creeper.is_guard and "guard" or "grouping")

    storage.parties = storage.parties or {}

    if not creeper.grouping_initialized then
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
                visited_chunks = {}
            }
            storage.parties[party_id] = party
            creeper.party_id = party_id
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
        game.print("Error: Party not found for unit " .. creeper.unit_number .. ", resetting grouping")
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
        game.print("Debug: Leader invalid, unit " .. creeper.unit_number .. " became leader")
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

    local guard_count = 0
    if #members >= 6 then guard_count = 5
    elseif #members >= 5 then guard_count = 4
    elseif #members >= 4 then guard_count = 3
    elseif #members >= 3 then guard_count = 2
    elseif #members >= 2 then guard_count = 1
    end
    local current_guards = #guards

    if current_guards < guard_count then
        local candidates = {}
        for _, member in ipairs(members) do
            if member.state == "grouping" and not member.is_leader and not member.is_guard then
                table.insert(candidates, member)
            end
        end
        table.sort(candidates, function(a, b) return a.tier < b.tier end)
        
        for _, candidate in ipairs(candidates) do
            if current_guards < guard_count then
                candidate.is_guard = true
                update_color(candidate.entity, "guard")
                current_guards = current_guards + 1
                table.insert(guards, candidate)
                game.print("Debug: Unit " .. candidate.unit_number .. " became guard")
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
                        game.print("Debug: Swapped guard " .. guard.unit_number .. " with " .. new_member.unit_number)
                        break
                    end
                end
            end
        end
    end

    local guard_positions = {}
    local guard_count = #guards
    if guard_count == 1 then
        guard_positions = {{angle = 180, radius = 3}}
    elseif guard_count == 2 then
        guard_positions = {{angle = 90, radius = 4}, {angle = 270, radius = 4}}
    elseif guard_count == 3 then
        guard_positions = {{angle = 120, radius = 5}, {angle = 240, radius = 5}, {angle = 0, radius = 5}}
    elseif guard_count == 4 then
        guard_positions = {{angle = 45, radius = 6}, {angle = 135, radius = 6}, {angle = 225, radius = 6}, {angle = 315, radius = 6}}
    elseif guard_count >= 5 then
        guard_positions = {{angle = 0, radius = 8}, {angle = 72, radius = 8}, {angle = 144, radius = 8}, {angle = 216, radius = 8}, {angle = 288, radius = 8}}
    end

    if current_guards > 0 and current_guards <= guard_count then
        for i, guard in ipairs(guards) do
            if guard.entity and guard.entity.valid then
                local pos = guard_positions[i] or {angle = 180, radius = 3}
                local dest_pos = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                }
                local dist_to_current = math.sqrt((dest_pos.x - guard.entity.position.x)^2 + (dest_pos.y - guard.entity.position.y)^2)
                if dist_to_current >= 3 and (not guard.last_path_request or event.tick >= guard.last_path_request + 60) then
                    schedule_autopilot_destination(guard, {dest_pos}, event.tick + 30, false)
                    guard.last_path_request = event.tick
                    game.print("Debug: Guard " .. guard.unit_number .. " scheduled autopilot to (" .. dest_pos.x .. "," .. dest_pos.y .. ")")
                end
            end
        end
    end

    if event.tick % 60 == 0 then
        for _, guard in ipairs(guards) do
            if guard.entity and guard.entity.valid then
                local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[guard.unit_number]
                if not queue and #guard.entity.autopilot_destinations > 0 then
                    guard.entity.autopilot_destination = nil
                   -- game.print("Debug: Guard " .. guard.unit_number .. " cleared autopilot_destination")
                end
            end
        end
    end

    if event.tick % 60 == 0 and guard_count > 0 then
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
                    if dist_to_dest > 3 then
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
                if dist1 >= 3 then
                    schedule_autopilot_destination(swap_guard, {dest_pos1}, event.tick + 30, false)
                    swap_guard.last_path_request = event.tick
                    game.print("Debug: Swapped guard " .. swap_guard.unit_number .. " to (" .. dest_pos1.x .. "," .. dest_pos1.y .. ")")
                end
                
                local dist2 = math.sqrt((dest_pos2.x - out_of_position.entity.position.x)^2 + (dest_pos2.y - out_of_position.entity.position.y)^2)
                if dist2 >= 3 then
                    schedule_autopilot_destination(out_of_position, {dest_pos2}, event.tick + 30, false)
                    out_of_position.last_path_request = event.tick
                    game.print("Debug: Swapped guard " .. out_of_position.unit_number .. " to (" .. dest_pos2.x .. "," .. dest_pos2.y .. ")")
                end
            end
        end
    end

    local random = game.create_random_generator()
    for _, member in ipairs(members) do
        if member.state == "grouping" and not member.is_leader and not member.is_guard and member.entity and member.entity.valid then
            local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[member.unit_number]
            if not queue and #member.entity.autopilot_destinations == 0 and random() <= 0.3 then
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
                    game.print("Debug: Follower " .. member.unit_number .. " scheduled random destination (" .. destinations[1].x .. "," .. destinations[1].y .. ")")
                end
            end
        end
    end

    if not party.started_scouting and party.grouping_start_tick and event.tick >= party.grouping_start_tick + 1200 and #members >= 3 then
        party.started_scouting = true
        party.state = "scouting"
        party.follower_targets = party.follower_targets or {}
    
        for _, member in ipairs(members) do
            if member.entity and member.entity.valid then
                member.state = member.is_guard and "guard" or "scouting"
                update_color(member.entity, member.state)
                --game.print("Debug: Unit " .. member.unit_number .. " transitioned to state " .. member.state)
            end
        end
    
        if creeper.is_leader then
            entity.autopilot_destination = nil
            local target_pos = get_unvisited_chunk(entity.position, party)
            if target_pos.x ~= entity.position.x or target_pos.y ~= entity.position.y then
                request_multiple_paths(entity.position, target_pos, party, surface, creeper.unit_number)
                --game.print("Debug: Leader " .. creeper.unit_number .. " set path to (" .. target_pos.x .. "," .. target_pos.y .. ")")
            else
                game.print("Error: Leader " .. creeper.unit_number .. " no valid chunk found")
            end
        end
    end
    
end

function handle_preparing_to_attack_state(creeper, event, position, entity, surface, tier, party)
    update_color(entity, "preparing_to_attack")
    --game.print("Debug: Unit " .. creeper.unit_number .. " in preparing_to_attack state, tick: " .. event.tick)

    if not party then
        --game.print("Error: Party not found for unit " .. creeper.unit_number .. ", reverting to grouping, tick: " .. event.tick)
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
        --game.print("Debug: Unit " .. creeper.unit_number .. " became leader due to invalid leader, tick: " .. event.tick)
    end

    if creeper.is_leader then
        entity.autopilot_destination = nil
        if storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] then
            storage.scheduled_autopilots[entity.unit_number] = nil
            --game.print("Debug: Cleared scheduled autopilot for leader " .. creeper.unit_number .. ", tick: " .. event.tick)
        end
    end

    local members = {}
    local distractors = {}
    for unit_number, member in pairs(storage.creeperbots or {}) do
        if member.party_id == creeper.party_id and member.entity and member.entity.valid then
            table.insert(members, member)
            if member.is_distractor then
                table.insert(distractors, member)
                --game.print("Debug: Unit " .. member.unit_number .. " added as distractor for party " .. creeper.party_id .. ", tick: " .. event.tick)
            end
        end
    end
    --game.print("Debug: Party " .. creeper.party_id .. " - Members: " .. #members .. ", Distractors: " .. #distractors .. ", tick: " .. event.tick)

    if #members == 1 and creeper.is_leader then
        entity.autopilot_destination = nil
        --game.print("Debug: Leader " .. creeper.unit_number .. " alone, cleared autopilot_destination, tick: " .. event.tick)
        return
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

    -- Assign new distractors if needed
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
                --game.print("Debug: Unit " .. candidate.unit_number .. " became distractor, tick: " .. event.tick)
            end
        end

        if current_distractors > 0 then
            local new_members = {}
            for _, member in ipairs(members) do
                if member.state == "preparing_to_attack" and not member.is_leader and not member.is_distractor then
                    table.insert(new_members, member)
                end
            end
            table.sort(new_members, function(a, b) return a.tier < b.tier end)

            for _, new_member in ipairs(new_members) do
                for i = #distractors, 1, -1 do
                    local distractor = distractors[i]
                    if distractor.distract_start_tick and distractor.distract_end_tick and event.tick < distractor.distract_end_tick then
                        --game.print("Debug: Skipping distractor swap for unit " .. distractor.unit_number .. " during distraction phase, tick: " .. event.tick)
                    elseif distractor.tier > new_member.tier then
                        distractor.is_distractor = false
                        update_color(distractor.entity, "preparing_to_attack")
                        new_member.is_distractor = true
                        new_member.distract_start_tick = event.tick
                        new_member.distract_end_tick = event.tick + 600
                        update_color(new_member.entity, "distractor")
                        distractors[i] = new_member
                        --game.print("Debug: Swapped distractor " .. distractor.unit_number .. " with " .. new_member.unit_number .. ", new distractor initialized with start_tick: " .. new_member.distract_start_tick .. ", end_tick: " .. new_member.distract_end_tick .. ", tick: " .. event.tick)
                        break
                    end
                end
            end
        end
    end

    -- Assign distractor positions
    local distractor_positions = {}
    local distractor_total = #distractors
    if distractor_total == 1 then
        distractor_positions = {{angle = 180, radius = 3}}
    elseif distractor_total == 2 then
        distractor_positions = {{angle = 90, radius = 4}, {angle = 270, radius = 4}}
    elseif distractor_total == 3 then
        distractor_positions = {{angle = 120, radius = 5}, {angle = 240, radius = 5}, {angle = 0, radius = 5}}
    elseif distractor_total == 4 then
        distractor_positions = {{angle = 45, radius = 6}, {angle = 135, radius = 6}, {angle = 225, radius = 6}, {angle = 315, radius = 6}}
    elseif distractor_total >= 5 then
        distractor_positions = {{angle = 0, radius = 8}, {angle = 72, radius = 8}, {angle = 144, radius = 8}, {angle = 216, radius = 8}, {angle = 288, radius = 8}}
    end

    -- Distractor positioning
    if current_distractors > 0 and current_distractors <= distractor_count then
        for i, distractor in ipairs(distractors) do
            if distractor.entity and distractor.entity.valid and distractor.state == "preparing_to_attack" then
                local pos = distractor_positions[i] or {angle = 180, radius = 3}
                local dest_pos = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                }
                local dist_to_current = calculate_distance(distractor.entity.position, dest_pos)
                if dist_to_current >= 3 then
                    schedule_autopilot_destination(distractor, {dest_pos}, event.tick + 30, false)
                    --game.print("Debug: Distractor " .. distractor.unit_number .. " scheduled autopilot to (" .. dest_pos.x .. "," .. dest_pos.y .. "), tick: " .. event.tick)
                end
            end
        end
    end

    -- Clear conflicting waypoints every 60 ticks
    if event.tick % 60 == 0 then
        for _, distractor in ipairs(distractors) do
            if distractor.entity and distractor.entity.valid then
                local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[distractor.unit_number]
                if not queue and #distractor.entity.autopilot_destinations > 0 then
                    distractor.entity.autopilot_destination = nil
                    --game.print("Debug: Distractor " .. distractor.unit_number .. " cleared autopilot_destination")
                end
            end
        end
    end

    if event.tick % 60 == 0 and distractor_count > 0 then
        local random = game.create_random_generator()
        local out_of_position = nil
        local out_of_position_index = nil

        for i, distractor in ipairs(distractors) do
            if distractor.entity and distractor.entity.valid then
                local pos = distractor_positions[i] or {angle = 180, radius = 3}
                local dest_pos = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                }
                local dist_to_dest = calculate_distance(distractor.entity.position, dest_pos)
                if dist_to_dest > 3 then
                    out_of_position = distractor
                    out_of_position_index = i
                    break
                end
            end
        end

        if out_of_position then
            local stationary_distractors = {}
            for i, distractor in ipairs(distractors) do
                if distractor.entity and distractor.entity.valid and i ~= out_of_position_index then
                    if #distractor.entity.autopilot_destinations == 0 then
                        table.insert(stationary_distractors, {distractor = distractor, index = i})
                    end
                end
            end

            if #stationary_distractors > 0 then
                local swap = stationary_distractors[random(1, #stationary_distractors)]
                local swap_distractor = swap.distractor
                local swap_index = swap.index

                distractors[out_of_position_index], distractors[swap_index] = swap_distractor, out_of_position

                local pos1 = distractor_positions[out_of_position_index] or {angle = 180, radius = 3}
                local dest_pos1 = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos1.angle)) * pos1.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos1.angle)) * pos1.radius)
                }
                local pos2 = distractor_positions[swap_index] or {angle = 180, radius = 3}
                local dest_pos2 = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos2.angle)) * pos2.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos2.angle)) * pos2.radius)
                }
                local dist1 = calculate_distance(swap_distractor.entity.position, dest_pos1)
                if dist1 >= 3 then
                    schedule_autopilot_destination(swap_distractor, {dest_pos1}, event.tick + 30, false)
                    swap_distractor.last_path_request = event.tick
                    --game.print("Debug: Swapped distractor " .. swap_distractor.unit_number .. " path request " .. (path_success and "succeeded" or "failed") .. " to (" .. dest_pos1.x .. "," .. dest_pos1.y .. "), tick: " .. event.tick)
                end

                local dist2 = calculate_distance(out_of_position.entity.position, dest_pos2)
                if dist2 >= 3 then
                    schedule_autopilot_destination(out_of_position, {dest_pos2}, event.tick + 30, false)
                    out_of_position.last_path_request = event.tick
                    --game.print("Debug: Swapped distractor " .. out_of_position.unit_number .. " path request " .. (path_success and "succeeded" or "failed") .. " to (" .. dest_pos2.x .. "," .. dest_pos2.y .. "), tick: " .. event.tick)
                end
            end
        end
    end

    -- Non-distractor followers move to leader
    if not party.attack_initiated and not creeper.is_leader and not creeper.is_distractor then
        -- Log leader details
        local leader = storage.creeperbots[party.grouping_leader]
        if leader and leader.entity and leader.entity.valid then
            --game.print("Debug: Leader unit_number: " .. party.grouping_leader .. ", position: (" .. leader_pos.x .. "," .. leader_pos.y .. "), tick: " .. event.tick)
        else
            --game.print("Debug: Invalid leader for party " .. creeper.party_id .. ", unit_number: " .. party.grouping_leader .. ", tick: " .. event.tick)
        end
    
        -- Log follower follow_target before clearing
        --game.print("Debug: Follower " .. creeper.unit_number .. " follow_target before clear: " .. (creeper.follow_target and creeper.follow_target.unit_number or "none") .. ", tick: " .. event.tick)
        
        creeper.follow_target = nil
        
        -- Log follower follow_target after clearing
        --game.print("Debug: Follower " .. creeper.unit_number .. " follow_target after clear: " .. (creeper.follow_target and creeper.follow_target.unit_number or "none") .. ", tick: " .. event.tick)
        
        local dist_to_leader = calculate_distance(position, leader_pos)
        if dist_to_leader > 3 then
            local dest_pos = {
                x = math.floor(leader_pos.x),
                y = math.floor(leader_pos.y)
            }
            schedule_autopilot_destination(creeper, {dest_pos}, event.tick + 30, false)
        end
    end

    -- Elect closest distractor
    if not party.preparation_start_tick then
        party.preparation_start_tick = event.tick
        --game.print("Debug: Set party.preparation_start_tick to " .. event.tick .. " for party " .. creeper.party_id .. ", tick: " .. event.tick)
    end
    if event.tick >= party.preparation_start_tick + 240 and (not party.last_distractor_election_tick or event.tick >= party.last_distractor_election_tick + 1200) then
        local target, target_type = scan_for_enemies(leader_pos, surface, tier_configs[entity.name].max_targeting)
        local closest_distractor = nil
        local min_distance = math.huge
        if target and target_type == "nest" then
            for i, distractor in ipairs(distractors) do
                if distractor.entity and distractor.entity.valid and distractor.state == "preparing_to_attack" then
                    local pos = distractor_positions[i] or {angle = 180, radius = 3}
                    local guard_pos = {
                        x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                        y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                    }
                    local dist_to_guard = calculate_distance(distractor.entity.position, guard_pos)
                    if dist_to_guard < 3 then
                        local dist_to_target = calculate_distance(distractor.entity.position, target.position)
                        if dist_to_target < min_distance then
                            min_distance = dist_to_target
                            closest_distractor = distractor
                        end
                    end
                end
            end
        end
        if closest_distractor then
            local dist_to_target = calculate_distance(closest_distractor.entity.position, target.position)
            local angle = math.atan2(target.position.y - closest_distractor.entity.position.y, target.position.x - closest_distractor.entity.position.x)
            local distract_pos = {
                x = math.floor(closest_distractor.entity.position.x + math.cos(angle) * 3),
                y = math.floor(closest_distractor.entity.position.y + math.sin(angle) * 3)
            }
            closest_distractor.autopilot_destination = nil
            --schedule_autopilot_destination(closest_distractor, {distract_pos}, event.tick, false)
            closest_distractor.state = "distractor"
            -- can we loh
            handle_distractor_state(closest_distractor, event, closest_distractor.entity.position, closest_distractor.entity, surface, tier_configs[entity.name], party)
            closest_distractor.distract_start_tick = event.tick
            closest_distractor.distract_end_tick = event.tick + 600
            party.last_distractor_election_tick = event.tick
            --game.print("Debug: Closest distractor elected: Unit " .. closest_distractor.unit_number .. ", distance to nest: " .. min_distance .. ", in guard position after 3s delay, scheduled autopilot to (" .. distract_pos.x .. "," .. distract_pos.y .. "), tick: " .. event.tick)
            -- the above logic succesfully elects the distractors and sends them in, subsequent distractors have issues with their logic
        end
    else
        --game.print("Debug: Waiting for conditions, party.preparation_start_tick: " .. (party.preparation_start_tick or "nil") .. ", last_distractor_election_tick: " .. (party.last_distractor_election_tick or "nil") .. ", current tick: " .. event.tick .. ", party: " .. creeper.party_id)
    end

    -- Replace distractor after attack initiation
    if closest_distractor and party.attack_initiated and current_distractors <= distractor_count then
        local non_distractors = {}
        for _, member in ipairs(members) do
            if member.entity and member.entity.valid and not member.is_leader and not member.is_distractor and member.state == "preparing_to_attack" then
                table.insert(non_distractors, member)
            end
        end
        table.sort(non_distractors, function(a, b) return a.tier < b.tier end)
        if #non_distractors > 0 and #distractors < distractor_count then
            local new_distractor = non_distractors[1]
            new_distractor.is_distractor = true
            table.insert(distractors, new_distractor)
            local target, target_type = scan_for_enemies(leader_pos, surface, tier_configs[entity.name].max_targeting)
            if target and target_type == "nest" then
                local dist_to_target = calculate_distance(new_distractor.entity.position, target.position)
                local angle = math.atan2(target.position.y - new_distractor.entity.position.y, target.position.x - new_distractor.entity.position.x)
                local distract_pos = {
                    x = math.floor(new_distractor.entity.position.x + math.cos(angle) * 3),
                    y = math.floor(new_distractor.entity.position.y + math.sin(angle) * 3)
                }         
                new_distractor.autopilot_destination = nil
                new_distractor.diversion_position = distract_pos
                new_distractor.state = "distractor"
                handle_distractor_state(new_distractor, event, new_distractor.entity.position, new_distractor.entity, surface, tier_configs[entity.name], party)
                new_distractor.distract_start_tick = event.tick
                new_distractor.distract_end_tick = event.tick + 600
                --game.print("Debug: Unit " .. new_distractor.unit_number .. " replaced distractor, transitioned to distractor state, diversion_position: (" .. distract_pos.x .. "," .. distract_pos.y .. "), tick: " .. event.tick)
            else
                --game.print("Debug: No valid nest target for new distractor " .. new_distractor.unit_number .. ", remaining in distractor state, tick: " .. event.tick)
            end
        end
    end

    -- Handle out-of-position distractors
    if event.tick % 60 == 0 and distractor_count > 0 then
        local random = game.create_random_generator()
        local out_of_position = nil
        local out_of_position_index = nil

        for i, distractor in ipairs(distractors) do
            if distractor.entity and distractor.entity.valid then
                local pos = distractor_positions[i] or {angle = 180, radius = 3}
                local dest_pos = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                }
                local dist_to_dest = calculate_distance(distractor.entity.position, dest_pos)
                if dist_to_dest > 3 then
                    out_of_position = distractor
                    out_of_position_index = i
                    break
                end
            end
        end

        if out_of_position then
            local stationary_distractors = {}
            for i, distractor in ipairs(distractors) do
                if distractor.entity and distractor.entity.valid and i ~= out_of_position_index then
                    if #distractor.entity.autopilot_destinations == 0 then
                        table.insert(stationary_distractors, {distractor = distractor, index = i})
                    end
                end
            end

            if #stationary_distractors > 0 then
                local swap = stationary_distractors[random(1, #stationary_distractors)]
                local swap_distractor = swap.distractor
                local swap_index = swap.index
            
                distractors[out_of_position_index], distractors[swap_index] = swap_distractor, out_of_position
            
                local pos1 = distractor_positions[out_of_position_index] or {angle = 180, radius = 3}
                local dest_pos1 = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos1.angle)) * pos1.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos1.angle)) * pos1.radius)
                }
                local pos2 = distractor_positions[swap_index] or {angle = 180, radius = 3}
                local dest_pos2 = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos2.angle)) * pos2.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos2.angle)) * pos2.radius)
                }
            
                local dist1 = calculate_distance(swap_distractor.entity.position, dest_pos1)
                if dist1 >= 3 then
                    schedule_autopilot_destination(swap_distractor, {dest_pos1}, event.tick, false)
                    --game.print("Debug: Swapped distractor " .. swap_distractor.unit_number .. " scheduled autopilot to (" .. dest_pos1.x .. "," .. dest_pos1.y .. "), tick: " .. event.tick)
                end
            
                local dist2 = calculate_distance(out_of_position.entity.position, dest_pos2)
                if dist2 >= 3 then
                    schedule_autopilot_destination(out_of_position, {dest_pos2}, event.tick, false)
                   -- game.print("Debug: Swapped distractor " .. out_of_position.unit_number .. " scheduled autopilot to (" .. dest_pos2.x .. "," .. dest_pos2.y .. "), tick: " .. event.tick)
                end
            end
        end
    end

    -- Assign spawner targets
    local assignments = {}
    --game.print("Debug: Starting assignments for party " .. creeper.party_id .. ", current tick: " .. event.tick .. ", preparation_start_tick: " .. (party.preparation_start_tick or "none") .. ", last_distractor_election_tick: " .. (party.last_distractor_election_tick or "none") .. ", attack_initiated: " .. tostring(party.attack_initiated) .. ", target: " .. (target and "(" .. target.position.x .. "," .. target.position.y .. ")" or "none") .. ", target_type: " .. (target_type or "none"))

    -- Ensure group target is set if missing (nests or spitters within 150 tiles)
    if not target or (target_type ~= "nest" and target_type ~= "spitter") then
        local nests = surface.find_entities_filtered({
            type = "unit-spawner",
            position = creeper.entity.position,
            radius = 150,
            force = "enemy"
        })
        if #nests > 0 and nests[1].valid then
            target = nests[1]
            target_type = "nest"
            game.print("Debug: Assigned group nest target at (" .. target.position.x .. "," .. target.position.y .. ") for party " .. creeper.party_id .. ", tick: " .. event.tick)
        else
            local spitters = surface.find_entities_filtered({
                type = "turret",
                position = creeper.entity.position,
                radius = 150,
                force = "enemy"
            })
            if #spitters > 0 and spitters[1].valid then
                target = spitters[1]
                target_type = "spitter"
                game.print("Debug: Assigned group spitter target at (" .. target.position.x .. "," .. target.position.y .. ") for party " .. creeper.party_id .. ", tick: " .. event.tick)
            else
                game.print("Debug: No valid nest or spitter within 150 tiles of unit " .. creeper.unit_number .. " at (" .. creeper.entity.position.x .. "," .. creeper.entity.position.y .. "), tick: " .. event.tick)
            end
        end
    end

    if event.tick >= (party.preparation_start_tick or event.tick) + 300 and not party.attack_initiated and (party.last_distractor_election_tick or event.tick) + 180 <= event.tick then
        game.print("Debug: Entered assignment block for party " .. creeper.party_id .. ", target: " .. (target and "(" .. target.position.x .. "," .. target.position.y .. ")" or "none") .. ", target_type: " .. (target_type or "none"))
        if target and (target_type == "nest" or target_type == "spitter") then
            local total_damage = 0
            local bot_configs = {}
            for _, member in ipairs(members) do
                if member.entity and member.entity.valid and member.state ~= "distractor" then
                    local config = tier_configs[member.entity.name]
                    total_damage = total_damage + config.damage
                    table.insert(bot_configs, {member = member, damage = config.damage, tier = config.tier})
                end
            end
            --game.print("Debug: Party " .. creeper.party_id .. " total damage: " .. total_damage .. ", tick: " .. event.tick)

            table.sort(bot_configs, function(a, b) return a.tier < b.tier end)
            local bot_config_log = {}
            for _, bot in ipairs(bot_configs) do
                table.insert(bot_config_log, "unit=" .. bot.member.unit_number .. ",tier=" .. bot.tier .. ",damage=" .. bot.damage)
            end
            --game.print("Debug: Party " .. creeper.party_id .. " sorted bot configs: [" .. table.concat(bot_config_log, "; ") .. "], tick: " .. event.tick)

            local spawner_targets = {}
            if target_type == "nest" then
                local spawners = surface.find_entities_filtered({
                    type = "unit-spawner",
                    position = target.position,
                    radius = 20,
                    force = "enemy"
                })
                for _, spawner in ipairs(spawners) do
                    if spawner.valid and spawner.health > 0 then
                        table.insert(spawner_targets, {entity = spawner, health = spawner.health, position = spawner.position})
                    end
                end
            elseif target_type == "spitter" then
                table.insert(spawner_targets, {entity = target, health = target.health, position = target.position})
            end
            local spawner_log = {}
            for _, spawner in ipairs(spawner_targets) do
                table.insert(spawner_log, "(" .. spawner.position.x .. "," .. spawner.position.y .. "),health=" .. spawner.health)
            end
            game.print("Debug: Found " .. #spawner_targets .. " targets near " .. target_type .. " at (" .. target.position.x .. "," .. target.position.y .. "): [" .. (table.concat(spawner_log, "; ") or "none") .. "], tick: " .. event.tick)

            for _, bot in ipairs(bot_configs) do
                if #spawner_targets > 0 then
                    local target_spawner = spawner_targets[1]
                    assignments[bot.member.unit_number] = target_spawner.position
                    bot.member.target = target_spawner.entity
                    bot.member.target_position = target_spawner.position
                    bot.member.target_health = target_spawner.health
                    bot.member.state = "approaching"
                    game.print("Debug: Assigned " .. target_type .. " at (" .. target_spawner.position.x .. "," .. target_spawner.position.y .. ") to unit " .. bot.member.unit_number .. " (" .. bot.member.entity.name .. "), health: " .. target_spawner.health .. ", set state=approaching, tick: " .. event.tick)
                    target_spawner.health = target_spawner.health - bot.damage
                    if target_spawner.health <= 0 then
                        table.remove(spawner_targets, 1)
                        game.print("Debug: " .. target_type .. " at (" .. target_spawner.position.x .. "," .. target_spawner.position.y .. ") depleted, removed from targets, tick: " .. event.tick)
                    end
                else
                    assignments[bot.member.unit_number] = target.position
                    bot.member.target = target
                    bot.member.target_position = target.position
                    bot.member.target_health = target.health
                    bot.member.state = "approaching"
                    game.print("Debug: Assigned " .. target_type .. " at (" .. target.position.x .. "," .. target.position.y .. ") to unit " .. bot.member.unit_number .. " (" .. bot.member.entity.name .. "), health: " .. target.health .. ", set state=approaching, tick: " .. event.tick)
                end
            end
        else
            game.print("Debug: Assignment skipped for party " .. creeper.party_id .. ": target=" .. (target and "valid" or "nil") .. ", target_type=" .. (target_type or "none") .. ", tick: " .. event.tick)
        end
    end
end

-- Updated handle_distractor_state
function handle_distractor_state(creeper, event, position, entity, surface, tier, party)
    --game.print("Debug: Unit " .. creeper.unit_number .. " in distractor state")
    update_color(entity, "distractor")

    -- Store original party_id and leave party
    if creeper.party_id and not creeper.original_party_id then
        creeper.original_party_id = creeper.party_id
        local party = storage.parties[creeper.party_id]
        if party then
            party.members = party.members or {}
            party.members[creeper.unit_number] = nil
            --game.print("Debug: Distractor " .. creeper.unit_number .. " left party " .. creeper.party_id)
        end
        creeper.party_id = nil
    end

    -- Initialize distraction timing
    if not creeper.distract_start_tick or not creeper.distract_end_tick then
        creeper.distract_start_tick = event.tick
        creeper.distract_end_tick = event.tick + 600
        --game.print("Debug: Initialized distraction timing for distractor " .. creeper.unit_number .. ", start_tick: " .. creeper.distract_start_tick .. ", end_tick: " .. creeper.distract_end_tick)
    end

    -- Assign or validate target
    creeper.target = nil
    if not creeper.target or not creeper.target.valid then
        local spawners = surface.find_entities_filtered{
                            -- this fails on the second distractor, successful on the third and 4th, and 5th,
                            -- it seems the second distractor cant path to the thing because its half leaning over a lake
            type = "unit-spawner",
            position = position,
            radius = 150,
            force = "enemy"
        }
        for _, spawner in ipairs(spawners) do
            if spawner.valid and spawner.health > 0 then
                creeper.target = spawner
                creeper.target_position = spawner.position
                creeper.target_health = spawner.health

                game.print("Debug: Distractor " .. creeper.unit_number .. " assigned target at (" .. spawner.position.x .. "," .. spawner.position.y .. ")")
                break
            end
        end
        if not creeper.target then
            if event.tick >= creeper.distract_start_tick + 300 then
                game.print("Debug: No valid target for distractor " .. creeper.unit_number .. " after timeout, reverting to grouping")
                creeper.state = "grouping"
                creeper.target = nil
                creeper.target_position = nil
                creeper.target_health = nil
                creeper.diversion_position = nil
                update_color(entity, "grouping")
                if creeper.original_party_id and storage.parties[creeper.original_party_id] then
                    creeper.party_id = creeper.original_party_id
                    storage.parties[creeper.party_id].members = storage.parties[creeper.party_id].members or {}
                    storage.parties[creeper.party_id].members[creeper.unit_number] = creeper
                   -- game.print("Debug: Distractor " .. creeper.unit_number .. " rejoined party " .. creeper.party_id)
                end
                return
            end
            --game.print("Debug: No valid target for distractor " .. creeper.unit_number .. ", retrying")
            return
        end
    elseif not creeper.target.valid then
        --game.print("creeper target not valid")
    end

    -- Update target health
    creeper.target_health = creeper.target.health

    -- Check for nearby enemies to explode
    local enemies = surface.find_entities_filtered{
        position = position,
        radius = 15,
        force = "enemy",
        type = "unit"
    }
    local nearest_enemy = nil
    local nearest_distance = 15
    for _, enemy in pairs(enemies) do
        local distance = calculate_distance(position, enemy.position)
        if distance < nearest_distance then
            nearest_distance = distance
            nearest_enemy = enemy
        end
    end
    if nearest_enemy and nearest_distance <= 5 then
        creeper.state = "exploding"
        --game.print("Debug: Distractor " .. creeper.unit_number .. " transitioning to exploding near enemy at (" .. nearest_enemy.position.x .. "," .. nearest_enemy.position.y .. ")")
        return
    end

    -- End distraction phase and rejoin party
    if event.tick >= creeper.distract_end_tick then
        --game.print("Debug: Distractor " .. creeper.unit_number .. " ended distraction phase, reverting to grouping")
        creeper.state = "grouping"
        creeper.diversion_position = nil
        update_color(entity, "grouping")
        if creeper.original_party_id and storage.parties[creeper.original_party_id] then
            creeper.party_id = creeper.original_party_id
            storage.parties[creeper.party_id].members = storage.parties[creeper.party_id].members or {}
            storage.parties[creeper.party_id].members[creeper.unit_number] = creeper
            --game.print("Debug: Distractor " .. creeper.unit_number .. " rejoined party " .. creeper.party_id)
        end
        return
    end
end

function handle_approaching_state(creeper, event, position, entity, surface, tier, party, has_valid_path)
    game.print("Debug: Unit " .. creeper.unit_number)

    if not creeper.target_position or not creeper.target_position.x or not creeper.target_position.y then
        game.print("Debug: Invalid target_position for unit " .. creeper.unit_number .. ", reverting to scouting, tick: " .. event.tick)
        creeper.state = "scouting"
        creeper.target = nil
        creeper.target_position = nil
        creeper.target_health = nil
        party.shared_target = nil
        clear_renderings(creeper)
        return false
    end

    -- Check if target entity is valid and has health
    local target_destroyed = not creeper.target or not creeper.target.valid or (creeper.target.valid and creeper.target.health <= 0)
    if target_destroyed then
        local spawners = surface.find_entities_filtered({
            type = "unit-spawner",
            position = creeper.target_position,
            radius = 50,
            force = "enemy"
        })
        local new_target = nil
        for _, spawner in ipairs(spawners) do
            if spawner.valid and spawner.health > 0 then
                new_target = spawner
                break
            end
        end
    else
        creeper.target_health = creeper.target.health
    end

    -- Calculate distance to target
    local dist_to_target = calculate_distance(position, creeper.target_position)
    game.print("Debug: Unit " .. creeper.unit_number .. " approaching target at (" .. creeper.target_position.x .. "," .. creeper.target_position.y .. "), dist_to_target: " .. dist_to_target .. ", health: " .. (creeper.target_health or "none") .. ", tick: " .. event.tick)

    -- Transition to exploding state if within explosion range
    local explosion_range = tier_configs[entity.name].radius or 3.5
    if dist_to_target <= 15 then -- distance to target shouold be target entity not target from storage
        creeper.state = "exploding"
        game.print("Debug: Unit " .. creeper.unit_number .. " within explosion range (" .. explosion_range .. "), transitioning to exploding, tick: " .. event.tick)
        return true
    end

    -- Check if bot is stuck
    if not entity.autopilot_destination and creeper.last_position and creeper.last_position_tick and event.tick >= creeper.last_position_tick + 120 and creeper.last_position.x == position.x and creeper.last_position.y == position.y then
        game.print("Debug: Unit " .. creeper.unit_number .. " stuck at (" .. position.x .. "," .. position.y .. "), tick: " .. event.tick)
        entity.autopilot_destination = nil
        local random = game.create_random_generator()
        local attempts = 0
        local max_attempts = 3
        local new_pos = nil
        while attempts < max_attempts do
            local angle = math.rad(random(0, 360))
            local distance = 3
            new_pos = {
                x = math.floor(position.x + math.cos(angle) * distance),
                y = math.floor(position.y + math.sin(angle) * distance)
            }
            local chunk_pos = {x = math.floor(new_pos.x / 32), y = math.floor(new_pos.y / 32)}
            if surface.is_chunk_generated(chunk_pos) and surface.can_place_entity{name = "character", position = new_pos} then
                break
            end
            game.print("Debug: Invalid new position for unit " .. creeper.unit_number .. " at (" .. new_pos.x .. "," .. new_pos.y .. "), attempt: " .. (attempts + 1) .. ", tick: " .. event.tick)
            attempts = attempts + 1
            new_pos = nil
        end
        if not new_pos then
            game.print("Debug: Failed to find new position for unit " .. creeper.unit_number .. " after " .. max_attempts .. " attempts, reverting to scouting, tick: " .. event.tick)
            creeper.state = "scouting"
            creeper.target = nil
            creeper.target_position = nil
            creeper.target_health = nil
            party.shared_target = nil
            clear_renderings(creeper)
            return false
        end
        schedule_autopilot_destination(creeper, {new_pos}, event.tick, false)
        creeper.autopilot_set_tick = event.tick
        creeper.last_position = nil
        creeper.last_position_tick = nil
        game.print("Debug: Unstuck successful for unit " .. creeper.unit_number .. ", new position: (" .. new_pos.x .. "," .. new_pos.y .. "), tick: " .. event.tick)
        return true
    end

    -- Update last position and tick
    creeper.last_position = {x = position.x, y = position.y}
    creeper.last_position_tick = event.tick

    -- Request path if needed
    if dist_to_target > 3 and (not creeper.last_path_request or event.tick >= creeper.last_path_request + 60) then
        local path_success = request_multiple_paths(position, creeper.target_position, party, surface, creeper.unit_number)
        game.print("Debug: Unit " .. creeper.unit_number .. " path request " .. (path_success and "succeeded" or "failed") .. " to target (" .. creeper.target_position.x .. "," .. creeper.target_position.y .. "), tick: " .. event.tick)
        if not path_success then
            game.print("Debug: Path request failed for unit " .. creeper.unit_number .. ", reverting to scouting, tick: " .. event.tick)
            creeper.state = "scouting"
            creeper.target = nil
            creeper.target_position = nil
            creeper.target_health = nil
            party.shared_target = nil
            clear_renderings(creeper)
            return false
        end
        creeper.last_path_request = event.tick
        creeper.autopilot_set_tick = event.tick
        return true
    end

    return true
end

-- Handler for exploding 
function handle_exploding_state(creeper, event, position, entity, surface, tier, party)
    --game.print("Debug: Unit " .. creeper.unit_number .. " in exploding state, tick: " .. game.tick)

    local entity = creeper.entity
    local position = entity.position
    local surface = entity.surface

    -- Validate tier
    if not tier or type(tier) ~= "table" or not tier.explosion then
        game.print("Debug: Invalid tier for unit " .. creeper.unit_number .. ", entity_name: " .. tostring(entity.name) .. ", tier: " .. tostring(tier) .. ", falling back to creeperbot-mk1, tick: " .. game.tick)
        tier = tier_configs["creeperbot-mk1"]
        -- this is failing
    end
    --game.print("Debug: Explosion details for unit " .. creeper.unit_number .. ": entity_name=" .. tostring(entity.name) .. ", explosion=" .. tier.explosion .. ", damage=" .. tier.damage .. ", radius=" .. tier.radius .. ", tick: " .. game.tick)

    -- Validate or assign target
    local new_target = nil
    local target_type = "none"
    if not creeper.target or not creeper.target.valid or (creeper.target.valid and creeper.target.health <= 0) then
        -- 1. Nests within 20 tiles
        local nests = surface.find_entities_filtered({
            type = "unit-spawner",
            position = position,
            radius = 20,
            force = "enemy"
        })
        for _, nest in ipairs(nests) do
            if nest.valid and nest.health > 0 then
                new_target = nest
                target_type = "nest"
                break
            end
        end

        -- 2. Turrets within 20 tiles
        if not new_target then
            local turrets = surface.find_entities_filtered({
                type = "turret",
                position = position,
                radius = 20,
                force = "enemy"
            })
            for _, turret in ipairs(turrets) do
                if turret.valid and turret.health > 0 then
                    new_target = turret
                    target_type = "turret"
                    break
                end
            end
        end

        -- 3. Nests within 40 tiles
        if not new_target then
            local nests = surface.find_entities_filtered({
                type = "unit-spawner",
                position = position,
                radius = 40,
                force = "enemy"
            })
            for _, nest in ipairs(nests) do
                if nest.valid and nest.health > 0 then
                    new_target = nest
                    target_type = "nest"
                    break
                end
            end
        end

        -- 4. Turrets within 40 tiles
        if not new_target then
            local turrets = surface.find_entities_filtered({
                type = "turret",
                position = position,
                radius = 40,
                force = "enemy"
            })
            for _, turret in ipairs(turrets) do
                if turret.valid and turret.health > 0 then
                    new_target = turret
                    target_type = "turret"
                    break
                end
            end
        end

        -- 5. Units within 40 tiles
        if not new_target then
            local units = surface.find_entities_filtered({
                type = "unit",
                position = position,
                radius = 40,
                force = "enemy"
            })
            for _, unit in ipairs(units) do
                if unit.valid and unit.health > 0 then
                    new_target = unit
                    target_type = "unit"
                    break
                end
            end
        end

        if new_target then
            creeper.target = new_target
            creeper.target_position = new_target.position
            creeper.target_health = new_target.health
            game.print("Debug: Unit " .. creeper.unit_number .. " selected new " .. target_type .. " target at (" .. new_target.position.x .. "," .. new_target.position.y .. "), health: " .. new_target.health .. ", tick: " .. game.tick)
        else
            game.print("Debug: No valid targets (nest, turret, or unit) found within 40 tiles for unit " .. creeper.unit_number .. ", reverting to scouting, tick: " .. game.tick)
            creeper.state = "scouting"
            creeper.target = nil
            creeper.target_position = nil
            creeper.target_health = nil
            party.shared_target = nil
            clear_renderings(creeper)
            return false
        end
    end

    -- Update target health
    if creeper.target and creeper.target.valid then
        creeper.target_health = creeper.target.health
    end

    -- Calculate distance to target
    local explosion_range = tier.radius or 3.5
    local dist_to_target = calculate_distance(position, creeper.target.position)
    --game.print("Debug: Unit " .. creeper.unit_number .. " distance to target at (" .. creeper.target.position.x .. "," .. creeper.target.position.y .. "): " .. dist_to_target .. ", explosion_range: " .. explosion_range .. ", tick: " .. game.tick)

    -- Check if within explosion range
    if dist_to_target <= 5 then
        --game.print("Debug: Unit " .. creeper.unit_number .. " within explosion range, executing explosion, tick: " .. game.tick)
        
        -- Create explosion
        if tier.explosion == "nuke-explosion" then
            surface.create_entity({name = "nuke-explosion", position = position})
            local cliffs = surface.find_entities_filtered{position = position, radius = 9, type = "cliff"}
            for _, cliff in pairs(cliffs) do
                cliff.destroy()
            end
            for _ = 1, 3 do
                surface.create_entity({name = "atomic-explosion", position = position})
            end
            if tier.extra_effect then
                surface.create_entity({name = tier.extra_effect, position = position})
            end
        else
            surface.create_entity({name = tier.explosion, position = position})
        end

        -- Clear renderings
        if creeper.render_ids then
            clear_renderings(creeper)
        end

        -- Damage target
        if creeper.target and creeper.target.valid then
           -- game.print("Debug: Damaging target " .. creeper.target.name .. " for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
            creeper.target.damage(tier.damage, entity.force)
        else
            --game.print("Debug: Target is no longer valid for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
        end

        -- Damage nearby enemies
        local nearby_enemies = surface.find_entities_filtered{position = position, radius = tier.radius, force = "enemy"}
        --game.print("Debug: Found " .. #nearby_enemies .. " enemies in blast radius for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
        for _, enemy in pairs(nearby_enemies) do
            if enemy.valid and enemy.health then
                local distance = calculate_distance(position, enemy.position)
                local damage = tier.damage - (distance * (tier.damage / tier.radius))
                if damage > 0 then
                    enemy.damage(damage, entity.force)
                end
            end
        end

        -- Clean up
        entity.destroy()
        remove_creeperbot(creeper.unit_number)
        return true
    end

    -- Check if bot is stuck
    if not creeper.autopilot_destination and creeper.last_position and creeper.last_position_tick and game.tick >= creeper.last_position_tick + 120 and creeper.last_position.x == position.x and creeper.last_position.y == position.y then -- line 1725
        game.print("Debug: Unit " .. creeper.unit_number .. " stuck at (" .. position.x .. "," .. position.y .. "), tick: " .. game.tick)
        creeper.autopilot_destination = nil
        local random = game.create_random_generator()
        local attempts = 0
        local max_attempts = 3
        local new_pos = nil
        while attempts < max_attempts do
            local angle = math.rad(random(0, 360))
            local distance = 3
            new_pos = {
                x = math.floor(position.x + math.cos(angle) * distance),
                y = math.floor(position.y + math.sin(angle) * distance)
            }
            local chunk_pos = {x = math.floor(new_pos.x / 32), y = math.floor(new_pos.y / 32)}
            if surface.is_chunk_generated(chunk_pos) and surface.can_place_entity{name = "character", position = new_pos} then
                break
            end
            game.print("Debug: Invalid new position for unit " .. creeper.unit_number .. " at (" .. new_pos.x .. "," .. new_pos.y .. "), attempt: " .. (attempts + 1) .. ", tick: " .. game.tick)
            attempts = attempts + 1
            new_pos = nil
        end
        if not new_pos then
            game.print("Debug: Failed to find new position for unit " .. creeper.unit_number .. " after " .. max_attempts .. " attempts, reverting to scouting, tick: " .. game.tick)
            creeper.state = "scouting"
            creeper.target = nil
            creeper.target_position = nil
            creeper.target_health = nil
            party.shared_target = nil
            clear_renderings(creeper)
            return false
        end
        schedule_autopilot_destination(creeper, {new_pos}, game.tick, false)
        creeper.autopilot_set_tick = game.tick
        creeper.last_position = nil
        creeper.last_position_tick = nil
        game.print("Debug: Unstuck successful for unit " .. creeper.unit_number .. ", new position: (" .. new_pos.x .. "," .. new_pos.y .. "), tick: " .. game.tick)
        return true
    end

    -- Update last position and tick
    creeper.last_position = {x = position.x, y = position.y}
    creeper.last_position_tick = game.tick

    -- Request path if needed
    if dist_to_target > explosion_range and (not creeper.last_path_request or game.tick >= creeper.last_path_request + 60) then
        local path_success = request_multiple_paths(position, creeper.target.position, party, surface, creeper.unit_number)
        game.print("Debug: Unit " .. creeper.unit_number .. " path request " .. (path_success and "succeeded" or "failed") .. " to target (" .. creeper.target.position.x .. "," .. creeper.target.position.y .. "), tick: " .. game.tick)
        if not path_success then
            game.print("Debug: Path request failed for unit " .. creeper.unit_number .. ", reverting to scouting, tick: " .. game.tick)
            creeper.state = "scouting"
            creeper.target = nil
            creeper.target_position = nil
            creeper.target_health = nil
            party.shared_target = nil
            clear_renderings(creeper)
            return false
        end
        creeper.last_path_request = game.tick
        creeper.autopilot_set_tick = game.tick
        return true
    end

    return true
end

function process_waypoints(creeper)
    --game.print("Debug: Entering process_waypoints for unit " .. (creeper.unit_number or "unknown") .. ", tick: " .. game.tick)
    
    local entity = creeper.entity
    local position = entity.position
    local surface = entity.surface
    
    if not entity or not entity.valid or not surface or not surface.valid then
        --game.print("Error: Invalid entity or surface for unit " .. (creeper.unit_number or "unknown") .. ", tick: " .. game.tick)
        return false
    end

    -- Handle distractor waypoints
    if creeper.state == "distractor" then
        --game.print("Debug: Processing distractor waypoints for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
        if not tier_configs[entity.name] then
           -- game.print("Error: Invalid tier config for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
            return false
        end
        --game.print("Debug: Tier config valid for unit " .. creeper.unit_number .. ", tier: " .. entity.name .. ", tick: " .. game.tick)

        local target_pos = creeper.diversion_position or creeper.target_position
        if not target_pos or not target_pos.x or not target_pos.y then
            game.print("Debug: Invalid target_pos for distractor " .. creeper.unit_number .. ", target_pos: " .. tostring(target_pos))
            return false
        end

        local dist_to_target = calculate_distance(position, target_pos)
        --game.print("Debug: Distractor " .. creeper.unit_number .. ", dist_to_target: " .. dist_to_target .. ", target_pos: (" .. target_pos.x .. "," .. target_pos.y .. "), diversion_position: " .. (creeper.diversion_position and "(" .. creeper.diversion_position.x .. "," .. creeper.diversion_position.y .. ")" or "none"))

        -- Check if bot is stuck
        --game.print("Debug: Stuck check for unit " .. creeper.unit_number .. ": autopilot_destination=" .. (entity.autopilot_destination and "(" .. entity.autopilot_destination.x .. "," .. entity.autopilot_destination.y .. ")" or "none") .. ", last_position=" .. (creeper.last_position and "(" .. creeper.last_position.x .. "," .. creeper.last_position.y .. ")" or "none") .. ", last_position_tick=" .. (creeper.last_position_tick or "none") .. ", game.tick=" .. game.tick .. ", position=(" .. position.x .. "," .. position.y .. "), tick_check=" .. (creeper.last_position_tick and tostring(game.tick >= creeper.last_position_tick + 120) or "false") .. ", position_match=" .. (creeper.last_position and tostring(creeper.last_position.x == position.x and creeper.last_position.y == position.y) or "false"))
        -- solved because autopilot destinatino was nil
        -- distractor state logic reinitiated the attack
        if not entity.autopilot_destination and creeper.last_position and creeper.last_position_tick and game.tick >= creeper.last_position_tick and creeper.last_position.x == position.x and creeper.last_position.y == position.y then
            --game.print("Stuck: Distractor " .. creeper.unit_number .. " stuck at (" .. position.x .. "," .. position.y .. "), tick: " .. game.tick)
            creeper.final_diversion_position = creeper.diversion_position
            entity.autopilot_destination = nil
            local random = game.create_random_generator()
            local attempts = 0
            local max_attempts = 3
            local new_pos = nil
            while attempts < max_attempts do
                local angle = math.rad(random(0, 360))
                local distance = 3
                new_pos = {
                    x = math.floor(position.x + math.cos(angle) * distance),
                    y = math.floor(position.y + math.sin(angle) * distance)
                }
                local chunk_pos = {x = math.floor(new_pos.x / 32), y = math.floor(new_pos.y / 32)}
                if surface.is_chunk_generated(chunk_pos) and surface.can_place_entity{name = "character", position = new_pos} then
                    break
                end
                --game.print("Debug: Invalid new position for distractor " .. creeper.unit_number .. " at (" .. new_pos.x .. "," .. new_pos.y .. "), attempt: " .. (attempts + 1))
                attempts = attempts + 1
                new_pos = nil
            end
            if not new_pos then
                --game.print("Debug: Failed to find new position for distractor " .. creeper.unit_number .. " after " .. max_attempts .. " attempts, tick: " .. game.tick)
                creeper.last_position = nil
                creeper.last_position_tick = nil
                return false
            end
            schedule_autopilot_destination(creeper, {new_pos}, game.tick, false)
            creeper.autopilot_set_tick = game.tick
            creeper.last_position = nil
            creeper.last_position_tick = nil
            --game.print("Debug: Unstuck successful for distractor " .. creeper.unit_number .. ", new position: (" .. new_pos.x .. "," .. new_pos.y .. "), tick: " .. game.tick)
            return true
        else
            --game.print("Stuck: Distractor " .. creeper.unit_number .. " not stuck at (" .. position.x .. "," .. position.y .. "), tick: " .. game.tick)

        end

        -- Update last position and tick
        creeper.last_position = {x = position.x, y = position.y}
        creeper.last_position_tick = game.tick
        --game.print("Debug: Updated last position (" .. position.x .. "," .. position.y .. ") at tick " .. game.tick .. " for distractor " .. creeper.unit_number)
        --game.print("Debug: Distractor " .. creeper.unit_number .. ", dist_to_target: " .. dist_to_target .. ", target_pos: (" .. target_pos.x .. "," .. target_pos.y .. "), diversion_position: " .. (creeper.diversion_position and "(" .. creeper.diversion_position.x .. "," .. creeper.diversion_position.y .. ")" or "none"))
        --game.print("Debug: Autopilot set tick: " .. (creeper.autopilot_set_tick or "none") .. ", current tick: " .. game.tick .. " for unit " .. creeper.unit_number)
       
        if dist_to_target > 30 then
            local path_success = request_multiple_paths(position, target_pos, nil, surface, creeper.unit_number)
            --game.print("Debug: Distractor " .. creeper.unit_number .. " path request " .. (path_success and "succeeded" or "failed") .. " to " .. (creeper.diversion_position and "diversion" or "target") .. " (" .. target_pos.x .. "," .. target_pos.y .. "), tick: " .. game.tick)
            if not path_success then
                --game.print("Debug: Path request failed for distractor " .. creeper.unit_number .. " to " .. (creeper.diversion_position and "diversion" or "target") .. " (" .. target_pos.x .. "," .. target_pos.y .. ")")
                return false
            end
            local autopilot = entity.autopilot_destination
            --game.print("Debug: Distractor " .. creeper.unit_number .. " pathing to " .. (creeper.diversion_position and "diversion" or "target") .. " at (" .. target_pos.x .. "," .. target_pos.y .. "), autopilot: (" .. (autopilot and autopilot.x .. "," .. autopilot.y or "none") .. ")")
            creeper.autopilot_set_tick = game.tick
            return true
        end

        -- Handle diversion position selection when within 30 tiles and no diversion_position
        if not creeper.diversion_position then
            entity.autopilot_destination = nil
            local random = game.create_random_generator()
            local attempts = 0
            local max_attempts = 3
            local divert_pos = nil
            local base_angle, angle_variation
            while attempts < max_attempts do
                base_angle = random(1, 2) == 1 and 180 or 360
                angle_variation = random(-30, 30)
                local divert_angle = math.rad(base_angle + angle_variation)
                local divert_distance = 20
                divert_pos = {
                    x = math.floor(position.x + math.cos(divert_angle) * divert_distance),
                    y = math.floor(position.y + math.sin(divert_angle) * divert_distance)
                }
                local chunk_pos = {x = math.floor(divert_pos.x / 32), y = math.floor(divert_pos.y / 32)}
                if surface.is_chunk_generated(chunk_pos) and surface.can_place_entity{name = "character", position = divert_pos} then
                    break
                end
                --game.print("Debug: Invalid diversion position for distractor " .. creeper.unit_number .. " at (" .. divert_pos.x .. "," .. divert_pos.y .. "), attempt: " .. (attempts + 1))
                attempts = attempts + 1
                divert_pos = nil
            end
            if not divert_pos then
                --game.print("Debug: Failed to find valid diversion position for distractor " .. creeper.unit_number .. " after " .. max_attempts .. " attempts")
                return false
            end
            creeper.diversion_position = divert_pos
            local path_success = request_multiple_paths(position, divert_pos, nil, surface, creeper.unit_number)
            --game.print("Debug: Distractor " .. creeper.unit_number .. " diversion path request " .. (path_success and "succeeded" or "failed") .. " to (" .. divert_pos.x .. "," .. divert_pos.y .. "), tick: " .. game.tick)
            if not path_success then
                --game.print("Debug: Path request failed for distractor " .. creeper.unit_number .. " to diversion (" .. divert_pos.x .. "," .. divert_pos.y .. ")")
                return false
            end
            local autopilot = entity.autopilot_destination
            --game.print("Debug: Distractor " .. creeper.unit_number .. " diverting to (" .. divert_pos.x .. "," .. divert_pos.y .. "), angle: " .. (base_angle + angle_variation) .. ", dist_to_target: " .. dist_to_target .. ", autopilot: (" .. (autopilot and autopilot.x .. "," .. autopilot.y or "none") .. ")")
            creeper.autopilot_set_tick = game.tick
            return true
        end

        -- Check if at diversion position
        if creeper.diversion_position and not entity.autopilot_destination and calculate_distance(position, creeper.diversion_position) < 1 then
            local enemies = surface.find_entities_filtered{
                position = position,
                radius = 5,
                force = "enemy",
                type = "unit"
            }
            if #enemies >= 5 then
                if not creeper.explosion_wait_tick then
                    creeper.explosion_wait_tick = game.tick + 60
                    --game.print("Debug: Distractor " .. creeper.unit_number .. " found " .. #enemies .. " biters within 5 tiles, waiting 1 second to explode, tick: " .. game.tick)
                elseif game.tick >= creeper.explosion_wait_tick then
                    creeper.state = "exploding"
                    --game.print("Debug: Distractor " .. creeper.unit_number .. " transitioning to exploding, tick: " .. game.tick)
                    creeper.explosion_wait_tick = nil
                end
            else
                if not creeper.explosion_wait_tick then
                    creeper.explosion_wait_tick = game.tick + 60
                    --game.print("Debug: Distractor " .. creeper.unit_number .. " found " .. #enemies .. " biters within 5 tiles, waiting 1 second to explode, tick: " .. game.tick)
                elseif game.tick >= creeper.explosion_wait_tick then
                    creeper.state = "exploding"
                    --game.print("Debug: Distractor " .. creeper.unit_number .. " transitioning to exploding, tick: " .. game.tick)
                    creeper.explosion_wait_tick = nil
                end
            end
            return true
        end

        -- Continue moving to diversion position if not yet arrived
        if creeper.diversion_position and dist_to_target <= 30 and not entity.autopilot_destination then
            schedule_autopilot_destination(creeper, {creeper.diversion_position}, game.tick, false)
            --game.print("Debug: Distractor " .. creeper.unit_number .. " scheduled autopilot to diversion (" .. creeper.diversion_position.x .. "," .. creeper.diversion_position.y .. "), tick: " .. game.tick)
            creeper.autopilot_set_tick = game.tick
            return true
        end
        return true
    end

    -- Original leader logic (unchanged)
    if creeper.is_leader then
        local party = storage.parties[creeper.party_id]
        if not party then
            --game.print("Error: Invalid party for unit " .. (creeper.unit_number or "unknown") .. ", tick: " .. game.tick)
            return false
        end
        --game.print("Debug: Validation passed for unit " .. creeper.unit_number .. ", leader: " .. (creeper.is_leader and "yes" or "no") .. ", tick: " .. game.tick)
        
        if not tier_configs[entity.name] then
            --game.print("Error: Invalid tier config for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
            return false
        end
        --game.print("Debug: Tier config valid for unit " .. creeper.unit_number .. ", tier: " .. entity.name .. ", tick: " .. game.tick)
        
        if not entity.autopilot_destinations or #entity.autopilot_destinations == 0 then
            --game.print("Debug: No autopilot destinations for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
            if creeper.is_leader then
                local target_pos = get_unvisited_chunk(position, party)
                if target_pos.x ~= position.x or target_pos.y ~= position.y then
                    game.print("Debug: Leader " .. creeper.unit_number .. " requesting path to (" .. target_pos.x .. "," .. target_pos.y .. "), tick: " .. game.tick)
                    request_multiple_paths(position, target_pos, party, surface, creeper.unit_number)
                else
                   -- game.print("Error: No valid chunk found for leader " .. creeper.unit_number .. ", tick: " .. game.tick)
                end
            end
            return false
        end
        
        local current_destination = entity.autopilot_destination
        if not current_destination then
            --game.print("Debug: No current destination for unit " .. creeper.unit_number .. ", clearing autopilot, tick: " .. game.tick)
            entity.autopilot_destination = nil
            clear_renderings(creeper)
            return false
        end
       -- game.print("Debug: Current destination for unit " .. creeper.unit_number .. ": (" .. current_destination.x .. "," .. current_destination.y .. "), tick: " .. game.tick)
        
        local distance = calculate_distance(position, current_destination)
        --game.print("Debug: Distance to current destination for unit " .. creeper.unit_number .. ": " .. distance .. ", tick: " .. game.tick)
        
        if creeper.dynamic_line_id then
            if type(creeper.dynamic_line_id) == "userdata" and creeper.dynamic_line_id.valid then
                --game.print("Debug: Destroying userdata dynamic line for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
                creeper.dynamic_line_id.destroy()
            elseif type(creeper.dynamic_line_id) == "number" then
                local render_obj = rendering.get_object_by_id(creeper.dynamic_line_id)
                if render_obj and render_obj.valid then
                    --game.print("Debug: Destroying numeric dynamic line ID " .. creeper.dynamic_line_id .. " for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
                    render_obj.destroy()
                else
                    --game.print("Debug: Invalid numeric dynamic line ID " .. tostring(creeper.dynamic_line_id) .. " for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
                end
            end
            creeper.dynamic_line_id = nil
        end
        
        local render_obj = rendering.draw_line({
            color = {r = 1, g = 0, b = 0, a = 1},
            width = 2,
            from = position,
            to = current_destination,
            surface = surface,
            time_to_live = 600,
            draw_on_ground = false
        })
        
        if render_obj and render_obj.valid then
            --game.print("Debug: Created new dynamic line ID " .. render_obj.id .. " for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
            creeper.dynamic_line_id = render_obj.id
        else
            --game.print("Debug: Failed to create dynamic line for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
        end
        
        local threshold = 3
        if distance <= threshold and (creeper.last_waypoint_change or 0) + 20 < game.tick then
           -- game.print("Debug: Leader " .. creeper.unit_number .. " reached waypoint at (" .. current_destination.x .. "," .. current_destination.y .. ") on tick " .. game.tick)
            
           -- game.print("Debug: Scanning for enemies for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
            local target, target_type = scan_for_enemies(position, surface, tier_configs[entity.name].max_targeting)
            if target and (target_type == "unit" or target_type == "nest") then
                --game.print("Debug: Leader " .. creeper.unit_number .. " detected " .. target_type .. " at (" .. target.position.x .. "," .. target.position.y .. "), transitioning party to preparing_to_attack, tick: " .. game.tick)
                for unit_number, member in pairs(storage.creeperbots or {}) do
                    if member.party_id == creeper.party_id and member.entity and member.entity.valid then
                        member.state = "preparing_to_attack"
                        update_color(member.entity, "preparing_to_attack")
                        member.entity.autopilot_destination = nil
                        if storage.scheduled_autopilots and storage.scheduled_autopilots[unit_number] then
                            storage.scheduled_autopilots[unit_number] = nil
                            --game.print("Debug: Cleared scheduled autopilot for unit " .. unit_number .. ", tick: " .. game.tick)
                        end
                       --game.print("Debug: Unit " .. unit_number .. " transitioned to preparing_to_attack, tick: " .. game.tick)
                    end
                end
                return false
            else
                --game.print("Debug: No enemies detected by unit " .. creeper.unit_number .. ", target_type: " .. (target_type or "none") .. ", target: " .. (target and "valid" or "nil") .. ", tick: " .. game.tick)
            end
            
            if creeper.render_ids and creeper.render_ids[1] then
                local id = creeper.render_ids[1]
                if type(id) == "number" then
                    local render_obj = rendering.get_object_by_id(id)
                    if render_obj and render_obj.valid then
                        game.print("Debug: Destroying render ID " .. id .. " for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
                        render_obj.destroy()
                    else
                        --game.print("Debug: Invalid render ID " .. id .. " for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
                    end
                end
                table.remove(creeper.render_ids, 1)
            end
            creeper.last_waypoint_change = game.tick
           -- game.print("Debug: Updated last_waypoint_change for unit " .. creeper.unit_number .. " to tick " .. game.tick)
            
            local remaining_waypoints = {}
            if entity.autopilot_destinations and #entity.autopilot_destinations > 1 then
                for i = 2, #entity.autopilot_destinations do
                    table.insert(remaining_waypoints, entity.autopilot_destinations[i])
                end
            end
            --game.print("Debug: Remaining waypoints for unit " .. creeper.unit_number .. ": " .. #remaining_waypoints .. ", tick: " .. game.tick)
            
            entity.autopilot_destination = nil
            if #remaining_waypoints > 0 then
                for _, waypoint in ipairs(remaining_waypoints) do
                    entity.add_autopilot_destination(waypoint)
                end
                --game.print("Debug: Leader " .. creeper.unit_number .. " moving to next waypoint, tick: " .. game.tick)
                return true
            else
                if creeper.is_leader then
                    local target_pos = get_unvisited_chunk(position, party)
                    if target_pos.x ~= position.x or target_pos.y ~= position.y then
                        --game.print("Debug: Leader " .. creeper.unit_number .. " requested new path to (" .. target_pos.x .. "," .. target_pos.y .. "), tick: " .. game.tick)
                        request_multiple_paths(position, target_pos, party, surface, creeper.unit_number)
                    else
                        --game.print("Error: No valid chunk found for leader " .. creeper.unit_number .. ", tick: " .. game.tick)
                    end
                end
                return false
            end
        end
        
        --game.print("Debug: Unit " .. creeper.unit_number .. " still moving to waypoint, distance: " .. distance .. ", tick: " .. game.tick)
        return true
    end
end

function clear_renderings(creeper)
    if creeper.render_ids then
        --game.print("Clearing render_ids: " .. serpent.line(creeper.render_ids))
        for _, id in pairs(creeper.render_ids) do
            if type(id) == "number" then
                -- Try to get the render object first
                local render_obj = rendering.get_object_by_id(id)
                if render_obj and render_obj.valid then
                    render_obj.destroy()
                    --game.print("Cleared rendering ID: " .. tostring(id))
                else
                    game.print("Skipping invalid rendering ID: " .. tostring(id))
                end
            else
                game.print("Skipping non-numeric rendering ID: type=" .. type(id) .. ", value=" .. tostring(id))
            end
        end
        creeper.render_ids = nil
    end
    
    if creeper.dynamic_line_id then
        -- Handle userdata rendering object directly
        if type(creeper.dynamic_line_id) == "userdata" then
            -- If it's a render object with a valid field, check validity
            if creeper.dynamic_line_id.valid then
                creeper.dynamic_line_id.destroy()
                --game.print("Destroyed dynamic line render object directly")
            else
                --game.print("Invalid dynamic line render object")
            end
        -- Handle direct numeric ID
        elseif type(creeper.dynamic_line_id) == "number" then
            local render_obj = rendering.get_object_by_id(creeper.dynamic_line_id)
            if render_obj and render_obj.valid then
                render_obj.destroy()
                --game.print("Cleared dynamic line ID: " .. tostring(creeper.dynamic_line_id))
            else
                --game.print("Invalid dynamic line ID: " .. tostring(creeper.dynamic_line_id))
            end
        else
            --game.print("Dynamic line ID is not a number or userdata: " .. type(creeper.dynamic_line_id))
        end
        
        creeper.dynamic_line_id = nil
    end
end