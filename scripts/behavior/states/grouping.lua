-- Creeperbots - Grouping State Handler
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local grouping_state = {}

function grouping_state.handle_grouping_state(creeper, event, position, entity, surface, tier, party)
    update_color(entity, creeper.is_guard and "guard" or "grouping")

    storage.parties = storage.parties or {}

    if not creeper.grouping_initialized then
        creeper.party_id = assign_to_party(entity)
        local party = storage.parties[creeper.party_id]
        if not party then
            local party_id = entity.unit_number .. "-" .. event.tick
            party = {
                members = {},
                grouping_leader = nil,
                grouping_start_tick = event.tick,
                last_join_tick = event.tick,
                state = "grouping",
                follower_targets = {},
                visited_chunks = {}
            }
            storage.parties[party_id] = party
            creeper.party_id = party_id
        end
        creeper.is_leader = not party.grouping_leader and true or false
        if creeper.is_leader then
            party.grouping_leader = entity.unit_number
            party.grouping_start_tick = event.tick
            party.last_join_tick = event.tick
        end
        creeper.grouping_initialized = true
        party.last_join_tick = event.tick
        --ame.print("Debug: Initialized party " .. creeper.party_id .. " for unit " .. creeper.unit_number .. ", leader: " .. tostring(creeper.is_leader))
    end

    party = storage.parties[creeper.party_id]
    if not party then
        creeper.grouping_initialized = false
        creeper.party_id = nil
        --game.print("Error: Party not found for unit " .. creeper.unit_number .. ", resetting grouping")
        return handle_grouping_state(creeper, event, position, entity, surface, tier, party)
    end

    local leader = storage.creeperbots[party.grouping_leader]
    local leader_pos = nil
    if leader and leader.entity and leader.entity.valid then
        leader_pos = leader.entity.position
    else
        creeper.is_leader = true
        creeper.is_guard = false
        update_color(entity, "grouping")
        party.grouping_leader = entity.unit_number
        party.grouping_start_tick = event.tick
        party.last_join_tick = event.tick
        leader_pos = entity.position
        --game.print("Debug: Leader invalid, unit " .. creeper.unit_number .. " became leader")
    end

    local members = {}
    local guards = {}
    for unit_number, member in pairs(storage.creeperbots or {}) do
        if member.party_id == creeper.party_id and member.entity and member.entity.valid then
            table.insert(members, member)
            if member.is_guard then
                table.insert(guards, member)
            end
        end
    end
    --game.print("Debug: Party " .. creeper.party_id .. " - Members: " .. #members .. ", Guards: " .. #guards .. ", Ticks elapsed: " .. (event.tick - (party.grouping_start_tick or event.tick)))

    if #members == 1 and creeper.is_leader then
        entity.autopilot_destination = nil
        --game.print("Debug: Leader " .. creeper.unit_number .. " alone, cleared autopilot_destination")
        return
    end

    local guard_count = 0
    if #members >= 6 then guard_count = 5
    elseif #members >= 5 then guard_count = 4
    elseif #members >= 4 then guard_count = 3
    elseif #members >= 3 then guard_count = 2
    elseif #members >= 2 then guard_count = 1
    end
    local current_guards = #guards

    if current_guards < guard_count then
        local candidates = {}
        for _, member in ipairs(members) do
            if member.state == "grouping" and not member.is_leader and not member.is_guard then
                table.insert(candidates, member)
            end
        end
        table.sort(candidates, function(a, b) return a.tier < b.tier end)
        
        for _, candidate in ipairs(candidates) do
            if current_guards < guard_count then
                candidate.is_guard = true
                update_color(candidate.entity, "guard")
                current_guards = current_guards + 1
                table.insert(guards, candidate)
                --game.print("Debug: Unit " .. candidate.unit_number .. " became guard")
            end
        end
        
        if current_guards > 0 then
            local new_members = {}
            for _, member in ipairs(members) do
                if member.state == "grouping" and not member.is_leader and not member.is_guard then
                    table.insert(new_members, member)
                end
            end
            table.sort(new_members, function(a, b) return a.tier < b.tier end)
            
            for _, new_member in ipairs(new_members) do
                for i = #guards, 1, -1 do
                    local guard = guards[i]
                    if guard.tier > new_member.tier then
                        guard.is_guard = false
                        update_color(guard.entity, "grouping")
                        new_member.is_guard = true
                        update_color(new_member.entity, "guard")
                        guards[i] = new_member
                        --game.print("Debug: Swapped guard " .. guard.unit_number .. " with " .. new_member.unit_number)
                        break
                    end
                end
            end
        end
    end

    local guard_positions = {}
    local guard_count = #guards
    if guard_count == 1 then
        guard_positions = {{angle = 180, radius = 3}}
    elseif guard_count == 2 then
        guard_positions = {{angle = 90, radius = 4}, {angle = 270, radius = 4}}
    elseif guard_count == 3 then
        guard_positions = {{angle = 120, radius = 5}, {angle = 240, radius = 5}, {angle = 0, radius = 5}}
    elseif guard_count == 4 then
        guard_positions = {{angle = 45, radius = 6}, {angle = 135, radius = 6}, {angle = 225, radius = 6}, {angle = 315, radius = 6}}
    elseif guard_count >= 5 then
        guard_positions = {{angle = 0, radius = 8}, {angle = 72, radius = 8}, {angle = 144, radius = 8}, {angle = 216, radius = 8}, {angle = 288, radius = 8}}
    end

    if current_guards > 0 and current_guards <= guard_count then
        for i, guard in ipairs(guards) do
            if guard.entity and guard.entity.valid then
                local pos = guard_positions[i] or {angle = 180, radius = 3}
                local dest_pos = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                }
                local dist_to_current = math.sqrt((dest_pos.x - guard.entity.position.x)^2 + (dest_pos.y - guard.entity.position.y)^2)
                if dist_to_current >= 3 and (not guard.last_path_request or event.tick >= guard.last_path_request + 60) then
                    schedule_autopilot_destination(guard, {dest_pos}, event.tick + 30, false)
                    guard.last_path_request = event.tick
                    --game.print("Debug: Guard " .. guard.unit_number .. " scheduled autopilot to (" .. dest_pos.x .. "," .. dest_pos.y .. ")")
                end
            end
        end
    end

    if event.tick % 60 == 0 then
        for _, guard in ipairs(guards) do
            if guard.entity and guard.entity.valid then
                local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[guard.unit_number]
                if not queue and #guard.entity.autopilot_destinations > 0 then
                    guard.entity.autopilot_destination = nil
                   -- game.print("Debug: Guard " .. guard.unit_number .. " cleared autopilot_destination")
                end
            end
        end
    end

    if event.tick % 60 == 0 and guard_count > 0 then
        local random = game.create_random_generator()
        local out_of_position = nil
        local out_of_position_index = nil
        
        for i, guard in ipairs(guards) do
            if guard.entity and guard.entity.valid then
                local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[guard.unit_number]
                if not queue and #guard.entity.autopilot_destinations == 0 then
                    local pos = guard_positions[i] or {angle = 180, radius = 3}
                    local dest_pos = {
                        x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                        y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                    }
                    local dist_to_dest = math.sqrt((dest_pos.x - guard.entity.position.x)^2 + (dest_pos.y - guard.entity.position.y)^2)
                    if dist_to_dest > 3 then
                        out_of_position = guard
                        out_of_position_index = i
                        break
                    end
                end
            end
        end
        
        if out_of_position then
            local stationary_guards = {}
            for i, guard in ipairs(guards) do
                if guard.entity and guard.entity.valid and i ~= out_of_position_index then
                    local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[guard.unit_number]
                    if not queue and #guard.entity.autopilot_destinations == 0 then
                        table.insert(stationary_guards, {guard = guard, index = i})
                    end
                end
            end
            
            if #stationary_guards > 0 then
                local swap = stationary_guards[random(1, #stationary_guards)]
                local swap_guard = swap.guard
                local swap_index = swap.index
                
                guards[out_of_position_index], guards[swap_index] = swap_guard, out_of_position
                
                local pos1 = guard_positions[out_of_position_index] or {angle = 180, radius = 3}
                local dest_pos1 = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos1.angle)) * pos1.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos1.angle)) * pos1.radius)
                }
                local pos2 = guard_positions[swap_index] or {angle = 180, radius = 3}
                local dest_pos2 = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos2.angle)) * pos2.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos2.angle)) * pos2.radius)
                }
                
                local dist1 = math.sqrt((dest_pos1.x - swap_guard.entity.position.x)^2 + (dest_pos1.y - swap_guard.entity.position.y)^2)
                if dist1 >= 3 then
                    schedule_autopilot_destination(swap_guard, {dest_pos1}, event.tick + 30, false)
                    swap_guard.last_path_request = event.tick
                    --game.print("Debug: Swapped guard " .. swap_guard.unit_number .. " to (" .. dest_pos1.x .. "," .. dest_pos1.y .. ")")
                end
                
                local dist2 = math.sqrt((dest_pos2.x - out_of_position.entity.position.x)^2 + (dest_pos2.y - out_of_position.entity.position.y)^2)
                if dist2 >= 3 then
                    schedule_autopilot_destination(out_of_position, {dest_pos2}, event.tick + 30, false)
                    out_of_position.last_path_request = event.tick
                    --game.print("Debug: Swapped guard " .. out_of_position.unit_number .. " to (" .. dest_pos2.x .. "," .. dest_pos2.y .. ")")
                end
            end
        end
    end

    local random = game.create_random_generator()
    for _, member in ipairs(members) do
        if member.state == "grouping" and not member.is_leader and not member.is_guard and member.entity and member.entity.valid then
            local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[member.unit_number]
            if not queue and #member.entity.autopilot_destinations == 0 and random() <= 0.3 then
                local destinations = generate_random_destinations(
                    leader_pos,
                    1,
                    3,
                    5,
                    surface,
                    member.entity.name,
                    member.entity.position,
                    member.unit_number,
                    event.tick
                )
                if #destinations > 0 then
                    schedule_autopilot_destination(member, {destinations[1]}, event.tick + 30, false)
                    --game.print("Debug: Follower " .. member.unit_number .. " scheduled random destination (" .. destinations[1].x .. "," .. destinations[1].y .. ")")
                end
            end
        end
    end

    if not party.started_scouting and party.grouping_start_tick and event.tick >= party.grouping_start_tick + 1200 and #members >= 3 then
        party.started_scouting = true
        party.state = "scouting"
        party.follower_targets = party.follower_targets or {}
    
        for _, member in ipairs(members) do
            if member.entity and member.entity.valid then
                member.state = member.is_guard and "guard" or "scouting"
                update_color(member.entity, member.state)
                --game.print("Debug: Unit " .. member.unit_number .. " transitioned to state " .. member.state)
            end
        end
    
        if creeper.is_leader then
            entity.autopilot_destination = nil
            local target_pos = get_unvisited_chunk(entity.position, party)
            if target_pos.x ~= entity.position.x or target_pos.y ~= entity.position.y then
                request_multiple_paths(entity.position, target_pos, party, surface, creeper.unit_number)
                --game.print("Debug: Leader " .. creeper.unit_number .. " set path to (" .. target_pos.x .. "," .. target_pos.y .. ")")
            else
                --game.print("Error: Leader " .. creeper.unit_number .. " no valid chunk found")
            end
        end
    end
    
end

return grouping_state

