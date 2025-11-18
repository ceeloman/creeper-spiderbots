-- utils.lua
-- Calculate distance between two positions
function calculate_distance(pos1, pos2)
    return ((pos1.x - pos2.x)^2 + (pos1.y - pos2.y)^2)^0.5
end
  
  -- Get chunk position from tile position
function get_chunk_pos(position)
    return {
        x = math.floor(position.x / 32),
        y = math.floor(position.y / 32),
    }
end

function update_color(entity, state)
    if state == "waking" then
        entity.color = {r = 1, g = 1, b = 1} -- White
    elseif state == "grouping" then
        entity.color = {r = 0.5, g = 0.5, b = 0.5} -- Grey
    elseif state == "scouting" then
        entity.color = {r = 0, g = 1, b = 0} -- Green
    elseif state == "approaching" then
        entity.color = {r = 1, g = 0, b = 0} -- Red
    elseif state == "attacking" then
        entity.color = {r = 1, g = 0.5, b = 0} -- Orange-red
    elseif state == "retreating" then
        entity.color = {r = 0, g = 0, b = 1} -- Blue
        --game.print("CreeperBot " .. entity.unit_number .. " retreating")
    elseif state == "guard" then
        entity.color = {r = 1, g = 1, b = 0} -- Yellow
    elseif state == "preparing_to_attack" then
        entity.color = {r = 1, g = 0, b = 0} -- Orange-red
    elseif state == "distractor" then
        entity.color = {r = 0, g = 0, b = 0} -- Yellow
    elseif state == "exploding" then
        entity.color = {r = 0.3, g = 0.5, b = 0.7} -- Cyan
    else
        entity.color = {r = 0.7, g = 0.7, b = 0.7} -- Default
    end
end

function generate_random_destinations(origin, count, min_distance, max_distance, surface, entity_name, current_position, unit_number, tick)
    local destinations = {}
    local current_pos = current_position or {x = origin.x, y = origin.y}
    
    -- Validate inputs
    if not surface or type(surface) ~= "userdata" or not surface.valid then
        --game.print("Error: Invalid surface for CreeperBot " .. tostring(unit_number or "unknown") .. " in generate_random_destinations")
        return destinations
    end
    if not entity_name then
        --game.print("Error: Invalid entity_name for CreeperBot " .. tostring(unit_number or "unknown") .. " in generate_random_destinations")
        return destinations
    end
    
    -- Unique seed
    local seed = tick or game.tick
    if unit_number then
        seed = unit_number * seed
    end
    local random = game.create_random_generator(seed)
    
    for i = 1, count do
        local attempts = 0
        local max_attempts = 5
        local dest = nil
        
        while attempts < max_attempts do
            local angle = random(0, 360)
            local distance = min_distance + (random(0, 1000) / 1000.0) * (max_distance - min_distance)
            dest = {
                x = math.floor(origin.x + math.cos(math.rad(angle)) * distance),
                y = math.floor(origin.y + math.sin(math.rad(angle)) * distance)
            }
            
            local dist_to_current = math.sqrt((dest.x - current_pos.x)^2 + (dest.y - current_pos.y)^2)
            if dist_to_current >= 3 then
                break
            end
            attempts = attempts + 1
            dest = nil
        end
        
        if not dest then
            local angle = random(0, 360)
            dest = {
                x = math.floor(origin.x + math.cos(math.rad(angle)) * min_distance),
                y = math.floor(origin.y + math.sin(math.rad(angle)) * min_distance)
            }
        end
        
        -- Use find_non_colliding_position with fallback
        local valid_dest = dest
        if surface.find_non_colliding_position then
            valid_dest = surface.find_non_colliding_position(
                entity_name,
                dest,
                2,    -- radius
                0.5   -- precision
            ) or dest
        else
            -- Fallback: Check walkable tiles
            local tiles = surface.find_tiles_filtered{
                position = dest,
                radius = 1,
                collision_mask = {"water-tile", "colliding-with-tiles-only"}
            }
            if #tiles == 0 then
                --game.print("CreeperBot " .. tostring(unit_number or "unknown") .. ": Fallback - Position (" .. dest.x .. "," .. dest.y .. ") is not walkable, using raw dest")
            end
        end
        
        valid_dest.x = math.floor(valid_dest.x)
        valid_dest.y = math.floor(valid_dest.y)
        --game.print("Generated destination for " .. (unit_number or "unknown") .. ": (" .. valid_dest.x .. "," .. valid_dest.y .. "), distance from current=" .. math.sqrt((valid_dest.x - current_pos.x)^2 + (valid_dest.y - current_pos.y)^2))
        table.insert(destinations, valid_dest)
    end
    
    return destinations
