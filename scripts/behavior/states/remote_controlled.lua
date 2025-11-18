-- Creeperbots - Remote Controlled State Handler
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local remote_controlled_state = {}

function remote_controlled_state.handle_remote_controlled_state(creeper, entity)
    -- Minimal handling as most logic is handled in waypoint processing
    entity.color = {r = 0, g = 0, b = 1}
    --game.print("CreeperBot " .. entity.unit_number .. "251")
end

return remote_controlled_state

