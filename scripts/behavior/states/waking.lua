-- Creeperbots - Waking State Handler
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local waking_state = {}

function waking_state.handle_waking_state(creeper, event, position, entity, surface, tier)
    -- Set color for waking state
    update_color(entity, "waking")
    
    -- Initialize and schedule all movements
    if not creeper.waking_initialized then
        local random = game.create_random_generator()
        local rand = random(1, 100)
        local move_count = rand <= 50 and 2 or (rand <= 80 and 3 or 4)
        
        -- Generate random destinations
        local destinations = generate_random_destinations(
            position, 
            move_count + 1, -- Extra destination for after scan
            3, 
            6, 
            surface, 
            entity.name
        )
        
        
        -- Log and schedule all destinations
        local current_tick = event.tick
        local scan_at_move = move_count -- Which move to perform the scan after
        
        -- First movement has longer delay (1-3 seconds)
        local first_delay = random(30, 180)
        current_tick = current_tick + first_delay
        
        -- Before scheduling, make sure the bot has a queue in storage
        if not storage.autopilot_queue then
            storage.autopilot_queue = {}
        end
        
        -- Clear any existing queue for this bot
        storage.autopilot_queue[entity.unit_number] = {}
        
        -- Schedule all movements
        for i = 1, #destinations do
            local dest = destinations[i]
            local actual_distance = calculate_distance(position, dest)
            
            -- Determine if we should scan after reaching this destination
            local should_scan = (i == scan_at_move)
            
            -- Add this destination to the queue
            table.insert(storage.autopilot_queue[entity.unit_number], {
                destination = dest,
                tick = current_tick,
                should_scan = should_scan,
                sequence = i
            })
            
            -- Add random delay for next movement (0.5-2 seconds)
            if i < #destinations then
                current_tick = current_tick + random(30, 120)
            end
        end
        
        creeper.waking_initialized = true
    end
    
    -- No need to check for destination completion or schedule new ones
    -- All destinations are scheduled at initialization
end

return waking_state

