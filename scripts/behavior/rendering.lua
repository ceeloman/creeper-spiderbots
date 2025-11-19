-- Creeperbots - Rendering module
-- Functions for managing rendering objects
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

function clear_renderings(creeper)
    if creeper.render_ids then
        --game.print("Clearing render_ids: " .. serpent.line(creeper.render_ids))
        for _, id in pairs(creeper.render_ids) do
            if type(id) == "number" then
                -- Try to get the render object first
                local render_obj = rendering.get_object_by_id(id)
                if render_obj and render_obj.valid then
                    render_obj.destroy()
                    --game.print("Cleared rendering ID: " .. tostring(id))
                else
                    --game.print("Skipping invalid rendering ID: " .. tostring(id))
                end
            else
                --game.print("Skipping non-numeric rendering ID: type=" .. type(id) .. ", value=" .. tostring(id))
            end
        end
        creeper.render_ids = nil
    end
    
    if creeper.dynamic_line_id then
        -- Handle userdata rendering object directly
        if type(creeper.dynamic_line_id) == "userdata" then
            -- If it's a render object with a valid field, check validity
            if creeper.dynamic_line_id.valid then
                creeper.dynamic_line_id.destroy()
                --game.print("Destroyed dynamic line render object directly")
            else
                --game.print("Invalid dynamic line render object")
            end
        -- Handle direct numeric ID
        elseif type(creeper.dynamic_line_id) == "number" then
            local render_obj = rendering.get_object_by_id(creeper.dynamic_line_id)
            if render_obj and render_obj.valid then
                render_obj.destroy()
                --game.print("Cleared dynamic line ID: " .. tostring(creeper.dynamic_line_id))
            else
                --game.print("Invalid dynamic line ID: " .. tostring(creeper.dynamic_line_id))
            end
        else
            --game.print("Dynamic line ID is not a number or userdata: " .. type(creeper.dynamic_line_id))
        end
        
        creeper.dynamic_line_id = nil
    end
    
    -- Clear debug text
    if creeper.debug_text_id then
        if type(creeper.debug_text_id) == "userdata" then
            -- It's a rendering object directly
            if creeper.debug_text_id.valid then
                creeper.debug_text_id.destroy()
            end
        elseif type(creeper.debug_text_id) == "number" then
            -- It's a numeric ID
            local debug_text = rendering.get_object_by_id(creeper.debug_text_id)
            if debug_text and debug_text.valid then
                debug_text.destroy()
            end
        end
        creeper.debug_text_id = nil
    end
end

local rendering_module = {}
rendering_module.clear_renderings = clear_renderings

return rendering_module
