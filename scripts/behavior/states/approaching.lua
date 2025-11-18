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

    -- Validate target exists
    if not creeper.target or not creeper.target.valid then
        -- Look for nearby nests
        local nearby_nests = surface.find_entities_filtered({
            type = "unit-spawner",
            position = position,
            radius = 50,
            force = "enemy"
        })
        local new_target = nil
        for _, nest in ipairs(nearby_nests) do
            if nest.valid and nest.health > 0 then
                new_target = nest
                break
            end
        end
        if new_target then
            creeper.target = new_target
            creeper.target_position = new_target.position
            creeper.target_health = new_target.health
        else
            -- No target found, revert to scouting
            creeper.state = "scouting"
            creeper.target = nil
            creeper.target_position = nil
            creeper.target_health = nil
            if party then party.shared_target = nil end
            rendering_module.clear_renderings(creeper)
            update_color(entity, "scouting")
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
    local explosion_distance = explosion_range + 5  -- Transition when within explosion range + 5 tiles

    -- Transition to exploding state if within explosion range
    if dist_to_target <= explosion_distance then
        creeper.state = "exploding"
        update_color(entity, "exploding")
        return true
    end

    -- NEW APPROACH: Use direct movement instead of pathfinding
    -- Continuously add waypoints closer to target, recalculating every few ticks
    -- This ensures the bot never stops until it's within explosion range
    
    -- Check if we need to update movement (every 15 ticks or if no autopilot destination)
    if not entity.autopilot_destination or (not creeper.last_movement_update or event.tick >= creeper.last_movement_update + 15) then
        -- Calculate direction vector toward target
        local dx = target_pos.x - position.x
        local dy = target_pos.y - position.y
        local distance = math.sqrt(dx * dx + dy * dy)
        
        if distance > 0 then
            -- Normalize direction
            local dir_x = dx / distance
            local dir_y = dy / distance
            
            -- Move 10 tiles closer (or to explosion_distance, whichever is closer)
            local move_distance = math.min(10, distance - explosion_distance)
            if move_distance > 1 then
                local next_pos = {
                    x = position.x + dir_x * move_distance,
                    y = position.y + dir_y * move_distance
                }
                
                -- Clear existing autopilot and add new destination
                entity.autopilot_destination = nil
                local success, err = pcall(function()
                    entity.add_autopilot_destination(next_pos)
                end)
                
                if success then
                    creeper.last_movement_update = event.tick
                else
                    -- If direct movement fails, fall back to pathfinding for long distances
                    if distance > 20 and (not creeper.last_path_request or event.tick >= creeper.last_path_request + 60) then
                        request_multiple_paths(position, target_pos, party, surface, creeper.unit_number)
                        creeper.last_path_request = event.tick
                    end
                end
            end
        end
    end

    return true
end

return approaching_state

