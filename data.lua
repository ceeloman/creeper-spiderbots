if mods["spiderbots"] then
    require("prototypes/spiderbots")
end

-- Create projectile entities for each creeperbot type (for teleportation)
local creeperbot_names = {"creeperbot-mk1", "creeperbot-mk2", "creeperbot-mk3-nuclear"}
for _, bot_name in ipairs(creeperbot_names) do
    local projectile_name = bot_name .. "-trigger"
    local projectile = {
        type = "projectile",
        name = projectile_name,
        acceleration = 0.005,
        action = {
            action_delivery = {
                target_effects = {
                    {
                        entity_name = bot_name,
                        type = "create-entity",
                        show_in_tooltip = true,
                        trigger_created_entity = true
                    }
                },
                type = "instant"
            },
            type = "direct"
        },
        animation = data.raw["projectile"]["distractor-capsule"] and data.raw["projectile"]["distractor-capsule"].animation or nil,
        shadow = data.raw["projectile"]["distractor-capsule"] and data.raw["projectile"]["distractor-capsule"].shadow or nil,
        flags = { "not-on-map" },
        enable_drawing_with_mask = true,
        hidden = true,
    }
    data:extend { projectile }
end

-- Register custom input for territory visualization
data:extend({
    {
        type = "custom-input",
        name = "creeperbots-toggle-territory",
        key_sequence = "CONTROL + T",
        consuming = "none"
    }
})