-- Creeperbots - Approaching State Handler
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local config = require "scripts.behavior.config"
local rendering_module = require "scripts.behavior.rendering"

local approaching_state = {}

function approaching_state.handle_approaching_state(creeper, event, position, entity, surface, tier, party)
    -- Clear follow_target to ensure autopilot can work
    if entity.follow_target then
        entity.follow_target = nil
    end

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
        return true
    end

    -- Validate target exists
    if not creeper.target or not creeper.target.valid or (creeper.target.valid and creeper.target.health <= 0) then
        -- First: Look for nearby nests within 30 tiles
        local nearby_nests = surface.find_entities_filtered({
            type = "unit-spawner",
            position = position,
            radius = 30,
            force = "enemy"
        })
        local new_target = nil
        for _, nest in ipairs(nearby_nests) do
            if nest.valid and nest.health > 0 then
                new_target = nest
                break
            end
        end
        
        -- If no nests found, check for enemy units within 30 tiles
        if not new_target then
            local enemy_units = surface.find_entities_filtered({
                type = "unit",
                position = position,
                radius = 30,
                force = "enemy"
            })
            
            -- Find enemy unit with fewest bots targeting it (load balancing)
            local unit_target_counts = {}
            for _, member in pairs(storage.creeperbots or {}) do
                if member.target and member.target.valid and member.target.type == "unit" then
                    local unit_num = member.target.unit_number
                    unit_target_counts[unit_num] = (unit_target_counts[unit_num] or 0) + 1
                end
            end
            
            local min_targets = math.huge
            for _, enemy in ipairs(enemy_units) do
                if enemy.valid and enemy.health > 0 then
                    local target_count = unit_target_counts[enemy.unit_number] or 0
                    if target_count < min_targets then
                        min_targets = target_count
                        new_target = enemy
                    end
                end
            end
        end
        
        if new_target then
            creeper.target = new_target
            creeper.target_position = new_target.position
            creeper.target_health = new_target.health
        else
            -- No target found, reform into formation (waking state)
            -- Clear all attack-related data
            creeper.target = nil
            creeper.target_position = nil
            creeper.target_health = nil
            if party then party.shared_target = nil end
            rendering_module.clear_renderings(creeper)
            
            -- Clear movement state
            entity.follow_target = nil
            entity.autopilot_destination = nil
            if storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] then
                storage.scheduled_autopilots[entity.unit_number] = nil
            end
            
            -- Clear all grouping/party state to start fresh
            creeper.grouping_initialized = false
            creeper.party_id = nil
            creeper.is_leader = false
            creeper.is_guard = false
            creeper.is_distractor = false
            
            -- Reset waking state to start fresh
            creeper.waking_initialized = nil
            
            -- Transition to waking state to reform
            creeper.state = "waking"
            update_color(entity, "waking")
            return false
        end
    end

    -- Update target position (in case it moved)
    creeper.target_position = creeper.target.position
    creeper.target_health = creeper.target.health

    -- Calculate distance to target
    local target_pos = creeper.target_position
    local dist_to_target = calculate_distance(position, target_pos)

    -- Get explosion range from tier config
    local tier_config = config.tier_configs[entity.name] or config.tier_configs["creeperbot-mk1"]
    local explosion_range = tier_config.radius or 3.5
    
    -- Explosion distance depends on target type:
    -- Nests have large radius, bots can't get to center - use explosion_range + 5 tiles
    -- Units are smaller - use 2 tiles
    local explosion_distance = explosion_range + 5  -- Default for nests
    if creeper.target and creeper.target.valid then
        if creeper.target.type == "unit" then
            explosion_distance = 2  -- Units need to be closer
        end
    end

    -- Transition to exploding state if within explosion range
    if dist_to_target <= explosion_distance then
        creeper.state = "exploding"
        update_color(entity, "exploding")
        return true
    end

    -- Check if we just reached a waypoint (no current destination but waypoints remain)
    -- If within 20 tiles of target, clear queue and go directly to target
    if not entity.autopilot_destination and entity.autopilot_destinations and #entity.autopilot_destinations > 0 then
        if dist_to_target <= 20 then
            -- Within 20 tiles - clear all remaining waypoints and go directly to target
            -- Clear current destination (which should already be nil, but ensure it)
            entity.autopilot_destination = nil
            -- Clear all remaining waypoints by repeatedly clearing until empty
            -- (autopilot_destinations is read-only, so we clear current destination repeatedly)
            local attempts = 0
            while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
                entity.autopilot_destination = nil
                attempts = attempts + 1
            end
            -- Now set autopilot directly to target
            local success, err = pcall(function()
                entity.add_autopilot_destination(target_pos)
            end)
            if success then
                return true
            end
        end
    end
    
    -- Also check if we have a current waypoint destination and are within 20 tiles of target
    -- If so, clear queue and go directly to target
    if entity.autopilot_destination and entity.autopilot_destinations and #entity.autopilot_destinations > 0 then
        if dist_to_target <= 20 then
            -- Clear current destination and all remaining waypoints
            entity.autopilot_destination = nil
            local attempts = 0
            while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
                entity.autopilot_destination = nil
                attempts = attempts + 1
            end
            -- Set autopilot directly to target
            local success, err = pcall(function()
                entity.add_autopilot_destination(target_pos)
            end)
            if success then
                return true
            end
        end
    end

    -- Use pathfinding for long distances, autopilot when close
    -- If no autopilot destination and far away, request pathfinding
    if not entity.autopilot_destination then
        if dist_to_target > 20 then
            -- Far away - use pathfinding to handle obstacles
            if not creeper.last_path_request or event.tick >= creeper.last_path_request + 60 then
                request_multiple_paths(position, target_pos, party, surface, creeper.unit_number)
                creeper.last_path_request = event.tick
            end
        elseif dist_to_target > explosion_distance then
            -- Close but not at explosion range - set autopilot directly to target
            local success, err = pcall(function()
                entity.add_autopilot_destination(target_pos)
            end)
            if not success then
                -- If autopilot fails, try pathfinding
                request_multiple_paths(position, target_pos, party, surface, creeper.unit_number)
            end
        end
    end

    return true
end

return approaching_state

