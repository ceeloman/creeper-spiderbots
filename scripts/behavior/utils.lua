-- Creeperbots - Behavior utilities module
-- Utility functions for behavior logic
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local config = require "scripts.behavior.config"

-- File logging function - uses Factorio's log() which writes to factorio-current.log
function log_to_file(message)
    local timestamp = game.tick
    local log_entry = "[CREEPERBOT] [" .. timestamp .. "] " .. message
    log(log_entry)
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
        --game.print("Found enemy unit at (" .. nearest_unit.position.x .. "," .. nearest_unit.position.y .. "), distance: " .. nearest_unit_distance)
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
                            -- State transition removed - to be reimplemented
                            -- creeper.state = "approaching"
                            -- creeper.entity.color = {r = 1, g = 0, b = 0}
                            -- request_multiple_paths(creeper.entity.position, target.position, party, surface, creeper.entity.unit_number)
                        end
                    end
                end
            end
        end
    end
end

local utils = {}

utils.log_to_file = log_to_file
utils.scan_for_enemies = scan_for_enemies
utils.broadcast_target = broadcast_target

return utils