end

-- Store scheduled autopilot destinations in storage
function schedule_autopilot_destination(creeper, destination, tick, should_scan)
    local entity = creeper.entity
    local unit_number = entity.unit_number
    
    if not storage.scheduled_autopilots then
        storage.scheduled_autopilots = {}
    end
    
    storage.scheduled_autopilots[unit_number] = {
        destination = destination,
        tick = tick,
        should_scan = should_scan or false
    }
    
    --game.print("CreeperBot " .. unit_number .. " scheduled to move at tick " .. tick .. ", current tick is " .. game.tick)
end

function table.map(tbl, func)
    local result = {}
    for _, v in ipairs(tbl) do
        table.insert(result, func(v))
    end
    return result
end

-- Function to process scheduled destinations (call this every tick or on_nth_tick)
function process_autopilot_queue(event)
    if not storage.autopilot_queue then return end
    
    for unit_number, queue in pairs(storage.autopilot_queue) do
        local creeper = storage.creeperbots[unit_number]
        if not (creeper and creeper.entity and creeper.entity.valid) then
            -- Bot no longer exists, clear its queue
            storage.autopilot_queue[unit_number] = nil
        else
            -- Get the next destination in the queue
            local next_dest = nil
            local next_index = nil
            
            for i, data in ipairs(queue) do
                if event.tick >= data.tick then
                    next_dest = data
                    next_index = i
                    break
                end
            end
            
            -- Process the next destination if found
            if next_dest then
                -- If bot has a current destination, don't override it yet
                if not creeper.entity.autopilot_destination then
                    -- Apply the autopilot destination
                    --game.print("CreeperBot " .. unit_number .. " scheduled")
                    creeper.entity.add_autopilot_destination(next_dest.destination)
                    
                    -- Handle enemy scanning if requested
                    if next_dest.should_scan then
                        local position = creeper.entity.position
                        local surface = creeper.entity.surface
                        local max_targeting = tier_configs[creeper.entity.name] and tier_configs[creeper.entity.name].max_targeting or 3
                        --game.print("Debug: Scanning for enemies, unit_number: " .. unit_number .. ", entity.name: " .. tostring(creeper.entity.name) .. ", max_targeting: " .. max_targeting)
                        local target = scan_for_enemies(position, surface, max_targeting, creeper.state == "waking")
                        
                        if target then
                            --game.print("CreeperBot " .. unit_number .. " detected enemy, switching to approaching")
                            -- State transition removed - to be reimplemented
                            -- creeper.state = "approaching"
                            creeper.target = target
                            storage.parties[creeper.party_id].shared_target = target
                            creeper.entity.color = {r = 1, g = 0, b = 0}
                            clear_renderings(creeper)
                            creeper.entity.autopilot_destination = nil
                            
                            local chunk_pos = get_chunk_pos(target.position)
                            if not has_pending_path_requests(storage.parties[creeper.party_id], chunk_pos.x, chunk_pos.y) then
                                mark_pending_path_requests(storage.parties[creeper.party_id], chunk_pos.x, chunk_pos.y)
                                request_multiple_paths(position, target.position, storage.parties[creeper.party_id], surface, unit_number)
                            end
                            
                            -- Cancel any existing queue for this bot
                            storage.autopilot_queue[unit_number] = nil
                            
                            -- Add new destination toward enemy
                            creeper.entity.add_autopilot_destination(target.position)
                            
                            -- Clean up waking state
                            if creeper.waking_initialized then
                                creeper.waking_initialized = nil
                            end
                            return
                        else
                            --game.print("CreeperBot " .. unit_number .. " scanned, no enemies found")
                        end
                    end
                    
                    -- Remove this destination from the queue
                    table.remove(queue, next_index)
                    
                    -- If the queue is now empty and we've completed the last move without finding enemies
                    if #queue == 0 and creeper.state == "waking" then
                        --game.print("CreeperBot " .. unit_number .. " completed waking, switching to grouping")
                        creeper.state = "grouping"
                        creeper.entity.color = {r = 0.5, g = 0.5, b = 0.5}
                        
                        -- Clean up waking state
                        if creeper.waking_initialized then
                            creeper.waking_initialized = nil
                        end
                    end
                end
            end
        end
    end
