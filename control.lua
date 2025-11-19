-- Creeperbots - Control script
-- Handles initialization and event registration for autonomous Creeperbot behavior
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local manager = require "scripts.creeperbot_manager"
local behavior = require "scripts.creeperbot_behavior"
local utils = require "scripts.utils"
local waypoints = require "scripts.behavior.waypoints"
local config = require "scripts.behavior.config"

-- Centralized logging function
local function log(message, level)
    level = level or "debug"
    if level == "error" --[[or level == "debug"]] then
        --game.print("[" .. level:upper() .. "] " .. message)
    end
end

-- Initialize global storage
local function initialize_storage()
    storage.creeperbots = storage.creeperbots or {}
    storage.parties = storage.parties or {}
    storage.path_requests = storage.path_requests or {}
    storage.scheduled_autopilots = storage.scheduled_autopilots or {}
    storage.leader_candidates = storage.leader_candidates or {}
end

-- Register a Creeperbot entity
local function handle_entity_creation(event)
    local entity = event.created_entity or event.entity
    if entity and entity.valid and is_creeperbot(entity.name) then
        register_creeperbot(entity)
        log("Registered Creeperbot " .. entity.unit_number)
    end
end

-- Clean up a Creeperbot from storage and party
local function cleanup_creeperbot(entity)
    if not entity or not entity.valid or entity.type ~= "unit" or not storage.creeperbots then
        return
    end

    for unit_number, creeper in pairs(storage.creeperbots) do
        if creeper.entity == entity then
            local party_id = creeper.party_id or "none"
            log("Cleaning up unit " .. unit_number .. ", party: " .. party_id)

            -- Clear scheduled autopilots
            if storage.scheduled_autopilots[unit_number] then
                storage.scheduled_autopilots[unit_number] = nil
                log("Cleared scheduled autopilot for unit " .. unit_number)
            end

            -- Clear leader candidates
            if storage.leader_candidates[unit_number] then
                storage.leader_candidates[unit_number] = nil
                log("Cleared unit " .. unit_number .. " from leader_candidates")
            end

            -- Update party
            if creeper.party_id and storage.parties[creeper.party_id] then
                local party = storage.parties[creeper.party_id]
                if party.grouping_leader == unit_number then
                    party.grouping_leader = nil
                    log("Cleared leader for party " .. creeper.party_id)
                end
                if party.follower_targets then
                    party.follower_targets[unit_number] = nil
                    log("Removed unit " .. unit_number .. " from follower_targets in party " .. creeper.party_id)
                end

                -- Reassign leader or remove party
                local members = {}
                for u_number, member in pairs(storage.creeperbots) do
                    if member.party_id == creeper.party_id and member.entity and member.entity.valid and u_number ~= unit_number then
                        table.insert(members, member)
                    end
                end
                if #members > 0 then
                    local new_leader = members[1]
                    new_leader.is_leader = true
                    new_leader.is_guard = false
                    party.grouping_leader = new_leader.unit_number
                    update_color(new_leader.entity, party.state == "scouting" and "scouting" or "grouping")
                    log("Party " .. creeper.party_id .. " assigned new leader " .. new_leader.unit_number)
                else
                    storage.parties[creeper.party_id] = nil
                    log("Removed party " .. creeper.party_id .. " - no valid members")
                end
            end

            remove_creeperbot(unit_number)
            storage.creeperbots[unit_number] = nil
            break
        end
    end
end

