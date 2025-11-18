-- Creeperbots - Configuration module
-- Tier configurations and related helper functions
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local config = {}

-- Tier configurations
config.tier_configs = {
    ["creeperbot-mk1"] = { tier = 1, damage = 200, radius = 3.5, max_targeting = 3, explosion = "big-explosion" },
    ["creeperbot-mk2"] = { tier = 2, damage = 400, radius = 5.0, max_targeting = 2, explosion = "massive-explosion" },
    ["creeperbot-mk3-nuclear"] = { tier = 3, damage = 900, radius = 20, max_targeting = 1, explosion = "nuke-explosion", extra_effect = "nuclear-smoke" },
}

function config.get_creeperbot_tier(entity_name)
    --game.print("Debug: get_creeperbot_tier called for: " .. tostring(entity_name))
    local tier_config = config.tier_configs[entity_name]
    if tier_config then
        return tier_config.tier
    end
    --game.print("Debug: Unknown entity: " .. tostring(entity_name) .. ", using default tier (mk1)")
    return config.tier_configs["creeperbot-mk1"].tier
end

function config.get_guard_positions(guard_count)
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

return config