end

-- Helper function to cancel all scheduled autopilot movements for a bot
function cancel_scheduled_autopilots(unit_number)
    if storage.scheduled_autopilots and storage.scheduled_autopilots[unit_number] then
        storage.scheduled_autopilots[unit_number] = nil
    end
end

-- Clean up waking state data
function cleanup_waking_state(creeper)
    creeper.waking_initialized = nil
    creeper.waking_destinations = nil
    creeper.waking_current_move = nil
    creeper.waking_scanned = nil
    creeper.waking_spawn_pos = nil
    creeper.waking_final_move = nil
    creeper.waking_delay_until = nil
    creeper.waking_timeout = nil
    creeper.waking_initial_delay = nil
end
  
  -- Get a random position in a chunk
function get_position_in_chunk(chunk_x, chunk_y)
    local surface = game.surfaces[1]
    local chunk_pos = {x = chunk_x, y = chunk_y}
    if not surface.is_chunk_generated(chunk_pos) then
        return {x = (chunk_x * 32) + 16, y = (chunk_y * 32) + 16}
    end
    for _ = 1, 10 do
        local pos = {
            x = (chunk_x * 32) + math.random(0, 31),
            y = (chunk_y * 32) + math.random(0, 31),
        }
        local tile = surface.get_tile(pos.x, pos.y)
        local tile_name = tile.name:lower()
        if not (tile_name:find("water") or tile_name:find("lava") or tile_name:find("lake") or tile_name:find("ammoniacal")) then
            return pos
        end
    end
    return {x = (chunk_x * 32) + 16, y = (chunk_y * 32) + 16}
end
  