-- Handle entity death and rendering cleanup
local function handle_entity_death(event)
    local entity = event.entity
    if entity and entity.valid and is_creeperbot(entity.name) then
        local creeper = storage.creeperbots[entity.unit_number]
        local position = entity.position
        local surface = entity.surface
        
        -- Get tier config for explosion damage
        local tier = config.tier_configs[entity.name] or config.tier_configs["creeperbot-mk1"]
        
        -- Create explosion and damage nearby entities
        if position and surface and surface.valid and entity.valid then
            local explosion_range = tier.radius or 3.5
            
            -- Create explosion entity
            if tier.explosion == "nuke-explosion" then
                surface.create_entity({name = "nuke-explosion", position = position})
                -- Destroy nearby cliffs
                local cliffs = surface.find_entities_filtered{position = position, radius = 9, type = "cliff"}
                for _, cliff in pairs(cliffs) do
                    cliff.destroy()
                end
                -- Create additional atomic explosions
                for _ = 1, 3 do
                    surface.create_entity({name = "atomic-explosion", position = position})
                end
                -- Create extra effect if specified
                if tier.extra_effect then
                    surface.create_entity({name = tier.extra_effect, position = position})
                end
            else
                surface.create_entity({name = tier.explosion, position = position})
            end
            
            -- Damage nearby enemy entities
            local nearby_entities = surface.find_entities_filtered{
                position = position,
                radius = explosion_range,
                force = "enemy"
            }
            for _, nearby_entity in pairs(nearby_entities) do
                if nearby_entity.valid and nearby_entity.health and nearby_entity.health > 0 then
                    nearby_entity.damage(tier.damage, "enemy", "explosion")
                end
            end
        end
        
        -- Clean up renderings
        if creeper and creeper.render_ids then
            for _, id in pairs(creeper.render_ids) do
                rendering.destroy(id)
            end
            creeper.render_ids = nil
        end
        cleanup_creeperbot(entity)
    end
end

-- Process Creeperbot behavior every 30 ticks
local function process_creeperbots(event)
    for unit_number, creeper in pairs(storage.creeperbots or {}) do
        if creeper.entity and creeper.entity.valid then
            local party = storage.parties[creeper.party_id]
            if creeper.state == "distractor" then
                waypoints.process_waypoints(creeper)
            end
            if creeper.is_leader and creeper.state == "scouting" then
                waypoints.process_waypoints(creeper)
            end
            ::continue::
        end
    end
end

-- Clean up invalid Creeperbots and parties
local function cleanup_invalid_units()
    local units_to_remove = {}
    for unit_number, creeper in pairs(storage.creeperbots or {}) do
        if not (creeper.entity and creeper.entity.valid) then
            table.insert(units_to_remove, unit_number)
        end
    end
    for _, unit_number in ipairs(units_to_remove) do
        cleanup_creeperbot(storage.creeperbots[unit_number].entity)
    end

    local parties_to_remove = {}
    for party_id, party in pairs(storage.parties or {}) do
        local members = {}
        for unit_number, member in pairs(storage.creeperbots or {}) do
            if member.party_id == party_id and member.entity and member.entity.valid then
                table.insert(members, member)
            end
        end
        if not party.grouping_leader or not storage.creeperbots[party.grouping_leader] or not storage.creeperbots[party.grouping_leader].entity or not storage.creeperbots[party.grouping_leader].entity.valid then
            if #members > 0 then
                local new_leader = members[1]
                new_leader.is_leader = true
                new_leader.is_guard = false
                party.grouping_leader = new_leader.unit_number
                update_color(new_leader.entity, party.state == "scouting" and "scouting" or "grouping")
                log("Party " .. party_id .. " assigned new leader " .. new_leader.unit_number)
            else
                table.insert(parties_to_remove, party_id)
            end
        end
    end
    for _, party_id in ipairs(parties_to_remove) do
        storage.parties[party_id] = nil
        log("Removed party " .. party_id)
    end
end

-- Process scheduled autopilots
local function process_scheduled_autopilots(event)
    if not storage.scheduled_autopilots then return end
    for unit_number, scheduled in pairs(storage.scheduled_autopilots) do
        local creeper = storage.creeperbots[unit_number]
        if creeper and creeper.entity and creeper.entity.valid and event.tick >= scheduled.tick then
            if creeper.entity.follow_target or creeper.state == "scouting" or creeper.state == "guard" or creeper.state == "approaching" or creeper.state == "exploding" then
                storage.scheduled_autopilots[unit_number] = nil
                log("Skipped autopilot for unit " .. unit_number .. " due to state " .. creeper.state)
            else
                creeper.entity.add_autopilot_destination(scheduled.destination[1])
                storage.scheduled_autopilots[unit_number] = nil
                log("Unit " .. unit_number .. " applied autopilot to (" .. scheduled.destination[1].x .. "," .. scheduled.destination[1].y .. ")")
            end
        end
    end
