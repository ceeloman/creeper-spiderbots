-- Creeperbots - Scouting State Handler
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local scouting_state = {}

function scouting_state.handle_scouting_state(creeper, event, position, entity, party, has_valid_path)
    -- Validate inputs
    if not entity or not entity.valid then
        --game.print("Error: Invalid entity for unit " .. (creeper.unit_number or "unknown"))
        return
    end
    if not party then
        --game.print("Error: Invalid party for unit " .. (creeper.unit_number or "unknown"))
        return
    end
    local surface = entity.surface
    if not surface or not surface.valid then
        --game.print("Error: Invalid surface for unit " .. (creeper.unit_number or "unknown"))
        return
    end
    --game.print("Debug: handle_scouting_state for unit " .. creeper.unit_number .. ", party: " .. (creeper.party_id or "none") .. ", surface: " .. surface.name)

    local members = {}
    local guards = {}
    local followers = {}
    for unit_number, member in pairs(storage.creeperbots or {}) do
        if member.party_id == creeper.party_id and member.entity and member.entity.valid then
            table.insert(members, member)
            if member.is_guard then
                table.insert(guards, member)
            elseif not member.is_leader then
                table.insert(followers, member)
            end
        end
    end
    --game.print("Debug: Party " .. creeper.party_id .. " - Members: " .. #members .. ", Guards: " .. #guards .. ", Followers: " .. #followers)

    local leader = storage.creeperbots[party.grouping_leader]
    if not leader or not leader.entity or not leader.entity.valid then
        local new_leader = nil
        for _, member in ipairs(members) do
            if member.entity and member.entity.valid then
                new_leader = member
                break
            end
        end
        if new_leader then
            new_leader.is_leader = true
            new_leader.is_guard = false
            update_color(new_leader.entity, "scouting")
            party.grouping_leader = new_leader.unit_number
            --game.print("Debug: New leader assigned - Unit " .. new_leader.unit_number)
        else
            --game.print("Error: No valid leader or members for party " .. creeper.party_id)
            return
        end
        leader = new_leader
    end

    if creeper.is_leader then
        local success, err = pcall(function()
            creeper.entity.follow_target = nil
        end)
        if not success then
            entity.autopilot_destination = nil
           -- game.print("Debug: Leader " .. creeper.unit_number .. " cleared autopilot_destination due to follow_target failure")
        else
            --game.print("Debug: Leader " .. creeper.unit_number .. " follow_target set to nil, has path: " .. (has_valid_path and "yes" or "no"))
        end
    elseif creeper.is_guard then
        local guard_index = nil
        for i, guard in ipairs(guards) do
            if guard.unit_number == creeper.unit_number then
                guard_index = i
                break
            end
        end
        if guard_index then
            --game.print("Debug: Guard " .. creeper.unit_number .. " found at guard_index: " .. guard_index)
            local current_follow_target = creeper.entity.follow_target
            --game.print("Debug: Guard " .. creeper.unit_number .. " current follow_target: " .. (current_follow_target and (current_follow_target.valid and "valid" or "invalid") or "none"))
            
            local success, err = pcall(function()
                creeper.entity.follow_target = leader.entity
                creeper.entity.follow_offset = nil
                --game.print("Debug: Guard " .. creeper.unit_number .. " setting follow_target to leader unit " .. party.grouping_leader)
            end)
            if not success then
                --game.print("Error: Guard " .. creeper.unit_number .. " failed to set follow_target to leader unit " .. party.grouping_leader .. ", error: " .. tostring(err))
            else
                entity.autopilot_destination = nil
               -- game.print("Debug: Guard " .. creeper.unit_number .. " follow_target successfully set to leader")
            end
        else
            --game.print("Error: Guard " .. creeper.unit_number .. " not found in guards list")
        end
    elseif creeper.state == "scouting" then
        party.follower_targets = party.follower_targets or {}
        local target_unit_number = party.follower_targets[creeper.unit_number]
        --game.print("Debug: Follower " .. creeper.unit_number .. " assigned to target unit: " .. (target_unit_number or "none"))
    
        -- Log all available follow targets (leader and guards)
        local available_targets = {}
        if leader and leader.entity and leader.entity.valid then
            table.insert(available_targets, {unit_number = party.grouping_leader, type = "leader"})
        end
        for _, guard in ipairs(guards) do
            if guard.entity and guard.entity.valid then
                table.insert(available_targets, {unit_number = guard.unit_number, type = "guard"})
            end
        end
        local target_list = #available_targets > 0 and table.concat(table.map(available_targets, function(t) return t.unit_number .. "(" .. t.type .. ")" end), ", ") or "none"
        --game.print("Debug: Follower " .. creeper.unit_number .. " available follow targets: " .. target_list)
    
        -- Determine follow target (leader or guard)
        local target = nil
        if target_unit_number and storage.creeperbots[target_unit_number] and storage.creeperbots[target_unit_number].entity and storage.creeperbots[target_unit_number].entity.valid then
            target = storage.creeperbots[target_unit_number]
            --game.print("Debug: Follower " .. creeper.unit_number .. " existing target unit: " .. target_unit_number .. ", type: " .. (target.is_leader and "leader" or "guard"))
        else
            -- Count followers per target to balance assignment
            local follower_counts = {}
            for _, t in ipairs(available_targets) do
                follower_counts[t.unit_number] = 0
            end
            for follower_unit, assigned_target in pairs(party.follower_targets) do
                if follower_unit ~= creeper.unit_number and storage.creeperbots[follower_unit] and storage.creeperbots[follower_unit].entity and storage.creeperbots[follower_unit].entity.valid then
                    if follower_counts[assigned_target] then
                        follower_counts[assigned_target] = follower_counts[assigned_target] + 1
                    end
                end
            end
    
            -- Assign to target with fewest followers, randomize if equal
            local min_followers = math.huge
            local candidates = {}
            for _, t in ipairs(available_targets) do
                if follower_counts[t.unit_number] < min_followers then
                    min_followers = follower_counts[t.unit_number]
                    candidates = {t}
                elseif follower_counts[t.unit_number] == min_followers then
                    table.insert(candidates, t)
                end
            end
    
            if #candidates > 0 then
                local random = game.create_random_generator()
                local selected_target = candidates[random(1, #candidates)]
                target = storage.creeperbots[selected_target.unit_number]
                target_unit_number = selected_target.unit_number
                party.follower_targets[creeper.unit_number] = target_unit_number
                --game.print("Debug: Follower " .. creeper.unit_number .. " assigned to " .. selected_target.type .. " unit: " .. target_unit_number .. " (followers: " .. (follower_counts[target_unit_number] + 1) .. ")")
            end
        end
    
        if target and target.entity and target.entity.valid then
            local current_follow_target = creeper.entity.follow_target
            --game.print("Debug: Follower " .. creeper.unit_number .. " current follow_target: " .. (current_follow_target and (current_follow_target.valid and "valid" or "invalid") or "none"))
    
            local success, err = pcall(function()
                creeper.entity.follow_target = target.entity
                creeper.entity.follow_offset = nil -- because the offset is not set it is not success to clears follow targets (but it claars teh storage of follow targets, not the actual follow targets fromthe factorio api)
                --game.print("Debug: Follower " .. creeper.unit_number .. " setting follow_target to unit " .. target_unit_number)
            end)
            if not success then
                --game.print("Error: Follower " .. creeper.unit_number .. " failed to set follow_target to unit " .. target_unit_number .. ", error: " .. tostring(err))
                --party.follower_targets[creeper.unit_number] = nil -- by commenting this out, the bots assign to the potential targets as intended so we dont need to cancle the follow if the offset is not there, thats a bit myuch
                --game.print("Debug: Follower " .. creeper.unit_number .. " cleared follower_targets due to follow_target failure")
            else
                --game.print("Debug: Follower " .. creeper.unit_number .. " follow_target successfully set to unit " .. target_unit_number)
            end
        else
            party.follower_targets[creeper.unit_number] = nil
            --game.print("Debug: Follower " .. creeper.unit_number .. " no valid target (leader or guard), cleared follower_targets")
        end
    end
end

return scouting_state