function request_multiple_paths(position, target_pos, party, surface, creeper_unit_number)
    --game.print("Debug: request_multiple_paths for unit " .. (creeper_unit_number or "unknown") .. ", target: (" .. (target_pos and target_pos.x or "nil") .. "," .. (target_pos and target_pos.y or "nil") .. "), party: " .. (party and "valid" or "nil"))

    -- Validate inputs
    if not position or not position.x or not position.y then
        --game.print("Error: Invalid position for unit " .. (creeper_unit_number or "unknown"))
        return false
    end
    if not target_pos or not target_pos.x or not target_pos.y then
        --game.print("Error: Invalid target_pos for unit " .. (creeper_unit_number or "unknown"))
        return false
    end
    if not surface or not surface.valid then
        --game.print("Error: Invalid surface for unit " .. (creeper_unit_number or "unknown"))
        return false
    end

    local path_collision_mask = {
        layers = {
            water_tile = true,
            cliff = true
        },
        colliding_with_tiles_only = true,
        consider_tile_transitions = true
    }

    local start_offsets = {
        {x = 0, y = 0},
        --[[
        {x = 0, y = 4},
        {x = 4, y = 0},
        {x = -4, y = 0},
        {x = 0, y = -4},
        ]]
    }

    storage.path_requests = storage.path_requests or {}
    for i, offset in ipairs(start_offsets) do
        local start_pos = {x = position.x + offset.x, y = position.y + offset.y}
        local chunk_x = math.floor(target_pos.x / 32)
        local chunk_y = math.floor(target_pos.y / 32)
        
        -- Validate chunk
        if not surface.is_chunk_generated({x = chunk_x, y = chunk_y}) then
            --game.print("Debug: Target chunk not generated for unit " .. (creeper_unit_number or "unknown") .. " at (" .. target_pos.x .. "," .. target_pos.y .. ")")
            return false
        end

        local request_id = surface.request_path{
            start = start_pos,
            goal = target_pos,
            force = "player",
            bounding_box = {{-0.5, -0.5}, {0.5, 0.5}},
            collision_mask = path_collision_mask,
            radius = 20,
            path_resolution_modifier = -3,
            pathfind_flags = {
                cache = false,
                prefer_straight_paths = false,
                low_priority = false
            }
        }

        if request_id then
            local request_data = {
                chunk_x = chunk_x,
                chunk_y = chunk_y,
                target_pos = target_pos,
                resolution = -3,
                start_offset_index = i,
                total_requests = #start_offsets,
                creeper_unit_number = creeper_unit_number
            }
            if party and party.visited_chunks and party.id then
                request_data.visits = party.visited_chunks[chunk_x .. "," .. chunk_y] or 0
                request_data.party_id = party.id
            else
                request_data.visits = 0
                request_data.party_id = "distractor_" .. (creeper_unit_number or "unknown")
            end
            storage.path_requests[request_id] = request_data
            --game.print("Debug: Path requested for unit " .. (creeper_unit_number or "unknown") .. " to (" .. target_pos.x .. "," .. target_pos.y .. "), request_id: " .. request_id)
            return true
        else
            --game.print("Debug: Path request failed for unit " .. (creeper_unit_number or "unknown") .. " to (" .. target_pos.x .. "," .. target_pos.y .. ")")
        end
    end
    return false
end
  
function get_unvisited_chunk(position, party)
    local surface = game.surfaces[1]
    local chunk_pos = get_chunk_pos(position)
    party.visited_chunks = party.visited_chunks or {}

    local search_radius = 10 -- Increased from 5
    local valid_chunks = {}

    for dx = -search_radius, search_radius do
        for dy = -search_radius, search_radius do
            local cx, cy = chunk_pos.x + dx, chunk_pos.y + dy
            local chunk_key = cx .. "," .. cy
            local visit_count = party.visited_chunks[chunk_key] or 0
            if surface.is_chunk_generated({x = cx, y = cy}) then
                local test_pos = {x = (cx * 32) + 16, y = (cy * 32) + 16}
                local tile = surface.get_tile(test_pos.x, test_pos.y)
                local tile_name = tile.name:lower()
                
                if not (tile_name:find("water") or tile_name:find("lava") or tile_name:find("lake") or tile_name:find("ammoniacal")) then
                    local valid_pos = surface.find_non_colliding_position("character", test_pos, 10, 2)
                    if valid_pos then
                        local dist = math.sqrt((valid_pos.x - position.x)^2 + (valid_pos.y - position.y)^2)
                        if dist >= 50 then -- Minimum distance 50 tiles
                            table.insert(valid_chunks, {
                                x = cx,
                                y = cy,
                                pos = valid_pos,
                                visits = visit_count
                            })
                        end
                    end
                end
            end
        end
    end

    table.sort(valid_chunks, function(a, b) return a.visits < b.visits end)

    if #valid_chunks > 0 then
        local chunk = valid_chunks[1]
        --request_multiple_paths(position, chunk.pos, party, surface, party.grouping_leader)
        return chunk.pos
    end

    return {x = position.x, y = position.y}
end