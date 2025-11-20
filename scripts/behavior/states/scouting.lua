-- Creeperbots - Scouting State Handler
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local config = require "scripts.behavior.config"

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
    
    -- Check if bot is being attacked by bugs - if so, explode immediately
    local is_being_attacked = false
    
    -- Method 1: Track health changes (only trigger on significant damage, > 1% or 5 health)
    if not creeper.last_health then
        creeper.last_health = entity.health
    end
    -- Track initial/max health when first seen
    if not creeper.max_health then
        creeper.max_health = entity.health
    end
    -- Update max_health if current health exceeds it (healing/repair)
    if entity.health > creeper.max_health then
        creeper.max_health = entity.health
    end
    local health_loss = creeper.last_health - entity.health
    local health_threshold = math.max(5, creeper.max_health * 0.01)  -- 1% of max health or 5, whichever is larger
    if health_loss > health_threshold then
        is_being_attacked = true
    end
    creeper.last_health = entity.health
    
    -- Method 2: Check for very close enemies (within 3 tiles) that are actually attacking
    -- Only check if we haven't already detected an attack via health loss
    if not is_being_attacked then
        local nearby_enemies = surface.find_entities_filtered({
            type = "unit",
            position = position,
            radius = 3,  -- Reduced from 5 to 3 - only very close enemies
            force = "enemy"
        })
        -- Check if any enemy is actually moving toward us or very close
        for _, enemy in ipairs(nearby_enemies) do
            if enemy.valid then
                local dist = calculate_distance(position, enemy.position)
                if dist <= 2.5 then  -- Very close, likely attacking
                    is_being_attacked = true
                    break
                end
            end
        end
    end
    
    -- If being attacked, transition to exploding
    if is_being_attacked then
        -- Find nearest enemy as target
        local nearby_enemies = surface.find_entities_filtered({
            type = "unit",
            position = position,
            radius = 10,
            force = "enemy"
        })
        if #nearby_enemies > 0 and nearby_enemies[1].valid then
            creeper.target = nearby_enemies[1]
            creeper.target_position = nearby_enemies[1].position
        else
            creeper.target = nil
            creeper.target_position = position
        end
        creeper.state = "exploding"
        update_color(entity, "exploding")
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
    
    -- Show debug message above leader's head
    if creeper.unit_number == party.grouping_leader and entity.valid then
        -- Clear old debug text
        if creeper.debug_text_id then
            if type(creeper.debug_text_id) == "userdata" then
                -- It's a rendering object directly
                if creeper.debug_text_id.valid then
                    creeper.debug_text_id.destroy()
                end
            elseif type(creeper.debug_text_id) == "number" then
                -- It's a numeric ID
                local old_text = rendering.get_object_by_id(creeper.debug_text_id)
                if old_text and old_text.valid then
                    old_text.destroy()
                end
            end
        end
        
        -- Create new debug text
        local debug_msg = string.format("Scouting: %d members", #members)
        
        creeper.debug_text_id = rendering.draw_text{
            text = debug_msg,
            surface = surface,
            target = entity,
            target_offset = {0, -2},
            color = {r = 0, g = 1, b = 0},
            scale = 1.0,
            alignment = "center"
        }
    end

    if creeper.unit_number == party.grouping_leader then
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
        -- Guards detect enemies and run towards them to explode
        -- This uses guard-specific attack logic (stays in guard state, doesn't use approaching)
        
        -- Check if guard is currently attacking
        if creeper.guard_target and creeper.guard_target.valid and creeper.guard_target.health > 0 then
            -- Guard is attacking - handle attack behavior
            local target = creeper.guard_target
            local target_pos = target.position
            local dist_to_target = calculate_distance(position, target_pos)
            
            -- Get tier config for explosion distance
            local tier_config = config.tier_configs[entity.name] or config.tier_configs["creeperbot-mk1"]
            local explosion_range = tier_config.radius or 3.5
            local explosion_distance = 3  -- Reduced from 5 - explode sooner for nests
            if target.type == "unit" or target.type == "turret" then
                explosion_distance = 1.5  -- Reduced from 2 - explode sooner for units/turrets
            end
            
            -- Close enough to explode
            if dist_to_target <= explosion_distance then
                -- Create explosion
                if tier_config.explosion == "nuke-explosion" then
                    surface.create_entity({name = "nuke-explosion", position = position})
                    local cliffs = surface.find_entities_filtered{position = position, radius = 9, type = "cliff"}
                    for _, cliff in pairs(cliffs) do
                        cliff.destroy()
                    end
                    for _ = 1, 3 do
                        surface.create_entity({name = "nuke-effects-nauvis", position = position})
                    end
                    if tier_config.extra_effect then
                        surface.create_entity({name = tier_config.extra_effect, position = position})
                    end
                else
                    surface.create_entity({name = tier_config.explosion, position = position})
                end
                
                -- Damage nearby enemy entities
                local nearby_entities = surface.find_entities_filtered{
                    position = position,
                    radius = explosion_range,
                    force = "enemy"
                }
                for _, nearby_entity in pairs(nearby_entities) do
                    if nearby_entity.valid and nearby_entity.health then
                        nearby_entity.damage(tier_config.damage, "enemy", "explosion")
                    end
                end
                
                -- Destroy the bot
                entity.die("enemy")
                return
            end
            
            -- Still too far - move towards target
            entity.follow_target = nil
            if not entity.autopilot_destination or (not creeper.guard_last_movement or event.tick >= creeper.guard_last_movement + 15) then
                entity.autopilot_destination = nil
                local success, err = pcall(function()
                    entity.add_autopilot_destination(target_pos)
                end)
                if success then
                    creeper.guard_last_movement = event.tick
                end
            end
            
            -- Update color to show guard is attacking
            update_color(entity, "approaching")
            return
        else
            -- No target or target is dead - guard survived attack, rejoin group
            creeper.guard_target = nil
            creeper.guard_target_position = nil
            
            -- Clear assignment in party
            if party and party.guard_assignments then
                for enemy_unit_number, guard_unit_number in pairs(party.guard_assignments) do
                    if guard_unit_number == creeper.unit_number then
                        party.guard_assignments[enemy_unit_number] = nil
                        break
                    end
                end
            end
            
            -- Guard automatically rejoins - will follow leader again
            update_color(entity, "guard")
            
            -- Clear movement state to allow following leader
            entity.follow_target = nil
            entity.autopilot_destination = nil
            if storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number] then
                storage.scheduled_autopilots[creeper.unit_number] = nil
            end
            
            -- Check for new enemies to attack (only assign if enemy doesn't have a guard)
            local nearby_enemies = surface.find_entities_filtered({
                type = {"unit", "turret", "unit-spawner"},
                position = position,
                radius = 45,
                force = "enemy"
            })
            
            if #nearby_enemies > 0 and party then
                -- Find enemies that don't have guards assigned
                local unassigned_enemies = {}
                for _, enemy in ipairs(nearby_enemies) do
                    if enemy.valid and enemy.health > 0 then
                        local has_guard = false
                        if party.guard_assignments then
                            for enemy_unit_number, guard_unit_number in pairs(party.guard_assignments) do
                                if enemy_unit_number == enemy.unit_number then
                                    local guard_creeper = storage.creeperbots[guard_unit_number]
                                    if guard_creeper and guard_creeper.entity and guard_creeper.entity.valid and
                                       guard_creeper.guard_target and guard_creeper.guard_target.valid then
                                        has_guard = true
                                        break
                                    end
                                end
                            end
                        end
                        if not has_guard then
                            table.insert(unassigned_enemies, enemy)
                        end
                    end
                end
                
                if #unassigned_enemies > 0 then
                    -- Find closest unassigned enemy
                    local closest_enemy = nil
                    local min_dist = math.huge
                    for _, enemy in ipairs(unassigned_enemies) do
                        local dist = calculate_distance(position, enemy.position)
                        if dist < min_dist then
                            min_dist = dist
                            closest_enemy = enemy
                        end
                    end
                    
                    if closest_enemy then
                        -- Get all available guards (not currently attacking)
                        local available_guards = {}
                        if party then
                            for unit_number, member in pairs(storage.creeperbots or {}) do
                                if member.party_id == creeper.party_id and 
                                   member.is_guard and 
                                   member.entity and 
                                   member.entity.valid and
                                   not member.guard_target then
                                    table.insert(available_guards, member)
                                end
                            end
                        end
                        
                        -- Find which guard is closest to the enemy
                        local closest_guard = nil
                        local closest_guard_dist = math.huge
                        for _, guard in ipairs(available_guards) do
                            if guard.entity and guard.entity.valid then
                                local dist = calculate_distance(guard.entity.position, closest_enemy.position)
                                if dist < closest_guard_dist then
                                    closest_guard_dist = dist
                                    closest_guard = guard
                                end
                            end
                        end
                        
                        -- Only this guard attacks if it's the closest
                        if closest_guard and closest_guard.unit_number == creeper.unit_number then
                            -- This guard is closest - start attack (stay in guard state)
                            creeper.guard_target = closest_enemy
                            creeper.guard_target_position = closest_enemy.position
                            
                            -- Track assignment in party
                            if party then
                                party.guard_assignments = party.guard_assignments or {}
                                party.guard_assignments[closest_enemy.unit_number] = creeper.unit_number
                            end
                            
                            -- Clear follow_target so guard can move independently
                            entity.follow_target = nil
                            entity.autopilot_destination = nil
                            if storage.scheduled_autopilots and storage.scheduled_autopilots[creeper.unit_number] then
                                storage.scheduled_autopilots[creeper.unit_number] = nil
                            end
                            
                            -- Update color to show guard is attacking
                            update_color(entity, "approaching")
                            return
                        end
                    end
                end
            end
        end
        
        -- No enemies detected - continue following leader
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

