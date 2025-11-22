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
    storage.territory = storage.territory or {}  -- Global chunk territory tracking by surface
    storage.territory_visualization = storage.territory_visualization or {}  -- Per-player visualization state
    storage.pending_teleports = storage.pending_teleports or {}  -- Store creeperbot state for teleportation restoration
end

-- Register a Creeperbot entity
local function handle_entity_creation(event)
    local entity = event.created_entity or event.entity
    if entity and entity.valid and is_creeperbot(entity.name) then
        -- Check if this is a teleported bot (created via script with raise_built=true)
        -- If so, let handle_trigger_created_entity handle it to preserve teleportation state
        if storage.pending_teleports then
            for key, teleport_data in pairs(storage.pending_teleports) do
                if teleport_data.bot_name == entity.name then
                    local distance = calculate_distance(entity.position, teleport_data.destination)
                    if distance < 10 then  -- Within 10 tiles of destination
                        -- This is a teleported bot - let handle_trigger_created_entity handle it
                        -- We need to create a fake trigger event for it
                        handle_trigger_created_entity({
                            entity = entity,
                            source = event.source or entity
                        })
                        return
                    end
                end
            end
        end
        
        -- Not a teleported bot - register normally
        register_creeperbot(entity)
        log("Registered Creeperbot " .. entity.unit_number)
    end
end

-- Handle creeperbot created by projectile (teleportation)
local function handle_trigger_created_entity(event)
    local entity = event.entity
    if not (entity and entity.valid and is_creeperbot(entity.name)) then
        return
    end
    
    -- Check if this is a teleported bot (has stored state) BEFORE checking source
    -- We match by finding the closest pending teleport to the new entity's position
    local best_match = nil
    local best_distance = math.huge
    local match_key = nil
    
    if storage.pending_teleports then
        for key, teleport_data in pairs(storage.pending_teleports) do
            if teleport_data.bot_name == entity.name then
                local distance = calculate_distance(entity.position, teleport_data.destination)
                if distance < 10 and distance < best_distance then  -- Within 10 tiles of destination
                    best_distance = distance
                    best_match = teleport_data
                    match_key = key
                end
            end
        end
    end
    
    -- For non-teleported bots (normal trigger_created_entity), require valid source
    -- For teleported bots (from script_raised_built), source may not be available
    if not best_match then
        local source = event.source
        if not (source and source.valid) then
            return
        end
    end
    
    if best_match then
        -- Check if already registered (could happen if both script_raised_built and on_trigger_created_entity fire)
        if storage.creeperbots and storage.creeperbots[entity.unit_number] then
            -- Already registered - just clean up the pending teleport
            storage.pending_teleports[match_key] = nil
            return
        end
        
        -- This is a teleported bot - register it but skip the default initialization
        -- Create creeper entry manually to preserve teleported state
        if not storage.creeperbots then storage.creeperbots = {} end
        if not storage.parties then storage.parties = {} end
        
        entity.entity_label = tostring(entity.unit_number)
        
        -- Create creeper table with restored state - restore ALL fields
        local creeper = {
            entity = entity,
            unit_number = entity.unit_number,
            state = best_match.state or "waking",  -- Restore state immediately
            party_id = best_match.party_id,  -- Restore party_id
            is_leader = best_match.is_leader or false,  -- Restore is_leader
            is_guard = best_match.is_guard or false,  -- Restore is_guard
            is_distractor = best_match.is_distractor or false,  -- Restore is_distractor
            target = best_match.target,  -- Restore target (may be nil if cleared)
            target_position = best_match.target_position,  -- Restore target_position
            target_health = best_match.target_health,  -- Restore target_health
            assigned_target = best_match.assigned_target,  -- Restore assigned_target
            tier = best_match.tier or get_creeperbot_tier(entity.name),  -- Restore tier
            last_teleport_tick = best_match.last_teleport_tick,  -- Restore teleport cooldown
            last_path_request = best_match.last_path_request,  -- Restore path request timing
            last_movement_update = best_match.last_movement_update,  -- Restore movement update timing
            last_target_search = best_match.last_target_search,  -- Restore target search timing
            last_health = best_match.last_health,  -- Restore health tracking
            max_health = best_match.max_health,  -- Restore max health
            launched_targets = best_match.launched_targets,  -- Restore launch tracking per target
            waking_initialized = best_match.waking_initialized,  -- Restore waking state
            grouping_initialized = best_match.grouping_initialized,  -- Restore grouping state
            distract_start_tick = best_match.distract_start_tick,  -- Restore distractor timing
            distract_end_tick = best_match.distract_end_tick,  -- Restore distractor timing
            diversion_position = best_match.diversion_position,  -- Restore diversion position
            render_ids = best_match.render_ids,  -- Restore renderings
        }
        
        -- Store the creeper
        storage.creeperbots[entity.unit_number] = creeper
        
        -- Restore autopilot destinations for leaders
        if best_match.is_leader and best_match.autopilot_destinations and #best_match.autopilot_destinations > 0 then
            entity.autopilot_destination = nil
            local attempts = 0
            while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
                entity.autopilot_destination = nil
                attempts = attempts + 1
            end
            -- Restore saved waypoints
            for _, waypoint in ipairs(best_match.autopilot_destinations) do
                entity.add_autopilot_destination(waypoint)
            end
            log("Restored " .. #best_match.autopilot_destinations .. " autopilot destinations for leader " .. entity.unit_number)
        else
            -- Clear autopilot destinations for followers
            entity.autopilot_destination = nil
            local attempts = 0
            while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
                entity.autopilot_destination = nil
                attempts = attempts + 1
            end
            if storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] then
                storage.scheduled_autopilots[entity.unit_number] = nil
            end
        end
        
        -- Restore follow target if it was set
        if best_match.follow_target and best_match.follow_target.valid then
            entity.follow_target = best_match.follow_target
        end
        
        -- Update color based on restored state
        update_color(entity, creeper.state)
        
        log("Restored teleported creeperbot " .. entity.unit_number .. " with state " .. creeper.state .. " (leader: " .. tostring(creeper.is_leader) .. ")")
        
        -- Clean up pending teleport
        storage.pending_teleports[match_key] = nil
    else
        -- Not a teleported bot - register normally
        register_creeperbot(entity)
    end
