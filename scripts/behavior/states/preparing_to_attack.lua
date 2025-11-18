-- Creeperbots - Preparing to Attack State Handler
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local config = require "scripts.behavior.config"
local behavior_utils = require "scripts.behavior.utils"
local distractor_state_module = require "scripts.behavior.states.distractor"

local preparing_to_attack_state = {}

function preparing_to_attack_state.handle_preparing_to_attack_state(creeper, event, position, entity, surface, tier, party)
    update_color(entity, "preparing_to_attack")
    --game.print("Debug: Unit " .. creeper.unit_number .. " in preparing_to_attack state, tick: " .. event.tick)

    if not party then
        --game.print("Error: Party not found for unit " .. creeper.unit_number .. ", reverting to grouping, tick: " .. event.tick)
        creeper.state = "grouping"
        update_color(entity, "grouping")
        return
    end

    local leader = storage.creeperbots[party.grouping_leader]
    local leader_pos = nil
    if leader and leader.entity and leader.entity.valid then
        leader_pos = leader.entity.position
    else
        creeper.is_leader = true
        party.grouping_leader = creeper.unit_number
        leader_pos = entity.position
        --game.print("Debug: Unit " .. creeper.unit_number .. " became leader due to invalid leader, tick: " .. event.tick)
    end

    if creeper.is_leader then
        entity.autopilot_destination = nil
        if storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] then
            storage.scheduled_autopilots[entity.unit_number] = nil
            --game.print("Debug: Cleared scheduled autopilot for leader " .. creeper.unit_number .. ", tick: " .. event.tick)
        end
    end

    local members = {}
    local distractors = {}
    for unit_number, member in pairs(storage.creeperbots or {}) do
        if member.party_id == creeper.party_id and member.entity and member.entity.valid then
            table.insert(members, member)
            if member.is_distractor then
                table.insert(distractors, member)
                --game.print("Debug: Unit " .. member.unit_number .. " added as distractor for party " .. creeper.party_id .. ", tick: " .. event.tick)
            end
        end
    end
    --game.print("Debug: Party " .. creeper.party_id .. " - Members: " .. #members .. ", Distractors: " .. #distractors .. ", tick: " .. event.tick)

    if #members == 1 and creeper.is_leader then
        entity.autopilot_destination = nil
        --game.print("Debug: Leader " .. creeper.unit_number .. " alone, cleared autopilot_destination, tick: " .. event.tick)
        return
    end

    -- Determine distractor count
    local distractor_count = 0
    if #members >= 6 then distractor_count = 5
    elseif #members >= 5 then distractor_count = 4
    elseif #members >= 4 then distractor_count = 3
    elseif #members >= 3 then distractor_count = 2
    elseif #members >= 2 then distractor_count = 1
    end
    local current_distractors = #distractors

    -- Assign new distractors if needed
    if current_distractors < distractor_count then
        local candidates = {}
        for _, member in ipairs(members) do
            if member.state == "preparing_to_attack" and not member.is_leader and not member.is_distractor then
                table.insert(candidates, member)
            end
        end
        table.sort(candidates, function(a, b) return a.tier < b.tier end)

        for _, candidate in ipairs(candidates) do
            if current_distractors < distractor_count then
                candidate.is_distractor = true
                update_color(candidate.entity, "distractor")
                current_distractors = current_distractors + 1
                table.insert(distractors, candidate)
                --game.print("Debug: Unit " .. candidate.unit_number .. " became distractor, tick: " .. event.tick)
            end
        end

        if current_distractors > 0 then
            local new_members = {}
            for _, member in ipairs(members) do
                if member.state == "preparing_to_attack" and not member.is_leader and not member.is_distractor then
                    table.insert(new_members, member)
                end
            end
            table.sort(new_members, function(a, b) return a.tier < b.tier end)

            for _, new_member in ipairs(new_members) do
                for i = #distractors, 1, -1 do
                    local distractor = distractors[i]
                    if distractor.distract_start_tick and distractor.distract_end_tick and event.tick < distractor.distract_end_tick then
                        --game.print("Debug: Skipping distractor swap for unit " .. distractor.unit_number .. " during distraction phase, tick: " .. event.tick)
                    elseif distractor.tier > new_member.tier then
                        distractor.is_distractor = false
                        update_color(distractor.entity, "preparing_to_attack")
                        new_member.is_distractor = true
                        new_member.distract_start_tick = event.tick
                        new_member.distract_end_tick = event.tick + 600
                        update_color(new_member.entity, "distractor")
                        distractors[i] = new_member
                        --game.print("Debug: Swapped distractor " .. distractor.unit_number .. " with " .. new_member.unit_number .. ", new distractor initialized with start_tick: " .. new_member.distract_start_tick .. ", end_tick: " .. new_member.distract_end_tick .. ", tick: " .. event.tick)
                        break
                    end
                end
            end
        end
    end

    -- Assign distractor positions
    local distractor_positions = {}
    local distractor_total = #distractors
    if distractor_total == 1 then
        distractor_positions = {{angle = 180, radius = 3}}
    elseif distractor_total == 2 then
        distractor_positions = {{angle = 90, radius = 4}, {angle = 270, radius = 4}}
    elseif distractor_total == 3 then
        distractor_positions = {{angle = 120, radius = 5}, {angle = 240, radius = 5}, {angle = 0, radius = 5}}
    elseif distractor_total == 4 then
        distractor_positions = {{angle = 45, radius = 6}, {angle = 135, radius = 6}, {angle = 225, radius = 6}, {angle = 315, radius = 6}}
    elseif distractor_total >= 5 then
        distractor_positions = {{angle = 0, radius = 8}, {angle = 72, radius = 8}, {angle = 144, radius = 8}, {angle = 216, radius = 8}, {angle = 288, radius = 8}}
    end

    -- Distractor positioning
    if current_distractors > 0 and current_distractors <= distractor_count then
        for i, distractor in ipairs(distractors) do
            if distractor.entity and distractor.entity.valid and distractor.state == "preparing_to_attack" then
                local pos = distractor_positions[i] or {angle = 180, radius = 3}
                local dest_pos = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                }
                local dist_to_current = calculate_distance(distractor.entity.position, dest_pos)
                if dist_to_current >= 3 then
                    schedule_autopilot_destination(distractor, {dest_pos}, event.tick + 30, false)
                    --game.print("Debug: Distractor " .. distractor.unit_number .. " scheduled autopilot to (" .. dest_pos.x .. "," .. dest_pos.y .. "), tick: " .. event.tick)
                end
            end
        end
    end

    -- Clear conflicting waypoints every 60 ticks
    if event.tick % 60 == 0 then
        for _, distractor in ipairs(distractors) do
            if distractor.entity and distractor.entity.valid then
                local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[distractor.unit_number]
                if not queue and #distractor.entity.autopilot_destinations > 0 then
                    distractor.entity.autopilot_destination = nil
                    --game.print("Debug: Distractor " .. distractor.unit_number .. " cleared autopilot_destination")
                end
            end
        end
    end

    if event.tick % 60 == 0 and distractor_count > 0 then
        local random = game.create_random_generator()
        local out_of_position = nil
        local out_of_position_index = nil

        for i, distractor in ipairs(distractors) do
            if distractor.entity and distractor.entity.valid then
                local pos = distractor_positions[i] or {angle = 180, radius = 3}
                local dest_pos = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                }
                local dist_to_dest = calculate_distance(distractor.entity.position, dest_pos)
                if dist_to_dest > 3 then
                    out_of_position = distractor
                    out_of_position_index = i
                    break
                end
            end
        end

        if out_of_position then
            local stationary_distractors = {}
            for i, distractor in ipairs(distractors) do
                if distractor.entity and distractor.entity.valid and i ~= out_of_position_index then
                    if #distractor.entity.autopilot_destinations == 0 then
                        table.insert(stationary_distractors, {distractor = distractor, index = i})
                    end
                end
            end

            if #stationary_distractors > 0 then
                local swap = stationary_distractors[random(1, #stationary_distractors)]
                local swap_distractor = swap.distractor
                local swap_index = swap.index

                distractors[out_of_position_index], distractors[swap_index] = swap_distractor, out_of_position

                local pos1 = distractor_positions[out_of_position_index] or {angle = 180, radius = 3}
                local dest_pos1 = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos1.angle)) * pos1.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos1.angle)) * pos1.radius)
                }
                local pos2 = distractor_positions[swap_index] or {angle = 180, radius = 3}
                local dest_pos2 = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos2.angle)) * pos2.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos2.angle)) * pos2.radius)
                }
                local dist1 = calculate_distance(swap_distractor.entity.position, dest_pos1)
                if dist1 >= 3 then
                    schedule_autopilot_destination(swap_distractor, {dest_pos1}, event.tick + 30, false)
                    swap_distractor.last_path_request = event.tick
                    --game.print("Debug: Swapped distractor " .. swap_distractor.unit_number .. " path request " .. (path_success and "succeeded" or "failed") .. " to (" .. dest_pos1.x .. "," .. dest_pos1.y .. "), tick: " .. event.tick)
                end

                local dist2 = calculate_distance(out_of_position.entity.position, dest_pos2)
                if dist2 >= 3 then
                    schedule_autopilot_destination(out_of_position, {dest_pos2}, event.tick + 30, false)
                    out_of_position.last_path_request = event.tick
                    --game.print("Debug: Swapped distractor " .. out_of_position.unit_number .. " path request " .. (path_success and "succeeded" or "failed") .. " to (" .. dest_pos2.x .. "," .. dest_pos2.y .. "), tick: " .. event.tick)
                end
            end
        end
    end

    -- Non-distractor followers move to leader
    if not party.attack_initiated and not creeper.is_leader and not creeper.is_distractor then
        -- Log leader details
        local leader = storage.creeperbots[party.grouping_leader]
        if leader and leader.entity and leader.entity.valid then
            --game.print("Debug: Leader unit_number: " .. party.grouping_leader .. ", position: (" .. leader_pos.x .. "," .. leader_pos.y .. "), tick: " .. event.tick)
        else
            --game.print("Debug: Invalid leader for party " .. creeper.party_id .. ", unit_number: " .. party.grouping_leader .. ", tick: " .. event.tick)
        end
    
        -- Log follower follow_target before clearing
        --game.print("Debug: Follower " .. creeper.unit_number .. " follow_target before clear: " .. (creeper.follow_target and creeper.follow_target.unit_number or "none") .. ", tick: " .. event.tick)
        
        creeper.follow_target = nil
        
        -- Log follower follow_target after clearing
        --game.print("Debug: Follower " .. creeper.unit_number .. " follow_target after clear: " .. (creeper.follow_target and creeper.follow_target.unit_number or "none") .. ", tick: " .. event.tick)
        
        local dist_to_leader = calculate_distance(position, leader_pos)
        if dist_to_leader > 3 then
            local dest_pos = {
                x = math.floor(leader_pos.x),
                y = math.floor(leader_pos.y)
            }
            schedule_autopilot_destination(creeper, {dest_pos}, event.tick + 30, false)
        end
    end

    -- Elect closest distractor
    if not party.preparation_start_tick then
        party.preparation_start_tick = event.tick
        --game.print("Debug: Set party.preparation_start_tick to " .. event.tick .. " for party " .. creeper.party_id .. ", tick: " .. event.tick)
    end
    if event.tick >= party.preparation_start_tick + 240 and (not party.last_distractor_election_tick or event.tick >= party.last_distractor_election_tick + 1200) then
        local target, target_type = behavior_utils.scan_for_enemies(leader_pos, surface, config.tier_configs[entity.name].max_targeting)
        local closest_distractor = nil
        local min_distance = math.huge
        if target and target_type == "nest" then
            for i, distractor in ipairs(distractors) do
                if distractor.entity and distractor.entity.valid and distractor.state == "preparing_to_attack" then
                    local pos = distractor_positions[i] or {angle = 180, radius = 3}
                    local guard_pos = {
                        x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                        y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                    }
                    local dist_to_guard = calculate_distance(distractor.entity.position, guard_pos)
                    if dist_to_guard < 3 then
                        local dist_to_target = calculate_distance(distractor.entity.position, target.position)
                        if dist_to_target < min_distance then
                            min_distance = dist_to_target
                            closest_distractor = distractor
                        end
                    end
                end
            end
        end
        if closest_distractor then
            local dist_to_target = calculate_distance(closest_distractor.entity.position, target.position)
            local angle = math.atan2(target.position.y - closest_distractor.entity.position.y, target.position.x - closest_distractor.entity.position.x)
            local distract_pos = {
                x = math.floor(closest_distractor.entity.position.x + math.cos(angle) * 3),
                y = math.floor(closest_distractor.entity.position.y + math.sin(angle) * 3)
            }
            closest_distractor.autopilot_destination = nil
            --schedule_autopilot_destination(closest_distractor, {distract_pos}, event.tick, false)
            closest_distractor.state = "distractor"
            -- can we loh
            distractor_state_module.handle_distractor_state(closest_distractor, event, closest_distractor.entity.position, closest_distractor.entity, surface, config.tier_configs[entity.name], party)
            closest_distractor.distract_start_tick = event.tick
            closest_distractor.distract_end_tick = event.tick + 600
            party.last_distractor_election_tick = event.tick
            --game.print("Debug: Closest distractor elected: Unit " .. closest_distractor.unit_number .. ", distance to nest: " .. min_distance .. ", in guard position after 3s delay, scheduled autopilot to (" .. distract_pos.x .. "," .. distract_pos.y .. "), tick: " .. event.tick)
            -- the above logic succesfully elects the distractors and sends them in, subsequent distractors have issues with their logic
        end
    else
        --game.print("Debug: Waiting for conditions, party.preparation_start_tick: " .. (party.preparation_start_tick or "nil") .. ", last_distractor_election_tick: " .. (party.last_distractor_election_tick or "nil") .. ", current tick: " .. event.tick .. ", party: " .. creeper.party_id)
    end

    -- Replace distractor after attack initiation
    if closest_distractor and party.attack_initiated and current_distractors <= distractor_count then
        local non_distractors = {}
        for _, member in ipairs(members) do
            if member.entity and member.entity.valid and not member.is_leader and not member.is_distractor and member.state == "preparing_to_attack" then
                table.insert(non_distractors, member)
            end
        end
        table.sort(non_distractors, function(a, b) return a.tier < b.tier end)
        if #non_distractors > 0 and #distractors < distractor_count then
            local new_distractor = non_distractors[1]
            new_distractor.is_distractor = true
            table.insert(distractors, new_distractor)
            local target, target_type = behavior_utils.scan_for_enemies(leader_pos, surface, config.tier_configs[entity.name].max_targeting)
            if target and target_type == "nest" then
                local dist_to_target = calculate_distance(new_distractor.entity.position, target.position)
                local angle = math.atan2(target.position.y - new_distractor.entity.position.y, target.position.x - new_distractor.entity.position.x)
                local distract_pos = {
                    x = math.floor(new_distractor.entity.position.x + math.cos(angle) * 3),
                    y = math.floor(new_distractor.entity.position.y + math.sin(angle) * 3)
                }         
                new_distractor.autopilot_destination = nil
                new_distractor.diversion_position = distract_pos
                new_distractor.state = "distractor"
                distractor_state_module.handle_distractor_state(new_distractor, event, new_distractor.entity.position, new_distractor.entity, surface, config.tier_configs[entity.name], party)
                new_distractor.distract_start_tick = event.tick
                new_distractor.distract_end_tick = event.tick + 600
                --game.print("Debug: Unit " .. new_distractor.unit_number .. " replaced distractor, transitioned to distractor state, diversion_position: (" .. distract_pos.x .. "," .. distract_pos.y .. "), tick: " .. event.tick)
            else
                --game.print("Debug: No valid nest target for new distractor " .. new_distractor.unit_number .. ", remaining in distractor state, tick: " .. event.tick)
            end
        end
    end

    -- Handle out-of-position distractors
    if event.tick % 60 == 0 and distractor_count > 0 then
        local random = game.create_random_generator()
        local out_of_position = nil
        local out_of_position_index = nil

        for i, distractor in ipairs(distractors) do
            if distractor.entity and distractor.entity.valid then
                local pos = distractor_positions[i] or {angle = 180, radius = 3}
                local dest_pos = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos.angle)) * pos.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos.angle)) * pos.radius)
                }
                local dist_to_dest = calculate_distance(distractor.entity.position, dest_pos)
                if dist_to_dest > 3 then
                    out_of_position = distractor
                    out_of_position_index = i
                    break
                end
            end
        end

        if out_of_position then
            local stationary_distractors = {}
            for i, distractor in ipairs(distractors) do
                if distractor.entity and distractor.entity.valid and i ~= out_of_position_index then
                    if #distractor.entity.autopilot_destinations == 0 then
                        table.insert(stationary_distractors, {distractor = distractor, index = i})
                    end
                end
            end

            if #stationary_distractors > 0 then
                local swap = stationary_distractors[random(1, #stationary_distractors)]
                local swap_distractor = swap.distractor
                local swap_index = swap.index
            
                distractors[out_of_position_index], distractors[swap_index] = swap_distractor, out_of_position
            
                local pos1 = distractor_positions[out_of_position_index] or {angle = 180, radius = 3}
                local dest_pos1 = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos1.angle)) * pos1.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos1.angle)) * pos1.radius)
                }
                local pos2 = distractor_positions[swap_index] or {angle = 180, radius = 3}
                local dest_pos2 = {
                    x = math.floor(leader_pos.x + math.cos(math.rad(pos2.angle)) * pos2.radius),
                    y = math.floor(leader_pos.y + math.sin(math.rad(pos2.angle)) * pos2.radius)
                }
            
                local dist1 = calculate_distance(swap_distractor.entity.position, dest_pos1)
                if dist1 >= 3 then
                    schedule_autopilot_destination(swap_distractor, {dest_pos1}, event.tick, false)
                    --game.print("Debug: Swapped distractor " .. swap_distractor.unit_number .. " scheduled autopilot to (" .. dest_pos1.x .. "," .. dest_pos1.y .. "), tick: " .. event.tick)
                end
            
                local dist2 = calculate_distance(out_of_position.entity.position, dest_pos2)
                if dist2 >= 3 then
                    schedule_autopilot_destination(out_of_position, {dest_pos2}, event.tick, false)
                   -- game.print("Debug: Swapped distractor " .. out_of_position.unit_number .. " scheduled autopilot to (" .. dest_pos2.x .. "," .. dest_pos2.y .. "), tick: " .. event.tick)
                end
            end
        end
    end

    -- Assign spawner targets
    local assignments = {}
    --game.print("Debug: Starting assignments for party " .. creeper.party_id .. ", current tick: " .. event.tick .. ", preparation_start_tick: " .. (party.preparation_start_tick or "none") .. ", last_distractor_election_tick: " .. (party.last_distractor_election_tick or "none") .. ", attack_initiated: " .. tostring(party.attack_initiated) .. ", target: " .. (target and "(" .. target.position.x .. "," .. target.position.y .. ")" or "none") .. ", target_type: " .. (target_type or "none"))

    -- Ensure group target is set if missing (nests or spitters within 150 tiles)
    if not target or (target_type ~= "nest" and target_type ~= "spitter") then
        local nests = surface.find_entities_filtered({
            type = "unit-spawner",
            position = creeper.entity.position,
            radius = 150,
            force = "enemy"
        })
        if #nests > 0 and nests[1].valid then
            target = nests[1]
            target_type = "nest"
            --game.print("Debug: Assigned group nest target at (" .. target.position.x .. "," .. target.position.y .. ") for party " .. creeper.party_id .. ", tick: " .. event.tick)
        else
            local spitters = surface.find_entities_filtered({
                type = "turret",
                position = creeper.entity.position,
                radius = 150,
                force = "enemy"
            })
            if #spitters > 0 and spitters[1].valid then
                target = spitters[1]
                target_type = "spitter"
                --game.print("Debug: Assigned group spitter target at (" .. target.position.x .. "," .. target.position.y .. ") for party " .. creeper.party_id .. ", tick: " .. event.tick)
            else
                --game.print("Debug: No valid nest or spitter within 150 tiles of unit " .. creeper.unit_number .. " at (" .. creeper.entity.position.x .. "," .. creeper.entity.position.y .. "), tick: " .. event.tick)
            end
        end
    end

    if event.tick >= (party.preparation_start_tick or event.tick) + 300 and not party.attack_initiated and (party.last_distractor_election_tick or event.tick) + 180 <= event.tick then
        --game.print("Debug: Entered assignment block for party " .. creeper.party_id .. ", target: " .. (target and "(" .. target.position.x .. "," .. target.position.y .. ")" or "none") .. ", target_type: " .. (target_type or "none"))
        if target and (target_type == "nest" or target_type == "spitter") then
            local total_damage = 0
            local bot_configs = {}
            for _, member in ipairs(members) do
                if member.entity and member.entity.valid and member.state ~= "distractor" then
                    local tier_config = config.tier_configs[member.entity.name]
                    total_damage = total_damage + tier_config.damage
                    table.insert(bot_configs, {member = member, damage = tier_config.damage, tier = tier_config.tier})
                end
            end
            --game.print("Debug: Party " .. creeper.party_id .. " total damage: " .. total_damage .. ", tick: " .. event.tick)

            table.sort(bot_configs, function(a, b) return a.tier < b.tier end)
            local bot_config_log = {}
            for _, bot in ipairs(bot_configs) do
                table.insert(bot_config_log, "unit=" .. bot.member.unit_number .. ",tier=" .. bot.tier .. ",damage=" .. bot.damage)
            end
            --game.print("Debug: Party " .. creeper.party_id .. " sorted bot configs: [" .. table.concat(bot_config_log, "; ") .. "], tick: " .. event.tick)

            local spawner_targets = {}
            if target_type == "nest" then
                local spawners = surface.find_entities_filtered({
                    type = "unit-spawner",
                    position = target.position,
                    radius = 20,
                    force = "enemy"
                })
                for _, spawner in ipairs(spawners) do
                    if spawner.valid and spawner.health > 0 then
                        table.insert(spawner_targets, {entity = spawner, health = spawner.health, position = spawner.position})
                    end
                end
            elseif target_type == "spitter" then
                table.insert(spawner_targets, {entity = target, health = target.health, position = target.position})
            end
            local spawner_log = {}
            for _, spawner in ipairs(spawner_targets) do
                table.insert(spawner_log, "(" .. spawner.position.x .. "," .. spawner.position.y .. "),health=" .. spawner.health)
            end
            --game.print("Debug: Found " .. #spawner_targets .. " targets near " .. target_type .. " at (" .. target.position.x .. "," .. target.position.y .. "): [" .. (table.concat(spawner_log, "; ") or "none") .. "], tick: " .. event.tick)

            for _, bot in ipairs(bot_configs) do
                if #spawner_targets > 0 then
                    local target_spawner = spawner_targets[1]
                    assignments[bot.member.unit_number] = target_spawner.position
                    bot.member.target = target_spawner.entity
                    bot.member.target_position = target_spawner.position
                    bot.member.target_health = target_spawner.health
                    bot.member.state = "approaching"
                    -- Clear follow_target and any scheduled autopilots to ensure bot paths to assigned nest, not distractor positions
                    if bot.member.entity and bot.member.entity.valid then
                        bot.member.entity.follow_target = nil
                        bot.member.entity.autopilot_destination = nil
                        -- Clear any scheduled autopilots that might be from distractor positioning
                        if storage.scheduled_autopilots and storage.scheduled_autopilots[bot.member.unit_number] then
                            storage.scheduled_autopilots[bot.member.unit_number] = nil
                        end
                        update_color(bot.member.entity, "approaching")
                        -- Immediately request path to the assigned target
                        request_multiple_paths(bot.member.entity.position, target_spawner.position, party, surface, bot.member.unit_number)
                    end
                    --game.print("Debug: Assigned " .. target_type .. " at (" .. target_spawner.position.x .. "," .. target_spawner.position.y .. ") to unit " .. bot.member.unit_number .. " (" .. bot.member.entity.name .. "), health: " .. target_spawner.health .. ", set state=approaching, tick: " .. event.tick)
                    target_spawner.health = target_spawner.health - bot.damage
                    if target_spawner.health <= 0 then
                        table.remove(spawner_targets, 1)
                        --game.print("Debug: " .. target_type .. " at (" .. target_spawner.position.x .. "," .. target_spawner.position.y .. ") depleted, removed from targets, tick: " .. event.tick)
                    end
                else
                    -- If no individual spawners, assign the main target but ensure each bot paths directly to it
                    assignments[bot.member.unit_number] = target.position
                    bot.member.target = target
                    bot.member.target_position = target.position
                    bot.member.target_health = target.health
                    bot.member.state = "approaching"
                    -- Clear follow_target and any scheduled autopilots to ensure bot paths to assigned nest, not distractor positions
                    if bot.member.entity and bot.member.entity.valid then
                        bot.member.entity.follow_target = nil
                        bot.member.entity.autopilot_destination = nil
                        -- Clear any scheduled autopilots that might be from distractor positioning
                        if storage.scheduled_autopilots and storage.scheduled_autopilots[bot.member.unit_number] then
                            storage.scheduled_autopilots[bot.member.unit_number] = nil
                        end
                        update_color(bot.member.entity, "approaching")
                        -- Immediately request path to the assigned target
                        request_multiple_paths(bot.member.entity.position, target.position, party, surface, bot.member.unit_number)
                    end
                    --game.print("Debug: Assigned " .. target_type .. " at (" .. target.position.x .. "," .. target.position.y .. ") to unit " .. bot.member.unit_number .. " (" .. bot.member.entity.name .. "), health: " .. target.health .. ", set state=approaching, tick: " .. event.tick)
                end
            end
        else
            --game.print("Debug: Assignment skipped for party " .. creeper.party_id .. ": target=" .. (target and "valid" or "nil") .. ", target_type=" .. (target_type or "none") .. ", tick: " .. event.tick)
        end
    end
end

return preparing_to_attack_state

