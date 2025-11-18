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

    -- Validate or find target
    if not creeper.target or not creeper.target.valid or (creeper.target.valid and creeper.target.health <= 0) then
        -- Look for nearby nests within 20 tiles
        local nests = surface.find_entities_filtered({
            type = "unit-spawner",
            position = position,
            radius = 20,
            force = "enemy"
        })
        local new_target = nil
        for _, nest in ipairs(nests) do
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

    -- Update target position and health
    if creeper.target and creeper.target.valid then
        creeper.target_position = creeper.target.position
        creeper.target_health = creeper.target.health
    end

    -- Calculate distance to target
    local dist_to_target = calculate_distance(position, creeper.target.position)
    local explosion_range = tier.radius or 3.5

    -- Close enough to explode (within 5 tiles)
    if dist_to_target <= 5 then
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
    -- Update movement every 15 ticks or if no autopilot destination
    if not entity.autopilot_destination or (not creeper.last_movement_update or event.tick >= creeper.last_movement_update + 15) then
        local target_pos = creeper.target.position
        local dx = target_pos.x - position.x
        local dy = target_pos.y - position.y
        local distance = math.sqrt(dx * dx + dy * dy)
        
        if distance > 5 then
            -- Normalize direction
            local dir_x = dx / distance
            local dir_y = dy / distance
            
            -- Move 5 tiles closer (or to 5 tiles away, whichever is closer)
            local move_distance = math.min(5, distance - 5)
            if move_distance > 0.5 then
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
                end
            end
        end
    end
    
    return true
end

return exploding_state