end


-- Create a projectile that spawns a creeperbot where it lands (for teleportation)
-- @param origin MapPosition - where the projectile starts
-- @param destination MapPosition - where the projectile lands
-- @param creeper table - the creeperbot data to preserve
-- @param speed_multiplier number? - multiplier for projectile speed
-- @param speed_override number? - override speed (if provided, speed_multiplier is ignored)
function create_creeperbot_projectile(origin, destination, creeper, speed_multiplier, speed_override)
    if not (creeper and creeper.entity and creeper.entity.valid) then
        return
    end
    
    local entity = creeper.entity
    local surface = entity.surface
    if not (surface and surface.valid) then
        return
    end
    
    -- Store creeperbot state for restoration after teleportation
    local teleport_key = "teleport_" .. entity.unit_number .. "_" .. game.tick
    storage.pending_teleports = storage.pending_teleports or {}
    
    -- Store autopilot destinations for leaders (they need to continue their path)
    local saved_autopilot_destinations = nil
    if creeper.is_leader and entity.autopilot_destinations and #entity.autopilot_destinations > 0 then
        saved_autopilot_destinations = {}
        for i, waypoint in ipairs(entity.autopilot_destinations) do
            table.insert(saved_autopilot_destinations, {x = waypoint.x, y = waypoint.y})
        end
    end
    
    -- Store ALL creeper data to preserve state completely
    storage.pending_teleports[teleport_key] = {
        bot_name = entity.name,
        destination = destination,
        state = creeper.state,
        party_id = creeper.party_id,
        is_leader = creeper.is_leader,
        is_guard = creeper.is_guard,
        is_distractor = creeper.is_distractor,
        target = creeper.target,
        target_position = creeper.target_position,
        target_health = creeper.target_health,
        assigned_target = creeper.assigned_target,
        follow_target = entity.follow_target,
        autopilot_destinations = saved_autopilot_destinations,  -- Store waypoints for leaders
        tier = creeper.tier,
        last_teleport_tick = creeper.last_teleport_tick,
        last_path_request = creeper.last_path_request,
        last_movement_update = creeper.last_movement_update,
        last_target_search = creeper.last_target_search,
        last_health = creeper.last_health,
        max_health = creeper.max_health,
        launched_targets = creeper.launched_targets,  -- Preserve launch tracking per target
        waking_initialized = creeper.waking_initialized,
        grouping_initialized = creeper.grouping_initialized,
        distract_start_tick = creeper.distract_start_tick,
        distract_end_tick = creeper.distract_end_tick,
        diversion_position = creeper.diversion_position,
        render_ids = creeper.render_ids,  -- Preserve renderings
    }
    
    -- Create the projectile
    local projectile_name = entity.name .. "-trigger"
    local source_entity = entity.follow_target or entity
    if not (source_entity and source_entity.valid) then
        source_entity = entity
    end
    
    surface.create_entity {
        name = projectile_name,
        position = origin,
        force = entity.force,
        source = source_entity,
        target = destination,
        speed = speed_override or (math.random() * (speed_multiplier or 1)),
        raise_built = true,
    }
    
    -- Destroy the old entity
    entity.destroy({ raise_destroy = true })
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
                
                -- Clear guard assignments if this was a guard
                if creeper.is_guard and party.guard_assignments then
                    for enemy_unit_number, guard_unit_number in pairs(party.guard_assignments) do
                        if guard_unit_number == unit_number then
                            party.guard_assignments[enemy_unit_number] = nil
                            log("Cleared guard assignment for enemy " .. enemy_unit_number .. " (guard " .. unit_number .. " died)")
                        end
                    end
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
                    surface.create_entity({name = "nuke-effects-nauvis", position = position})
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
            if creeper.entity.follow_target or creeper.state == "scouting" or creeper.state == "guard" or creeper.state == "approaching" or creeper.state == "exploding" or creeper.state == "defensive_formation" then
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