end

-- Update Creeperbot states
local function update_creeperbots(event)
    for unit_number, creeper in pairs(storage.creeperbots or {}) do
        if creeper.entity and creeper.entity.valid then
            if creeper.state == "guard" and creeper.entity.follow_target then
                -- Skip guard with follow target
            elseif creeper.is_leader and creeper.entity.autopilot_destination then
                -- Skip leader with autopilot destination
            elseif creeper.state == "scouting" and not creeper.is_leader and creeper.entity.follow_target then
                -- Skip follower in scouting state with follow target
            elseif creeper.state == "approaching" and creeper.entity.autopilot_destination then
                -- Skip approaching with autopilot destination
            elseif creeper.state == "distractor" and creeper.entity.autopilot_destination then
                -- Skip distractor with autopilot destination
            elseif creeper.state == "exploding" and creeper.entity.autopilot_destination then
                -- Check if close enough to explode even with autopilot
                if creeper.target and creeper.target.valid then
                    local dist = math.sqrt((creeper.entity.position.x - creeper.target.position.x)^2 + (creeper.entity.position.y - creeper.target.position.y)^2)
                    if dist <= 5 then
                        -- Close enough, update to trigger explosion
                        update_creeperbot(creeper, event)
                    end
                    -- Otherwise skip (let it move)
                else
                    -- No target, update to find new one
                    update_creeperbot(creeper, event)
                end
            else
                update_creeperbot(creeper, event)
                log("Updated unit " .. unit_number .. ", state: " .. creeper.state)
            end
        end
    end
end

