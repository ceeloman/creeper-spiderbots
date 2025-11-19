-- Creeperbots - Manager script
-- Manages Creeperbot instances, parties, and updates
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

-- Ensure utils are loaded (functions are global)
require "scripts.utils"

-- Check if an entity is a Creeperbot
function is_creeperbot(entity_name)
    return entity_name == "creeperbot-mk1" or
           entity_name == "creeperbot-mk2" or
           entity_name == "creeperbot-mk3-nuclear"
end

-- Register a new Creeperbot
function register_creeperbot(entity)
    if not storage.creeperbots then storage.creeperbots = {} end
    if not storage.parties then storage.parties = {} end

    --game.print("CreeperBot " .. entity.name .. " deployed and waking")

    -- Check if the bot is placed on or near water, and move it away if needed
    if entity.valid and entity.surface and entity.surface.valid then
        local position = entity.position
        -- Check a larger radius to catch bots placed very close to water
        local on_water = is_position_on_water(entity.surface, position, 2.5)
        if on_water then
            -- Find a safe position away from water
            local safe_position = find_safe_position_away_from_water(entity.surface, entity, position, 30)
            if safe_position then
                -- Store the safe position to move to after a short delay (next tick)
                -- This ensures the entity is fully initialized before we try to move it
                if not storage.pending_water_moves then
                    storage.pending_water_moves = {}
                end
                storage.pending_water_moves[entity.unit_number] = {
                    position = safe_position,
                    tick = game.tick + 1  -- Move on next tick
                }
                game.print("CreeperBot " .. entity.unit_number .. " detected near water, will move to (" .. string.format("%.1f", safe_position.x) .. ", " .. string.format("%.1f", safe_position.y) .. ")")
            else
                -- If we can't find a safe position, try teleport as fallback
                local fallback_pos = entity.surface.find_non_colliding_position("character", position, 30, 0.5)
                if fallback_pos and not is_position_on_water(entity.surface, fallback_pos, 2.5) then
                    entity.teleport(fallback_pos)
                    game.print("CreeperBot " .. entity.unit_number .. " teleported away from water (fallback)")
                end
            end
        end
    end

    -- Set entity label to unit number
    entity.entity_label = tostring(entity.unit_number)

    -- Create creeper table without party_id
    local creeper = {
        entity = entity,
        unit_number = entity.unit_number,
        state = "waking",
        tier = get_creeperbot_tier(entity.name)
    }

    -- Store as a map using unit_number
    storage.creeperbots[entity.unit_number] = creeper

    -- Trigger initial update for waking state
    update_creeperbot(creeper, {tick = game.tick})
end

-- Assign Creeperbot to a party
function assign_to_party(entity)
    local position = entity.position
    local surface = entity.surface
    local nearby_bots = surface.find_entities_filtered{
        position = position,
        radius = 50,
        name = {"creeperbot-mk1", "creeperbot-mk2", "creeperbot-mk3-nuclear"}
    }

    -- Find a leader in grouping state
    for _, bot in pairs(nearby_bots) do
        local bot_creeper = storage.creeperbots[bot.unit_number]
        if bot_creeper and bot_creeper.state == "grouping" and bot_creeper.is_leader then
            local party_id = bot_creeper.party_id
            storage.parties[party_id].members[entity.unit_number] = true
            --game.print("CreeperBot " .. entity.unit_number .. " assigned to party " .. party_id .. " with leader " .. bot.unit_number)
            return party_id
        end
    end

    -- Create a new party
    local party_id = #storage.parties + 1
    storage.parties[party_id] = {
        id = party_id,
        members = {[entity.unit_number] = true},
        shared_target = nil,
        visited_chunks = {},
        pending_path_requests = {}
    }
    --game.print("CreeperBot " .. entity.unit_number .. " created new party " .. party_id .. " (no leader found)")
    return party_id
end

-- Remove a Creeperbot
function remove_creeperbot(unit_number)
    if not storage.creeperbots then return end
    for i, creeper in pairs(storage.creeperbots) do
        if creeper.unit_number == unit_number then
            local party = storage.parties[creeper.party_id]
            if party and party.members then
                party.members[unit_number] = nil
                if not next(party.members) then
                    storage.parties[creeper.party_id] = nil
                end
            end
            table.remove(storage.creeperbots, i)
            break
        end
    end
end

-- Check if a party has pending path requests for a chunk
function has_pending_path_requests(party, chunk_x, chunk_y, creeper_unit_number)
    if not party.pending_path_requests then
        party.pending_path_requests = {}
    end
    
    local chunk_key = chunk_x .. "," .. chunk_y
    local requests = party.pending_path_requests[chunk_key] or {}
    return requests[creeper_unit_number] ~= nil
end

function mark_pending_path_requests(party, chunk_x, chunk_y, creeper_unit_number)
    if not party then
        --game.print("Debug: mark_pending_path_requests called with nil party, chunk: (" .. tostring(chunk_x) .. "," .. tostring(chunk_y) .. "), unit_number: " .. tostring(creeper_unit_number) .. ", tick: " .. game.tick)
        return
    end
    if not chunk_x or not chunk_y then
        --game.print("Debug: mark_pending_path_requests called with invalid chunk coordinates, chunk: (" .. tostring(chunk_x) .. "," .. tostring(chunk_y) .. "), unit_number: " .. tostring(creeper_unit_number) .. ", tick: " .. game.tick)
        return
    end
    if not creeper_unit_number then
        --game.print("Debug: mark_pending_path_requests called with nil creeper_unit_number, chunk: (" .. chunk_x .. "," .. chunk_y .. "), tick: " .. game.tick)
        return
    end
    
    party.pending_path_requests = party.pending_path_requests or {}
    local chunk_key = chunk_x .. "," .. chunk_y
    local requests = party.pending_path_requests[chunk_key] or {}
    requests[creeper_unit_number] = true
    party.pending_path_requests[chunk_key] = requests
    --game.print("Debug: Marked pending path request for unit " .. creeper_unit_number .. ", chunk: (" .. chunk_x .. "," .. chunk_y .. "), tick: " .. game.tick)
end

function clear_pending_path_requests(party, chunk_x, chunk_y, creeper_unit_number)
    if not party.pending_path_requests then
        party.pending_path_requests = {}
        return
    end
    
    local chunk_key = chunk_x .. "," .. chunk_y
    local requests = party.pending_path_requests[chunk_key]
    if requests then
        requests[creeper_unit_number] = nil
        if not next(requests) then
            party.pending_path_requests[chunk_key] = nil
        end
    end
end

-- Update all Creeperbots
function update_creeperbots(event)
    if not storage.creeperbots then storage.creeperbots = {} end
    local to_remove = {}
    for i, creeper in pairs(storage.creeperbots) do
        if not creeper.entity or not creeper.entity.valid then
            table.insert(to_remove, i)
        else
            update_creeperbot(creeper, event)
        end
    end

    for i = #to_remove, 1, -1 do
        remove_creeperbot(storage.creeperbots[to_remove[i]].unit_number)
    end
end