-- Check if creeperbots are too far from their follow target and teleport them closer
local function check_and_teleport_stuck_bots(event)
    -- Distance thresholds (in tiles)
    local max_range = 70  -- Normal max range
    local double_max_range = 140  -- Greatly exceeds range
    
    for unit_number, creeper in pairs(storage.creeperbots or {}) do
        if not (creeper.entity and creeper.entity.valid) then
            goto continue
        end
        
        local entity = creeper.entity
        local follow_target = entity.follow_target
        
        -- Only check bots that have a follow target
        if not (follow_target and follow_target.valid) then
            goto continue
        end
        
        -- Skip bots that are in certain states (they should handle their own movement)
        if creeper.state == "exploding" or creeper.state == "approaching" then
            goto continue
        end
        
        -- Check if bot is on the same surface as follow target
        if entity.surface_index ~= follow_target.surface_index then
            -- Different surface - teleport to follow target's surface
            local position_in_radius = get_random_position_in_radius(follow_target.position, 50)
            -- Use character as a generic entity type for collision checking
            local non_colliding_position = follow_target.surface.find_non_colliding_position("character", position_in_radius, 50, 0.5)
            local position = non_colliding_position or follow_target.position
            create_creeperbot_projectile(entity.position, position, creeper, 1, 0.25)
            log("Teleporting creeperbot " .. unit_number .. " to different surface")
            goto continue
        end
        
        -- Calculate distance to follow target
        local distance_to_target = calculate_distance(entity.position, follow_target.position)
        local no_speed = (entity.speed == 0)
        local exceeds_range = distance_to_target > max_range
        local greatly_exceeds_range = distance_to_target > double_max_range
        
        -- Teleport if bot is stuck (no speed) and exceeds range, or greatly exceeds range
        if (no_speed and exceeds_range) or greatly_exceeds_range then
            local position_in_radius = get_random_position_in_radius(follow_target.position, 50)
            -- Use character as a generic entity type for collision checking
            local non_colliding_position = follow_target.surface.find_non_colliding_position("character", position_in_radius, 100, 0.5)
            
            if non_colliding_position then
                create_creeperbot_projectile(entity.position, non_colliding_position, creeper, 5)
                log("Teleporting stuck creeperbot " .. unit_number .. " closer to follow target (distance: " .. string.format("%.1f", distance_to_target) .. ")")
            end
        end
        
        ::continue::
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
                -- Check if far enough to teleport (>50 tiles) - if so, still update to allow teleportation
                if creeper.target and creeper.target.valid then
                    local dist = math.sqrt((creeper.entity.position.x - creeper.target.position.x)^2 + (creeper.entity.position.y - creeper.target.position.y)^2)
                    if dist > 30 then
                        -- Far enough to teleport - update to allow teleportation check
                        update_creeperbot(creeper, event)
                    end
                    -- Otherwise skip (let it move normally)
                else
                    -- No target, update to find new one
                    update_creeperbot(creeper, event)
                end
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

                -- Check if leader is near water before starting scouting
                local actual_leader_pos = leader.entity.position
                if is_position_on_water(surface, actual_leader_pos, 2.5) then
                    local safe_pos = find_safe_position_away_from_water(surface, leader.entity, actual_leader_pos, 30)
                    if safe_pos then
                        leader.entity.autopilot_destination = nil
                        leader.entity.add_autopilot_destination(safe_pos)
                        log("Leader " .. leader.unit_number .. " is near water, moving to safe position at (" .. string.format("%.1f", safe_pos.x) .. ", " .. string.format("%.1f", safe_pos.y) .. ") before scouting")
                        goto continue
                    else
                        log("Warning: Leader " .. leader.unit_number .. " is near water but could not find safe position")
                    end
                end

                local target_pos = get_unvisited_chunk(actual_leader_pos, party)
                if target_pos.x == actual_leader_pos.x and target_pos.y == actual_leader_pos.y then
                    log("No valid chunk found for party " .. party_id, "error")
                    goto continue
                end

                -- Verify target position is not in water
                if is_position_on_water(surface, target_pos, 1.5) then
                    local safe_target = find_safe_position_away_from_water(surface, leader.entity, target_pos, 30)
                    if safe_target then
                        target_pos = safe_target
                        log("Target chunk position was in water, using safe alternative at (" .. string.format("%.1f", safe_target.x) .. ", " .. string.format("%.1f", safe_target.y) .. ")")
                    else
                        log("Warning: Target chunk position is in water and no safe alternative found")
                        goto continue
                    end
                end

                leader.entity.autopilot_destination = nil
                request_multiple_paths(actual_leader_pos, target_pos, party, surface, leader.unit_number)
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

