-- Creeperbots - Disable alerts for creeperbot entities
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

-- Disable alerts when damaged or destroyed for all creeperbot types
local creeperbot_names = {"creeperbot-mk1", "creeperbot-mk2", "creeperbot-mk3-nuclear"}

for _, bot_name in ipairs(creeperbot_names) do
    local bot = data.raw["spider-vehicle"][bot_name]
    if bot then
        bot.alert_when_damaged = false
    end
end

