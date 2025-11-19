-- Creeperbots - Exploding State Handler
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local config = require "scripts.behavior.config"
local rendering_module = require "scripts.behavior.rendering"

local exploding_state = {}

function exploding_state.handle_exploding_state(creeper, event, position, entity, surface, tier, party)
    -- Get tier config if not provided
    if not tier or type(tier) ~= "table" or not tier.explosion then
        tier = config.tier_configs[entity.name] or config.tier_configs["creeperbot-mk1"]
    end

    -- Ensure color is correct for exploding state
    update_color(entity, "exploding")
    
    -- Check if party has disbanded or transitioned - if so, clear party state
    if party then
        -- Check if party still exists and is valid
        if not storage.parties or not storage.parties[creeper.party_id] then
            -- Party was disbanded, clear state
            party = nil
            creeper.party_id = nil
            creeper.is_leader = false
            creeper.is_guard = false
            creeper.is_distractor = false
        elseif party.state == "scouting" and creeper.state == "exploding" then
            -- Party has moved on to scouting, but we're still in exploding
            -- Clear party association so we can hunt independently
            creeper.party_id = nil
            creeper.is_leader = false
            creeper.is_guard = false
            creeper.is_distractor = false
            party = nil
        end
    end

    -- ALWAYS validate target first - check every tick if target is invalid
    local target_valid = creeper.target and creeper.target.valid and creeper.target.health > 0
    
    -- If target is invalid, clear it immediately and force search
    if not target_valid then
        creeper.target = nil
        creeper.target_position = nil
        creeper.target_health = nil
        -- Clear movement since target is invalid
        entity.autopilot_destination = nil
        if storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] then
            storage.scheduled_autopilots[entity.unit_number] = nil
        end
    end
    
    -- Validate or find target - search periodically (every 30 ticks) or if target is invalid
    local needs_target_search = false
    if not target_valid then
        needs_target_search = true
    elseif not creeper.last_target_search or event.tick >= creeper.last_target_search + 30 then
        -- Periodically re-search for targets every 30 ticks (reduced from 60) to catch dead targets faster
        -- Also re-validate target before searching
        if not creeper.target or not creeper.target.valid or creeper.target.health <= 0 then
            target_valid = false
            creeper.target = nil
            creeper.target_position = nil
            creeper.target_health = nil
        end
        needs_target_search = true
    end
    
    if needs_target_search then
        creeper.last_target_search = event.tick
        
        -- Search in expanding radius: start with 30 tiles, then 50 if nothing found
        local search_radius = 30
        local new_target = nil
        
        -- Priority 1: Look for turrets and nests first (biggest threats)
        local high_priority_targets = surface.find_entities_filtered({
            type = {"turret", "unit-spawner"},
            position = position,
            radius = search_radius,
            force = "enemy"
        })
        for _, target in ipairs(high_priority_targets) do
            if target.valid and target.health > 0 then
                new_target = target
                break
            end
        end
        
        -- Priority 2: If no turrets/nests found, check for enemy units
        if not new_target then
            local enemy_units = surface.find_entities_filtered({
                type = "unit",
                position = position,
                radius = search_radius,
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
        
        -- If still no target found, expand search to 50 tiles
        if not new_target then
            search_radius = 50
            -- Priority 1: Look for turrets and nests first (biggest threats)
            high_priority_targets = surface.find_entities_filtered({
                type = {"turret", "unit-spawner"},
                position = position,
                radius = search_radius,
                force = "enemy"
            })
            for _, target in ipairs(high_priority_targets) do
                if target.valid and target.health > 0 then
                    new_target = target
                    break
                end
            end
            
            -- Priority 2: If no turrets/nests found, check for enemy units
            if not new_target then
                local enemy_units = surface.find_entities_filtered({
                    type = "unit",
                    position = position,
                    radius = search_radius,
                    force = "enemy"
                })
                
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
        end
        
        if new_target then
            creeper.target = new_target
            creeper.target_position = new_target.position
            creeper.target_health = new_target.health
        else
            -- No target found in search - re-validate existing target (it might have died during search)
            local has_valid_target = creeper.target and creeper.target.valid and creeper.target.health > 0
            if not has_valid_target then
                -- No valid target exists - reform into formation (waking state)
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
            -- If we have a valid existing target, keep using it (it was validated at the start)
        end
    end

    -- Validate target again before using it (it might have died between initial check and now)
    -- This is critical - target could die at any time
    if not creeper.target or not creeper.target.valid or creeper.target.health <= 0 then
        -- Target became invalid - transition to waking immediately
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
    
    -- Target is valid, update position and health (re-validate one more time after update)
    creeper.target_position = creeper.target.position
    creeper.target_health = creeper.target.health
    
    -- Final validation - target might have died during position update
    if not creeper.target.valid or creeper.target.health <= 0 then
        -- Target died during update - transition to waking
        creeper.target = nil
        creeper.target_position = nil
        creeper.target_health = nil
        entity.autopilot_destination = nil
        if storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] then
            storage.scheduled_autopilots[entity.unit_number] = nil
        end
        creeper.grouping_initialized = false
        creeper.party_id = nil
        creeper.is_leader = false
        creeper.is_guard = false
        creeper.is_distractor = false
        creeper.waking_initialized = nil
        creeper.state = "waking"
        update_color(entity, "waking")
        return false
    end

    -- Calculate distance to target (using validated target_position)
    local dist_to_target = calculate_distance(position, creeper.target_position)
    local explosion_range = tier.radius or 3.5
    
    -- Explosion distance depends on target type:
    -- Nests have large radius, bots can't get to center - use 5 tiles
    -- Turrets and units are smaller - use 2 tiles
    local explosion_distance = 5  -- Default for nests
    if creeper.target and creeper.target.valid then
        if creeper.target.type == "unit" or creeper.target.type == "turret" then
            explosion_distance = 2  -- Units and turrets need to be closer
        end
        -- Nests use default 5 tiles
    end

    -- Close enough to explode
    if dist_to_target <= explosion_distance then
        -- Create explosion
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
            if nearby_entity.valid and nearby_entity.health then
                nearby_entity.damage(tier.damage, "enemy", "explosion")
            end
        end
        
        -- Destroy the bot
        entity.die("enemy")
        return true
    end
    
    -- Still too far - continue moving using direct movement
    -- Clear follow_target if set
    if entity.follow_target then
        entity.follow_target = nil
    end
    
    -- Use direct movement toward target (same approach as approaching state)
    -- ALWAYS validate target immediately before using it for movement (target might have died)
    local current_target_valid = creeper.target and creeper.target.valid and creeper.target.health > 0
    
    if current_target_valid then
        -- Update target position before using it
        creeper.target_position = creeper.target.position
        creeper.target_health = creeper.target.health
        
        local target_pos = creeper.target_position
        local dist_to_target = calculate_distance(position, target_pos)
        
        -- If we're far away (> 20 tiles), use pathfinding
        if dist_to_target > 20 then
            if not creeper.last_path_request or event.tick >= creeper.last_path_request + 60 then
                request_multiple_paths(position, target_pos, party, surface, creeper.unit_number)
                creeper.last_path_request = event.tick
            end
        elseif dist_to_target > explosion_distance then
            -- Close but not at explosion range - set autopilot directly to target position
            -- Update movement every 15 ticks or if no autopilot destination
            if not entity.autopilot_destination or (not creeper.last_movement_update or event.tick >= creeper.last_movement_update + 15) then
                -- Clear existing autopilot and add new destination directly to target
                entity.autopilot_destination = nil
                local success, err = pcall(function()
                    entity.add_autopilot_destination(target_pos)
                end)
                
                if success then
                    creeper.last_movement_update = event.tick
                else
                    -- If autopilot fails, try pathfinding
                    if not creeper.last_path_request or event.tick >= creeper.last_path_request + 60 then
                        request_multiple_paths(position, target_pos, party, surface, creeper.unit_number)
                        creeper.last_path_request = event.tick
                    end
                end
            end
        end
        -- If we're within explosion_distance, we'll explode on next check (handled above)
    else
        -- Target became invalid - clear movement and transition to waking on next tick
        creeper.target = nil
        creeper.target_position = nil
        creeper.target_health = nil
        entity.autopilot_destination = nil
        if storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] then
            storage.scheduled_autopilots[entity.unit_number] = nil
        end
        -- Don't transition here - let the validation at the top handle it on next tick
        -- This prevents multiple transitions in one tick
    end
    
    return true
end

return exploding_state