-- Process pending water moves (bots that need to move away from water)
local function process_pending_water_moves(event)
    if not storage.pending_water_moves then return end
    
    for unit_number, move_data in pairs(storage.pending_water_moves) do
        if event.tick >= move_data.tick then
            local creeper = storage.creeperbots[unit_number]
            if creeper and creeper.entity and creeper.entity.valid then
                local entity = creeper.entity
                -- Clear any existing destinations and move away
                entity.autopilot_destination = nil
                entity.add_autopilot_destination(move_data.position)
                --game.print("CreeperBot " .. unit_number .. " moving away from water")
            end
            storage.pending_water_moves[unit_number] = nil
        end
    end
end

-- Check for bots near water and move them away
local function check_and_move_bots_away_from_water(event)
    for unit_number, creeper in pairs(storage.creeperbots or {}) do
        if not (creeper.entity and creeper.entity.valid) then
            goto continue
        end
        
        local entity = creeper.entity
        local position = entity.position
        local surface = entity.surface
        
        -- Only check bots in waking state that are stationary (not moving)
        if creeper.state == "waking" and entity.speed == 0 then
            -- Check if bot is on or very close to water
            if is_position_on_water(surface, position, 2.5) then
                -- Find a safe position away from water
                local safe_position = find_safe_position_away_from_water(surface, entity, position, 30)
                if safe_position then
                    -- Clear any existing destinations and move away
                    entity.autopilot_destination = nil
                    entity.add_autopilot_destination(safe_position)
                    --game.print("CreeperBot " .. unit_number .. " detected near water, moving away")
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
    check_and_teleport_stuck_bots(event)
    check_and_move_bots_away_from_water(event)
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
                layers = { 
                    water_tile = true,
                    cliff = true  -- Prefer avoiding cliffs in pathfinding
                },
                colliding_with_tiles_only = true,
                consider_tile_transitions = true
            }
            -- Define start_offsets to match the ones used in request_multiple_paths
            local start_offsets = {
                {x = 0, y = 0},
                --[[
                {x = 0, y = 4},
                {x = 4, y = 0},
                {x = -4, y = 0},
                {x = 0, y = -4},
                ]]
            }
            -- Use creeper's current position as start (with offset if needed)
            local current_pos = creeper.entity.position
            local start_pos = {
                x = current_pos.x + start_offsets[request.start_offset_index].x,
                y = current_pos.y + start_offsets[request.start_offset_index].y
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
            -- Check if this is a scouting path failure
            if (creeper.state == "scouting" or (party and party.state == "scouting")) and request.target_pos then
                log("Scouting path failed permanently for unit " .. (creeper.unit_number or "unknown") .. 
                    " to (" .. string.format("%.1f", request.target_pos.x) .. ", " .. string.format("%.1f", request.target_pos.y) .. ")" ..
                    ", request_id: " .. event.id)
            else
                log("Path request " .. event.id .. " failed permanently")
            end
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
    
    -- Filter out water waypoints and cliff-problematic waypoints
    local surface = creeper.entity.surface
    local safe_waypoints = {}
    local skipped_water = 0
    local skipped_cliffs = 0
    
    for i, waypoint in ipairs(event.path) do
        local waypoint_pos = waypoint.position
        local prev_pos = (i > 1) and event.path[i-1].position or creeper.entity.position
        local next_pos = (i < #event.path) and event.path[i+1].position or nil
        
        -- Check if waypoint is on water
        if is_position_on_water(surface, waypoint_pos, 1.5) then
            skipped_water = skipped_water + 1
            -- If this is the first waypoint and it's in water, try to find a safe alternative
            if #safe_waypoints == 0 then
                local current_pos = creeper.entity.position
                local safe_pos = find_safe_position_away_from_water(surface, creeper.entity, current_pos, 10)
                if safe_pos then
                    table.insert(safe_waypoints, safe_pos)
                    log("First waypoint was in water, using safe alternative at (" .. string.format("%.1f", safe_pos.x) .. ", " .. string.format("%.1f", safe_pos.y) .. ")")
                end
            end
        -- Check if waypoint is near a corner cliff (avoid)
        elseif is_position_near_corner_cliff(surface, waypoint_pos, 2.5) then
            skipped_cliffs = skipped_cliffs + 1
            -- Skip corner cliff waypoints
        -- Check if waypoint path is parallel to a cliff (avoid)
        elseif is_waypoint_parallel_to_cliff(surface, waypoint_pos, prev_pos, next_pos, 2.0) then
            skipped_cliffs = skipped_cliffs + 1
            -- Skip parallel cliff paths
        -- Allow waypoints that cross straight cliffs (2-3 cliffs in a line)
        elseif is_waypoint_crossing_straight_cliff(surface, waypoint_pos, prev_pos, next_pos, 2.5) then
            -- This is OK - straight cliffs are easy to traverse
            table.insert(safe_waypoints, waypoint_pos)
        -- No cliff issues, add waypoint
        else
            table.insert(safe_waypoints, waypoint_pos)
        end
    end
    
    -- If we filtered out all waypoints, try to find a safe path to the target
    if #safe_waypoints == 0 then
        local current_pos = creeper.entity.position
        local safe_pos = find_safe_position_away_from_water(surface, creeper.entity, request.target_pos, 30)
        if safe_pos then
            table.insert(safe_waypoints, safe_pos)
            log("All waypoints were problematic, using safe alternative target at (" .. string.format("%.1f", safe_pos.x) .. ", " .. string.format("%.1f", safe_pos.y) .. ")")
        else
            log("Warning: Could not find safe waypoints for unit " .. request.creeper_unit_number)
            storage.path_requests[event.id] = nil
            return
        end
    end
    
    -- Check if path has too many waypoints (likely going around a large obstacle like a lake)
    local MAX_WAYPOINTS = 75
    if #safe_waypoints > MAX_WAYPOINTS then
        log("Path rejected: too many waypoints (" .. #safe_waypoints .. ") for unit " .. request.creeper_unit_number .. " to (" .. string.format("%.1f", request.target_pos.x) .. ", " .. string.format("%.1f", request.target_pos.y) .. ")")
        
        -- Check if this is a path to a nest target (nest on other side of lake - not a threat)
        local is_nest_target = false
        if party and party.target_nest and party.target_nest.valid then
            local nest_pos = party.target_nest.position
            local dist_to_nest = calculate_distance(request.target_pos, nest_pos)
            if dist_to_nest < 5 then  -- Target position is near the nest
                is_nest_target = true
            end
        end
        if not is_nest_target and creeper.target and creeper.target.valid then
            local target_pos = creeper.target.position
            local dist_to_target = calculate_distance(request.target_pos, target_pos)
            if dist_to_target < 5 and (creeper.target.type == "unit-spawner" or creeper.target.type == "turret") then
                is_nest_target = true
            end
        end
        
        -- If this is a nest target with too many waypoints, it's not a threat - clear it and return to scouting
        if is_nest_target and party and not is_distractor then
            -- Get nest position for tracking
            local nest_pos = nil
            if party.target_nest and party.target_nest.valid then
                nest_pos = party.target_nest.position
            elseif creeper.target and creeper.target.valid then
                nest_pos = creeper.target.position
            end
            
            log("Nest target rejected: too many waypoints (" .. #safe_waypoints .. ") - nest is not a threat (on other side of obstacle)" .. (nest_pos and " at (" .. string.format("%.1f", nest_pos.x) .. ", " .. string.format("%.1f", nest_pos.y) .. ")" or ""))
            
            -- Track rejected nest to prevent re-detection loop
            if nest_pos then
                party.rejected_nests = party.rejected_nests or {}
                local nest_key = string.format("%.1f,%.1f", nest_pos.x, nest_pos.y)
                party.rejected_nests[nest_key] = game.tick
                log("Marked nest at (" .. string.format("%.1f", nest_pos.x) .. ", " .. string.format("%.1f", nest_pos.y) .. ") as rejected, will ignore for 50 seconds")
            end
            
            -- Clear nest target from party
            if party.target_nest then
                party.target_nest = nil
            end
            party.target_health = nil
            party.target_max_health = nil
            party.attack_initiated = false
            party.scout_sent = false
            
            -- Clear target from all party members and transition back to scouting
            for unit_number, member in pairs(storage.creeperbots or {}) do
                if member.party_id == creeper.party_id and member.entity and member.entity.valid then
                    if member.state == "preparing_to_attack" or member.state == "approaching" then
                        member.target = nil
                        member.target_position = nil
                        member.target_health = nil
                        member.assigned_target = nil
                        member.state = member.is_guard and "guard" or "scouting"
                        update_color(member.entity, member.state)
                        member.entity.follow_target = nil
                        member.entity.autopilot_destination = nil
                        if storage.scheduled_autopilots and storage.scheduled_autopilots[unit_number] then
                            storage.scheduled_autopilots[unit_number] = nil
                        end
                    end
                end
            end
            
            -- Transition party back to scouting
            if party then
                party.state = "scouting"
            end
            
            storage.path_requests[event.id] = nil
            return
        end
        
        -- For scouting paths, mark this chunk as visited and find a closer one
        if (creeper.state == "scouting" or (party and party.state == "scouting")) and not is_distractor then
            -- Mark the target chunk as visited so it's less likely to be selected again
            local chunk_key = request.chunk_x .. "," .. request.chunk_y
            if party and party.visited_chunks then
                party.visited_chunks[chunk_key] = (party.visited_chunks[chunk_key] or 0) + 1
            end
            
            -- Find a closer unvisited chunk
            local current_pos = creeper.entity.position
            local closer_target = get_unvisited_chunk(current_pos, party)
            
            -- Verify the closer target is actually different
            if closer_target.x ~= current_pos.x or closer_target.y ~= current_pos.y then
                local dist_to_original = calculate_distance(current_pos, request.target_pos)
                local dist_to_closer = calculate_distance(current_pos, closer_target)
                log("Finding closer target: original distance " .. string.format("%.1f", dist_to_original) .. ", new distance " .. string.format("%.1f", dist_to_closer))
                -- Request path to closer target (even if not strictly closer, it's a different chunk that might have a better path)
                request_multiple_paths(current_pos, closer_target, party, surface, creeper.unit_number)
            else
                log("No closer chunk found, will retry later")
            end
        end
        
        storage.path_requests[event.id] = nil
        return
    end
    
    creeper.entity.autopilot_destination = nil
    for _, waypoint_pos in ipairs(safe_waypoints) do
        creeper.entity.add_autopilot_destination(waypoint_pos)
    end
    
    if skipped_water > 0 or skipped_cliffs > 0 then
        log("Set " .. #safe_waypoints .. " safe autopilot destinations for unit " .. request.creeper_unit_number .. 
            " (skipped " .. skipped_water .. " water, " .. skipped_cliffs .. " cliff-problematic waypoints) to (" .. 
            request.target_pos.x .. "," .. request.target_pos.y .. ")")
    else
        log("Set " .. #safe_waypoints .. " autopilot destinations for unit " .. request.creeper_unit_number .. " (state: " .. (creeper.state or "nil") .. ") to (" .. request.target_pos.x .. "," .. request.target_pos.y .. ")")
    end
    
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

-- Update territory visualization for a player (call when map view changes)
local function update_territory_visualization(player_index)
    local player = game.get_player(player_index)
    if not player then return end
    
    storage.territory_visualization = storage.territory_visualization or {}
    local vis_state = storage.territory_visualization[player_index]
    if not vis_state or not vis_state.enabled then return end
    
    -- Clear old renderings
    for _, render_id in ipairs(vis_state.render_ids) do
        if type(render_id) == "number" then
            local render_obj = rendering.get_object_by_id(render_id)
            if render_obj and render_obj.valid then
                render_obj.destroy()
            end
        elseif type(render_id) == "userdata" then
            -- It's a render object directly
            if render_id.valid then
                render_id.destroy()
            end
        end
    end
    vis_state.render_ids = {}
    
    -- Get player's current surface
    local surface = player.surface or game.surfaces[1]
    if not surface or not surface.valid then return end
    
    local surface_id = surface.index
    local territory = storage.territory and storage.territory[surface_id]
    if not territory then return end
    
    -- Determine view center - use player position
    local center_pos = player.position
    local view_radius = 25  -- Render chunks within 25 chunks of center (800 tiles)
    
    local center_chunk = {
        x = math.floor(center_pos.x / 32),
        y = math.floor(center_pos.y / 32)
    }
    
    -- Render chunks in visible area (only safe and unsafe, skip unvisited)
    local rendered_count = 0
    for chunk_key, chunk_data in pairs(territory) do
        -- Only render chunks that have been visited (have safety status)
        if chunk_data.safe ~= nil then
            local cx, cy = chunk_key:match("([^,]+),([^,]+)")
            if cx and cy then
                cx = tonumber(cx)
                cy = tonumber(cy)
                
                -- Only render chunks within view radius
                local chunk_distance = math.max(math.abs(cx - center_chunk.x), math.abs(cy - center_chunk.y))
                if chunk_distance <= view_radius then
                    local chunk_pos = {x = cx * 32, y = cy * 32}
                    local chunk_size = 32
                    
                    -- Determine color based on chunk status
                    local color
                    if chunk_data.safe == true then
                        color = {r = 0, g = 0.8, b = 0, a = 0.25}  -- Green for safe
                    elseif chunk_data.safe == false then
                        color = {r = 0.8, g = 0, b = 0, a = 0.25}  -- Red for unsafe
                    else
                        -- Skip unvisited chunks (shouldn't happen due to check above, but just in case)
                        goto continue
                    end
                    
                    -- Draw rectangle for chunk
                    local render_obj = rendering.draw_rectangle{
                        color = color,
                        filled = true,
                        left_top = {x = chunk_pos.x, y = chunk_pos.y},
                        right_bottom = {x = chunk_pos.x + chunk_size, y = chunk_pos.y + chunk_size},
                        surface = surface,
                        draw_on_ground = true,
                        only_in_alt_mode = true  -- Only show in map mode (alt view)
                    }
                    
                    if render_obj then
                        -- Store the render object (could be userdata or number ID)
                        table.insert(vis_state.render_ids, render_obj)
                        rendered_count = rendered_count + 1
                    end
                end
            end
        end
        ::continue::
    end
    
    storage.territory_visualization[player_index] = vis_state
end

-- Toggle territory visualization for a player
local function toggle_territory_visualization(player_index)
    local player = game.get_player(player_index)
    if not player then return end
    
    storage.territory_visualization = storage.territory_visualization or {}
    local vis_state = storage.territory_visualization[player_index] or {enabled = false, render_ids = {}}
    
    if vis_state.enabled then
        -- Disable: Clear all renderings
        for _, render_id in ipairs(vis_state.render_ids) do
            if type(render_id) == "number" then
                local render_obj = rendering.get_object_by_id(render_id)
                if render_obj and render_obj.valid then
                    render_obj.destroy()
                end
            elseif type(render_id) == "userdata" then
                -- It's a render object directly
                if render_id.valid then
                    render_id.destroy()
                end
            end
        end
        vis_state.render_ids = {}
        vis_state.enabled = false
        player.print("Territory visualization disabled")
    else
        -- Enable: Render chunks
        vis_state.enabled = true
        vis_state.render_ids = {}
        update_territory_visualization(player_index)
        player.print("Territory visualization enabled (press Ctrl+T again to toggle off)")
    end
    
    storage.territory_visualization[player_index] = vis_state
end

-- Handle keyboard shortcut
local function handle_territory_toggle(event)
    toggle_territory_visualization(event.player_index)
end

-- Update visualization when player moves (for map view updates)
local function handle_player_changed_position(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    
    storage.territory_visualization = storage.territory_visualization or {}
    local vis_state = storage.territory_visualization[event.player_index]
    if vis_state and vis_state.enabled then
        -- Update visualization periodically (every 2 seconds) to avoid lag
        if not vis_state.last_update_tick or (game.tick - vis_state.last_update_tick) > 120 then
            update_territory_visualization(event.player_index)
            vis_state.last_update_tick = game.tick
        end
    end
end

-- Register event handlers
script.on_init(initialize_storage)
script.on_configuration_changed(initialize_storage)

script.on_event(defines.events.on_built_entity, handle_entity_creation)
script.on_event(defines.events.on_robot_built_entity, handle_entity_creation)
script.on_event(defines.events.script_raised_revive, handle_entity_creation)
script.on_event(defines.events.script_raised_built, handle_entity_creation)
script.on_event(defines.events.on_trigger_created_entity, handle_trigger_created_entity)

script.on_event(defines.events.on_player_mined_entity, cleanup_creeperbot)
script.on_event(defines.events.on_entity_died, handle_entity_death)

script.on_event(defines.events.on_selected_entity_changed, handle_selected_entity)

-- Register custom input for territory visualization toggle
script.on_event("creeperbots-toggle-territory", handle_territory_toggle)

-- Update visualization periodically (every 2 seconds) for all connected players
script.on_nth_tick(120, function(event)  -- Every 2 seconds
    for player_index, _ in pairs(game.connected_players) do
        handle_player_changed_position({player_index = player_index})
    end
end)

-- Cleanup old territory data periodically (every 10 minutes)
script.on_nth_tick(36000, function()
    cleanup_old_territory_data(36000)  -- Remove chunks not checked in 10 minutes
end)

script.on_nth_tick(1, process_pending_water_moves)  -- Check every tick for pending water moves
script.on_nth_tick(15, process_autopilot_queue) 
script.on_nth_tick(30, process_creeperbots)
script.on_nth_tick(60, handle_tick_60)

script.on_event(defines.events.on_script_path_request_finished, handle_path_request)