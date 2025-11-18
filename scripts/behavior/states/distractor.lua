-- Creeperbots - Distractor State Handler
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local distractor_state = {}

function distractor_state.handle_distractor_state(creeper, event, position, entity, surface, tier, party)
    --game.print("Debug: Unit " .. creeper.unit_number .. " in distractor state")
    update_color(entity, "distractor")

    -- Store original party_id and leave party
    if creeper.party_id and not creeper.original_party_id then
        creeper.original_party_id = creeper.party_id
        local party = storage.parties[creeper.party_id]
        if party then
            party.members = party.members or {}
            party.members[creeper.unit_number] = nil
            --game.print("Debug: Distractor " .. creeper.unit_number .. " left party " .. creeper.party_id)
        end
        creeper.party_id = nil
    end

    -- Initialize distraction timing
    if not creeper.distract_start_tick or not creeper.distract_end_tick then
        creeper.distract_start_tick = event.tick
        creeper.distract_end_tick = event.tick + 600
        --game.print("Debug: Initialized distraction timing for distractor " .. creeper.unit_number .. ", start_tick: " .. creeper.distract_start_tick .. ", end_tick: " .. creeper.distract_end_tick)
    end

    -- Assign or validate target
    creeper.target = nil
    if not creeper.target or not creeper.target.valid then
        local spawners = surface.find_entities_filtered{
                            -- this fails on the second distractor, successful on the third and 4th, and 5th,
                            -- it seems the second distractor cant path to the thing because its half leaning over a lake
            type = "unit-spawner",
            position = position,
            radius = 150,
            force = "enemy"
        }
        for _, spawner in ipairs(spawners) do
            if spawner.valid and spawner.health > 0 then
                creeper.target = spawner
                creeper.target_position = spawner.position
                creeper.target_health = spawner.health

                --game.print("Debug: Distractor " .. creeper.unit_number .. " assigned target at (" .. spawner.position.x .. "," .. spawner.position.y .. ")")
                break
            end
        end
        if not creeper.target then
            if event.tick >= creeper.distract_start_tick + 300 then
                --game.print("Debug: No valid target for distractor " .. creeper.unit_number .. " after timeout, reverting to grouping")
                creeper.state = "grouping"
                creeper.target = nil
                creeper.target_position = nil
                creeper.target_health = nil
                creeper.diversion_position = nil
                update_color(entity, "grouping")
                if creeper.original_party_id and storage.parties[creeper.original_party_id] then
                    creeper.party_id = creeper.original_party_id
                    storage.parties[creeper.party_id].members = storage.parties[creeper.party_id].members or {}
                    storage.parties[creeper.party_id].members[creeper.unit_number] = creeper
                   -- game.print("Debug: Distractor " .. creeper.unit_number .. " rejoined party " .. creeper.party_id)
                end
                return
            end
            --game.print("Debug: No valid target for distractor " .. creeper.unit_number .. ", retrying")
            return
        end
    elseif not creeper.target.valid then
        --game.print("creeper target not valid")
    end

    -- Update target health
    creeper.target_health = creeper.target.health

    -- Check for nearby enemies to explode
    local enemies = surface.find_entities_filtered{
        position = position,
        radius = 15,
        force = "enemy",
        type = "unit"
    }
    local nearest_enemy = nil
    local nearest_distance = 15
    for _, enemy in pairs(enemies) do
        local distance = calculate_distance(position, enemy.position)
        if distance < nearest_distance then
            nearest_distance = distance
            nearest_enemy = enemy
        end
    end
    if nearest_enemy and nearest_distance <= 5 then
        creeper.state = "exploding"
        update_color(entity, "exploding")
        --game.print("Debug: Distractor " .. creeper.unit_number .. " transitioning to exploding near enemy at (" .. nearest_enemy.position.x .. "," .. nearest_enemy.position.y .. ")")
        return
    end

    -- End distraction phase and rejoin party
    if event.tick >= creeper.distract_end_tick then
        --game.print("Debug: Distractor " .. creeper.unit_number .. " ended distraction phase, reverting to grouping")
        creeper.state = "grouping"
        creeper.diversion_position = nil
        update_color(entity, "grouping")
        if creeper.original_party_id and storage.parties[creeper.original_party_id] then
            creeper.party_id = creeper.original_party_id
            storage.parties[creeper.party_id].members = storage.parties[creeper.party_id].members or {}
            storage.parties[creeper.party_id].members[creeper.unit_number] = creeper
            --game.print("Debug: Distractor " .. creeper.unit_number .. " rejoined party " .. creeper.party_id)
        end
        return
    end
end

return distractor_state

