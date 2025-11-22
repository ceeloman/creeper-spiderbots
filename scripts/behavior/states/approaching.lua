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

    -- Validate target exists or find new target
    if not creeper.target or not creeper.target.valid or (creeper.target.valid and creeper.target.health <= 0) then
        -- Initialize search radius if not set
        if not creeper.search_radius then
            creeper.search_radius = 15  -- Start with 15 tiles for nests/turrets
        end
        
        local new_target = nil
        
        -- First: Look for closest nest/turret within 15 tiles (priority targets)
        local nearby_structures = surface.find_entities_filtered({
            type = {"unit-spawner", "turret"},
            position = position,
            radius = 15,
            force = "enemy"
        })
        
        local closest_structure = nil
        local closest_structure_dist = math.huge
        for _, structure in ipairs(nearby_structures) do
            if structure.valid and structure.health > 0 then
                local dist = calculate_distance(position, structure.position)
                if dist < closest_structure_dist then
                    closest_structure_dist = dist
                    closest_structure = structure
                end
            end
        end
        
        if closest_structure then
            new_target = closest_structure
            creeper.search_radius = 15  -- Reset search radius when target found
        else
            -- No nests/turrets within 15 tiles, check for units within 10 tiles
            local search_radius_for_units = 10
            local enemy_units = surface.find_entities_filtered({
                type = "unit",
                position = position,
                radius = search_radius_for_units,
                force = "enemy"
            })
            
            -- Find closest enemy unit
            local closest_unit = nil
            local closest_unit_dist = math.huge
            for _, enemy in ipairs(enemy_units) do
                if enemy.valid and enemy.health > 0 then
                    local dist = calculate_distance(position, enemy.position)
                    if dist < closest_unit_dist then
                        closest_unit_dist = dist
                        closest_unit = enemy
                    end
                end
            end
            
            if closest_unit then
                new_target = closest_unit
                creeper.search_radius = 10  -- Reset search radius when target found
            else
                -- No targets found, incrementally increase search radius by 10 tiles
                creeper.search_radius = creeper.search_radius + 10
                
                -- Search for any enemy within expanded radius
                local all_enemies = surface.find_entities_filtered({
                    type = {"unit", "turret", "unit-spawner"},
                    position = position,
                    radius = creeper.search_radius,
                    force = "enemy"
                })
                
                local closest_enemy = nil
                local closest_enemy_dist = math.huge
                for _, enemy in ipairs(all_enemies) do
                    if enemy.valid and enemy.health > 0 then
                        local dist = calculate_distance(position, enemy.position)
                        if dist < closest_enemy_dist then
                            closest_enemy_dist = dist
                            closest_enemy = enemy
                        end
                    end
                end
                
                if closest_enemy then
                    new_target = closest_enemy
                end
            end
        end
        
        if new_target then
            creeper.target = new_target
            creeper.target_position = new_target.position
            creeper.target_health = new_target.health
            
            -- Reset launch tracking for new target (so we can launch once for this new target)
            -- Don't reset - we want to track launches per target, so new target = new launch allowed
            
            -- Immediately set autopilot to new target after finding it
            entity.autopilot_destination = nil
            local success, err = pcall(function()
                entity.add_autopilot_destination(new_target.position)
            end)
            if not success then
                -- If autopilot fails, try pathfinding
                if not creeper.last_path_request or event.tick >= creeper.last_path_request + 60 then
                    request_multiple_paths(position, new_target.position, party, surface, creeper.unit_number)
                    creeper.last_path_request = event.tick
                end
            end
        else
            -- No target found
            -- If guard was part of a party, return to grouping state to retake position
            -- Otherwise, reform into formation (waking state)
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
            
            -- If guard was part of a party, return to grouping to retake guard position
            if creeper.party_id and party and party.state == "grouping" and creeper.is_guard then
                -- Reset grouping initialization so guard can retake position
                creeper.grouping_initialized = false
                creeper.state = "grouping"
                update_color(entity, "grouping")
                return false
            end
            
            -- Otherwise, clear all grouping/party state to start fresh
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

    -- IMMEDIATELY check distance and transition to exploding if within range
    -- Calculate distance to target using fresh position
    local target_pos = creeper.target_position
    local dist_to_target = calculate_distance(position, target_pos)

    -- Get explosion range from tier config
    local tier_config = config.tier_configs[entity.name] or config.tier_configs["creeperbot-mk1"]
    local explosion_range = tier_config.radius or 3.5
    
    -- Explode when within 1.5 tiles of target (for all target types) - reduced for faster explosion
    local explosion_distance = 1.5

    -- Transition to exploding state immediately if within explosion range
    if dist_to_target <= explosion_distance then
        creeper.state = "exploding"
        update_color(entity, "exploding")
        return true
    end

    -- Launch/teleport logic with cooldown
    -- Launch cooldown: 4 seconds (240 ticks)
    local launch_cooldown = 240
    
    -- Track if we've launched for THIS specific target (not globally)
    local target_id = creeper.target and creeper.target.valid and creeper.target.unit_number or nil
    local has_launched_for_this_target = false
    if target_id and creeper.launched_targets then
        has_launched_for_this_target = creeper.launched_targets[target_id] == true
    end
    
    local cooldown_expired = true  -- Default to true if never launched
    if creeper.last_teleport_tick then
        cooldown_expired = event.tick >= creeper.last_teleport_tick + launch_cooldown
    end
    
    -- Check if we should launch
    -- Initial launch for THIS target: must be within 45 tiles (but not too close to explode) AND cooldown expired
    -- Subsequent launches for same target: must be >20 tiles away and cooldown MUST be expired
    local should_launch = false
    if not has_launched_for_this_target then
        -- First launch for this target - only if within 45 tiles, not too close to explode, and cooldown expired
        should_launch = dist_to_target <= 45 and dist_to_target > explosion_distance and cooldown_expired
    else
        -- Subsequent launches for same target - >20 tiles away and cooldown MUST be expired
        should_launch = dist_to_target > 20 and cooldown_expired
    end
    
    if should_launch then
        -- Calculate landing position: random offset within 10 tiles of target
        local random = game.create_random_generator()
        local offset_radius = 3 + random() * 7  -- 3-10 tiles from target
        local landing_pos = get_random_position_in_radius(target_pos, offset_radius)
        
        -- Find a safe non-colliding position near the landing point
        local safe_landing_pos = surface.find_non_colliding_position("character", landing_pos, 20, 0.5)
        if not safe_landing_pos then
            safe_landing_pos = landing_pos
        end
        
        -- Clear movement state before teleporting (clear all autopilot destinations)
        entity.autopilot_destination = nil
        local attempts = 0
        while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
            entity.autopilot_destination = nil
            attempts = attempts + 1
        end
        if storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number] then
            storage.scheduled_autopilots[creeper.unit_number] = nil
        end
        
        -- Set teleport cooldown BEFORE creating projectile (so it's stored in teleport data)
        creeper.last_teleport_tick = event.tick
        
        -- Mark that we've launched for this target
        if target_id then
            creeper.launched_targets = creeper.launched_targets or {}
            creeper.launched_targets[target_id] = true
        end
        
        -- Teleport to landing position (target data is preserved in creeper, will be stored in teleport)
        -- Note: We clear target AFTER teleportation so bot searches for new target near landing
        create_creeperbot_projectile(position, safe_landing_pos, creeper, 3)
        
        -- Clear target AFTER storing in teleport data so bot will search for new target near landing position
        creeper.target = nil
        creeper.target_position = nil
        creeper.target_health = nil
        creeper.search_radius = nil  -- Reset search radius after launch
        if party then party.shared_target = nil end
        return true
    end
    
    -- If within 20 tiles or on cooldown, use autopilot to move toward target
    if dist_to_target > explosion_distance then
        if not entity.autopilot_destination then
            local success, err = pcall(function()
                entity.add_autopilot_destination(target_pos)
            end)
            if not success then
                -- If autopilot fails, try pathfinding
                if not creeper.last_path_request or event.tick >= creeper.last_path_request + 60 then
                    request_multiple_paths(position, target_pos, party, surface, creeper.unit_number)
                    creeper.last_path_request = event.tick
                end
            end
        end
    end


    return true
end

return approaching_state