-- Resolve leader candidates
local function resolve_leader_candidates(event)
    if not storage.leader_candidates then return end
    local candidates = storage.leader_candidates
    storage.leader_candidates = {}
    local groups = {}
    for unit_number, candidate in pairs(candidates) do
        local added = false
        for _, group in ipairs(groups) do
            for _, member_unit in ipairs(group) do
                local member = candidates[member_unit]
                if calculate_distance(candidate.position, member.position) <= 30 then
                    table.insert(group, unit_number)
                    added = true
                    break
                end
            end
            if added then break end
        end
        if not added then
            table.insert(groups, {unit_number})
        end
    end

    local random = game.create_random_generator()
    for _, group in ipairs(groups) do
        local leader_index = random(1, #group)
        local leader_unit = group[leader_index]
        local leader_creeper = candidates[leader_unit].creeper
        leader_creeper.party_id = assign_to_party(leader_creeper.entity)
        local party = storage.parties[leader_creeper.party_id]
        leader_creeper.is_leader = true
        party.grouping_leader = leader_unit
        party.grouping_start_tick = event.tick
        party.last_join_tick = event.tick
        party.follower_targets = party.follower_targets or {}
        leader_creeper.state = "grouping"
        update_color(leader_creeper.entity, "grouping")
        log("Unit " .. leader_unit .. " became " .. (#group == 1 and "solo leader" or "leader of group size " .. #group))

        for i, unit_number in ipairs(group) do
            if i ~= leader_index then
                local creeper = candidates[unit_number].creeper
                creeper.party_id = party.id
                creeper.state = "grouping"
                update_color(creeper.entity, "grouping")
                party.last_join_tick = event.tick
                log("Unit " .. unit_number .. " joined group, leader: " .. leader_unit)
            end
        end
    end
end

-- Evaluate party grouping conditions
local function evaluate_grouping(event)
    for party_id, party in pairs(storage.parties or {}) do
        if party.state ~= "grouping" and party.state ~= "preparing_to_attack" then
            goto continue
        end

        local leader = storage.creeperbots[party.grouping_leader]
        if not (leader and leader.entity and leader.entity.valid) then
            log("Leader invalid for party " .. party_id, "error")
            goto continue
        end

        local surface = leader.entity.surface
        local leader_pos = leader.entity.position
        local members = {}
        local distractors = {}
        for unit_number, member in pairs(storage.creeperbots or {}) do
            if member.party_id == party_id and member.entity and member.entity.valid then
                table.insert(members, member)
                if member.is_distractor then
                    table.insert(distractors, member)
                end
            end
        end
        log("Party " .. party_id .. " - Members: " .. #members .. ", Distractors: " .. #distractors .. ", State: " .. party.state)

        if party.state == "grouping" then
            -- Use same criteria as grouping.lua for consistency
            if not party.grouping_start_tick then
                party.grouping_start_tick = event.tick
            end
            
            local time_elapsed = event.tick - party.grouping_start_tick
            local min_time = (#members >= 3) and 600 or 900  -- 10 seconds for groups, 15 seconds for smaller groups
            local has_leader = party.grouping_leader and storage.creeperbots[party.grouping_leader] and storage.creeperbots[party.grouping_leader].entity and storage.creeperbots[party.grouping_leader].entity.valid
            local timeout_elapsed = time_elapsed >= min_time
            local size_ok = #members >= 1  -- Allow solo bots

            if not party.started_scouting and timeout_elapsed and size_ok and has_leader then
                party.started_scouting = true
                party.state = "scouting"
                party.follower_targets = party.follower_targets or {}
                for _, member in ipairs(members) do
                    if member.entity and member.entity.valid then
                        member.state = member.is_distractor and "distractor" or "scouting"
                        update_color(member.entity, member.state)
                        if storage.scheduled_autopilots[member.unit_number] then
                            storage.scheduled_autopilots[member.unit_number] = nil
                            log("Cleared scheduled_autopilots for unit " .. member.unit_number)
                        end
                        if not member.is_leader and not member.is_distractor then
                            member.entity.autopilot_destination = nil
                            log("Cleared autopilot_destination for follower unit " .. member.unit_number)
                        end
                        log("Unit " .. member.unit_number .. " transitioned to state " .. member.state)
                    end
                end

                local target_pos = get_unvisited_chunk(leader_pos, party)
                if target_pos.x == leader_pos.x and target_pos.y == leader_pos.y then
                    log("No valid chunk found for party " .. party_id, "error")
                    goto continue
                end

                leader.entity.autopilot_destination = nil
                request_multiple_paths(leader_pos, target_pos, party, surface, leader.unit_number)
                log("Leader " .. leader.unit_number .. " set path to (" .. target_pos.x .. "," .. target_pos.y .. ")")

                for _, distractor in ipairs(distractors) do
                    if distractor.entity and distractor.entity.valid then
                        distractor.entity.autopilot_destination = nil
                        log("Cleared autopilot_destination for distractor unit " .. distractor.unit_number)
                    end
                end
            end
        end

        table.sort(members, function(a, b) return a.tier < b.tier end)
        local leaders = {leader}
        for _, distractor in ipairs(distractors) do
            table.insert(leaders, distractor)
        end
        local follower_counts = {}
        for _, l in ipairs(leaders) do
            follower_counts[l.unit_number] = 0
        end
        local tiers = {{tier = 1, bots = {}}, {tier = 2, bots = {}}, {tier = 3, bots = {}}}
        for _, member in ipairs(members) do
            if not member.is_leader and not member.is_distractor then
                table.insert(tiers[member.tier].bots, member)
            end
        end

        local max_distractors = math.max(1, math.floor(#members / 3))
        local distractor_count = #distractors
        if distractor_count < max_distractors then
            for _, tier in ipairs(tiers) do
                for _, member in ipairs(tier.bots) do
                    if distractor_count < max_distractors and member.entity and member.entity.valid then
                        member.is_distractor = true
                        member.state = party.state == "preparing_to_attack" and "distractor" or "distractor"
                        update_color(member.entity, "distractor")
                        table.insert(distractors, member)
                        table.insert(leaders, member)
                        follower_counts[member.unit_number] = 0
                        log("Unit " .. member.unit_number .. " assigned as distractor for party " .. party_id)
                        distractor_count = distractor_count + 1
                    end
                end
            end
        end

        for _, tier in ipairs(tiers) do
            for _, member in ipairs(tier.bots) do
                if member.entity and member.entity.valid and not member.is_distractor then
                    local min_followers = math.huge
                    local target_leader = nil
                    for _, l in ipairs(leaders) do
                        if follower_counts[l.unit_number] < min_followers then
                            min_followers = follower_counts[l.unit_number]
                            target_leader = l
                        end
                    end
                    if target_leader and target_leader.entity and target_leader.entity.valid then
                        local success, err = pcall(function()
                            member.entity.follow_target = target_leader.entity
                        end)
                        if success then
                            party.follower_targets[member.unit_number] = target_leader.unit_number
                            follower_counts[target_leader.unit_number] = follower_counts[target_leader.unit_number] + 1
                            log("Follower " .. member.unit_number .. " assigned to " .. target_leader.unit_number)
                        else
                            log("Follower " .. member.unit_number .. " failed to set follow_target to unit " .. target_leader.unit_number .. ": " .. tostring(err), "error")
                            party.follower_targets[member.unit_number] = nil
                            log("Cleared follower_targets for unit " .. member.unit_number)
                        end
                    end
                end
            end
        end

        ::continue::
    end
end

-- Combined tick handler (every 60 ticks)
local function handle_tick_60(event)
    cleanup_invalid_units()
    process_scheduled_autopilots(event)
    update_creeperbots(event)
    resolve_leader_candidates(event)
    evaluate_grouping(event)
end

-- Handle path request completion
local function handle_path_request(event)
    local request = storage.path_requests[event.id]
    if not request then
        log("No path request found for request_id: " .. event.id)
        return
    end

    local creeper = storage.creeperbots[request.creeper_unit_number]
    if not creeper or not creeper.entity or not creeper.entity.valid then
        log("Invalid creeper for unit " .. request.creeper_unit_number .. " in path request " .. event.id)
        storage.path_requests[event.id] = nil
        return
    end

    local is_distractor = type(request.party_id) == "string" and request.party_id:match("^distractor_")
    local party = is_distractor and {} or storage.parties[request.party_id]
    
    -- Allow path setting even if party is nil (for bots that may have left their party)
    if not is_distractor and not party then
        log("Path request " .. event.id .. " ignored - invalid party for unit " .. request.creeper_unit_number .. " in state " .. (creeper.state or "nil"))
        storage.path_requests[event.id] = nil
        return
    end
    if not creeper or not creeper.entity or not creeper.entity.valid then
        log("Path request " .. event.id .. " ignored - invalid creeper")
        storage.path_requests[event.id] = nil
        return
    end

    if not event.path then
        if event.try_again_later then
            log("Path request " .. event.id .. " failed, will retry later")
            local surface = creeper.entity.surface
            local path_collision_mask = {
                layers = { water_tile = true, cliff = true },
                colliding_with_tiles_only = true,
                consider_tile_transitions = true
            }
            local start_pos = {
                x = request.target_pos.x + start_offsets[request.start_offset_index].x,
                y = request.target_pos.y + start_offsets[request.start_offset_index].y
            }
            local new_request_id = surface.request_path{
                start = start_pos,
                goal = request.target_pos,
                force = "player",
                bounding_box = {{-0.5, -0.5}, {0.5, 0.5}},
                collision_mask = path_collision_mask,
                radius = 20,
                path_resolution_modifier = -3,
                pathfind_flags = {
                    cache = false,
                    prefer_straight_paths = false,
                    low_priority = true
                }
            }
            storage.path_requests[new_request_id] = request
            storage.path_requests[event.id] = nil
            return
        else
            log("Path request " .. event.id .. " failed permanently")
            if not is_distractor then
                creeper.state = "scouting"
                creeper.target = nil
                creeper.target_position = nil
                creeper.target_health = nil
                party.shared_target = nil
                clear_renderings(creeper)
            end
            storage.path_requests[event.id] = nil
            return
        end
    end

    -- Clear follow_target if set (it can prevent autopilot from working)
    if creeper.entity.follow_target then
        creeper.entity.follow_target = nil
        log("Cleared follow_target for unit " .. request.creeper_unit_number .. " before setting autopilot path")
    end
    
    creeper.entity.autopilot_destination = nil
    for _, waypoint in ipairs(event.path) do
        creeper.entity.add_autopilot_destination(waypoint.position)
    end
    log("Set " .. #event.path .. " autopilot destinations for unit " .. request.creeper_unit_number .. " (state: " .. (creeper.state or "nil") .. ") to (" .. request.target_pos.x .. "," .. request.target_pos.y .. ")")
    
    if not is_distractor then
        local chunk_key = request.chunk_x .. "," .. request.chunk_y
        party.visited_chunks[chunk_key] = (party.visited_chunks[chunk_key] or 0) + 1
        log("Leader " .. request.creeper_unit_number .. " set path to chunk (" .. request.chunk_x .. "," .. request.chunk_y .. "), visits: " .. party.visited_chunks[chunk_key])
    end

    storage.path_requests[event.id] = nil
end

-- Handle player clicking on a creeperbot - print debug info
local function handle_selected_entity(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    
    local selected = player.selected
    if not selected or not selected.valid then return end
    
    if is_creeperbot(selected.name) then
        local creeper = storage.creeperbots[selected.unit_number]
        if creeper then
            local party = creeper.party_id and storage.parties[creeper.party_id] or nil
            local follow_target = selected.follow_target
            local autopilot_dest = selected.autopilot_destination
            local autopilot_dests = selected.autopilot_destinations
            
            local debug_info = {
                "=== Creeperbot Debug Info ===",
                "Unit Number: " .. selected.unit_number,
                "State: " .. (creeper.state or "nil"),
                "Party ID: " .. (creeper.party_id or "none"),
                "Is Leader: " .. tostring(creeper.is_leader or false),
                "Is Guard: " .. tostring(creeper.is_guard or false),
                "Is Distractor: " .. tostring(creeper.is_distractor or false),
                "Health: " .. string.format("%.1f", selected.health),
                "Position: (" .. string.format("%.1f", selected.position.x) .. ", " .. string.format("%.1f", selected.position.y) .. ")",
            }
            
            if party then
                table.insert(debug_info, "Party State: " .. (party.state or "nil"))
                table.insert(debug_info, "Party Members: " .. (party.grouping_leader and "has leader" or "no leader"))
            end
            
            if follow_target and follow_target.valid then
                table.insert(debug_info, "Follow Target: " .. follow_target.name .. " (" .. string.format("%.1f", follow_target.position.x) .. ", " .. string.format("%.1f", follow_target.position.y) .. ")")
            else
                table.insert(debug_info, "Follow Target: none")
            end
            
            if autopilot_dest then
                table.insert(debug_info, "Autopilot Dest: (" .. string.format("%.1f", autopilot_dest.x) .. ", " .. string.format("%.1f", autopilot_dest.y) .. ")")
            else
                table.insert(debug_info, "Autopilot Dest: none")
            end
            
            if autopilot_dests and #autopilot_dests > 0 then
                table.insert(debug_info, "Autopilot Queue: " .. #autopilot_dests .. " waypoints")
            else
                table.insert(debug_info, "Autopilot Queue: empty")
            end
            
            if creeper.target and creeper.target.valid then
                table.insert(debug_info, "Target: " .. creeper.target.name .. " (" .. string.format("%.1f", creeper.target.position.x) .. ", " .. string.format("%.1f", creeper.target.position.y) .. ")")
            else
                table.insert(debug_info, "Target: none")
            end
            
            for _, line in ipairs(debug_info) do
                player.print(line)
            end
        end
    end
end

-- Register event handlers
script.on_init(initialize_storage)
script.on_configuration_changed(initialize_storage)

script.on_event(defines.events.on_built_entity, handle_entity_creation)
script.on_event(defines.events.on_robot_built_entity, handle_entity_creation)
script.on_event(defines.events.script_raised_revive, handle_entity_creation)

script.on_event(defines.events.on_player_mined_entity, cleanup_creeperbot)
script.on_event(defines.events.on_entity_died, handle_entity_death)

script.on_event(defines.events.on_selected_entity_changed, handle_selected_entity)

script.on_nth_tick(15, process_autopilot_queue) 
script.on_nth_tick(30, process_creeperbots)
script.on_nth_tick(60, handle_tick_60)

script.on_event(defines.events.on_script_path_request_finished, handle_path_request)