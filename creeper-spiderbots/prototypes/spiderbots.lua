-- Creeperbots - Explosive spiderbots that hunt enemy nests
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

-- Check if SpiderBots mod is installed and create_spidertron function exists
if not (mods["spiderbots"] and _G.create_spidertron) then
    return
end

-- Define Creeperbot configurations
local creeperbot_configs = {
    {
        name = "creeperbot-mk1",
        scale = 0.25,
        leg_scale = 0.7,
        leg_thickness = 1.0,
        leg_movement_speed = 1.5,
        health = 500,
        explosion = "big-explosion",
        damage = 100,
        explosion_radius = 3.5,
        recipe_ingredients = {
            { type = "item", name = "spiderbot", amount = 1 },
            { type = "item", name = "explosives", amount = 10 },
            { type = "item", name = "engine-unit", amount = 2 },
        },
        stack_size = 20,
        mining_time = 0.3,
    },
    {
        name = "creeperbot-mk2",
        scale = 0.30,
        leg_scale = 0.8,
        leg_thickness = 1.2,
        leg_movement_speed = 1.3,
        health = 750,
        explosion = "massive-explosion",
        damage = 200,
        explosion_radius = 5.0,
        recipe_ingredients = {
            { type = "item", name = "creeperbot-mk1", amount = 1 },
            { type = "item", name = "rocket", amount = 5 },
            { type = "item", name = "advanced-circuit", amount = 2 },
        },
        stack_size = 15,
        mining_time = 0.4,
    },
    {
        name = "creeperbot-mk3-nuclear",
        scale = 0.35,
        leg_scale = 0.9,
        leg_thickness = 1.4,
        leg_movement_speed = 1.1,
        health = 1000,
        explosion = "atomic-rocket",
        damage = 500,
        explosion_radius = 8.0,
        recipe_ingredients = {
            { type = "item", name = "creeperbot-mk2", amount = 1 },
            { type = "item", name = "atomic-bomb", amount = 1 },
            { type = "item", name = "processing-unit", amount = 5 },
        },
        stack_size = 10,
        mining_time = 0.5,
    },
}

-- Create entities for each Creeperbot tier
for _, config in pairs(creeperbot_configs) do
    -- Create the spiderbot using the SpiderBots mod function
    create_spidertron({
        scale = config.scale,
        leg_scale = config.leg_scale,
        name = config.name,
        leg_thickness = config.leg_thickness,
        leg_movement_speed = config.leg_movement_speed,
    })

    -- Get the prototype and modify it
    local prototype = data.raw["spider-vehicle"][config.name]
    if prototype then
        -- Set basic properties
        prototype.max_health = config.health
        prototype.minable = { result = config.name, mining_time = config.mining_time }
        prototype.placeable_by = { item = config.name, count = 1 }
        prototype.guns = nil
        prototype.inventory_size = 0
        prototype.equipment_grid = nil
        prototype.allow_passengers = false
        prototype.is_military_target = true
        prototype.se_allow_in_space = false

        -- Speed and movement adjustments
        prototype.torso_rotation_speed = prototype.torso_rotation_speed * 2.0
        prototype.torso_bob_speed = 0.8
        prototype.chunk_exploration_radius = 3

        -- Add custom explosion on death
        prototype.dying_explosion = config.explosion
        prototype.dying_trigger_effect = {
            type = "create-entity",
            entity_name = config.explosion,
            offset_deviation = {{-0.5, 0.5}, {-0.5, 0.5}},
            damage_type_filters = "fire",
            damage = config.damage,
            radius = config.explosion_radius,
        }

        -- Adjust legs
        local legs = prototype.spider_engine.legs
        if legs[1] then
            for _, leg in pairs(legs) do
                local leg_name = leg.leg
                local leg_prototype = data.raw["spider-leg"][leg_name]
                if leg_prototype then
                    leg_prototype.localised_name = { "entity-name." .. config.name .. "-leg" }
                    leg_prototype.walking_sound_volume_modifier = 0.1
                    leg_prototype.collision_mask = {
                        layers = {
                            water_tile = true,
                            rail = true,
                            ghost = true,
                            object = true,
                            empty_space = true,
                            lava_tile = true,
                            rail_support = true,
                            cliff = true,
                            spiderbot_leg = true,
                        },
                        not_colliding_with_itself = true,
                        consider_tile_transitions = false,
                        colliding_with_tiles_only = false,
                    }
                end
            end
        end

        -- Create item
        local spidertron_item = table.deepcopy(data.raw["item-with-entity-data"]["spidertron"])
        local item = {
            type = "item-with-entity-data",
            name = config.name,
            icon = spidertron_item.icon, -- Same graphics as original
            icon_size = spidertron_item.icon_size,
            icon_mipmaps = 4,
            stack_size = config.stack_size,
            subgroup = "transport",
            order = "b[personal-transport]-c[spidertron]-b[" .. config.name .. "]",
            place_result = config.name,
        }

        -- Create recipe
        local recipe = {
            type = "recipe",
            name = config.name,
            enabled = false,
            energy_required = 5,
            ingredients = config.recipe_ingredients,
            results = { { type = "item", name = config.name, amount = 2 } },
        }

        -- Extend prototypes
        data:extend{ prototype, item, recipe }
    end

    -- Add recipe to technology
    if data.raw.technology["spiderbots"] then
        table.insert(data.raw.technology["spiderbots"].effects, {
            type = "unlock-recipe",
            recipe = config.name,
        })
    end
end