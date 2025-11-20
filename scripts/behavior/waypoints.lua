-- Creeperbots - Waypoint Processing Module
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local config = require "scripts.behavior.config"
local rendering_module = require "scripts.behavior.rendering"
local behavior_utils = require "scripts.behavior.utils"

local waypoints = {}

function waypoints.process_waypoints(creeper)
    --game.print("Debug: Entering process_waypoints for unit " .. (creeper.unit_number or "unknown") .. ", tick: " .. game.tick)
    
    local entity = creeper.entity
    local position = entity.position
    local surface = entity.surface
    
    if not entity or not entity.valid or not surface or not surface.valid then
        --game.print("Error: Invalid entity or surface for unit " .. (creeper.unit_number or "unknown") .. ", tick: " .. game.tick)
        return false
    end
    
    -- Don't process waypoints if leader is in defensive_formation state
    if creeper.state == "defensive_formation" then
        return false
    end

    -- Handle distractor waypoints
    if creeper.state == "distractor" then
        --game.print("Debug: Processing distractor waypoints for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
        if not config.tier_configs[entity.name] then
           -- game.print("Error: Invalid tier config for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
            return false
        end
        --game.print("Debug: Tier config valid for unit " .. creeper.unit_number .. ", tier: " .. entity.name .. ", tick: " .. game.tick)

        local target_pos = creeper.diversion_position or creeper.target_position
        if not target_pos or not target_pos.x or not target_pos.y then
            --game.print("Debug: Invalid target_pos for distractor " .. creeper.unit_number .. ", target_pos: " .. tostring(target_pos))
            return false
        end

        local dist_to_target = calculate_distance(position, target_pos)
        --game.print("Debug: Distractor " .. creeper.unit_number .. ", dist_to_target: " .. dist_to_target .. ", target_pos: (" .. target_pos.x .. "," .. target_pos.y .. "), diversion_position: " .. (creeper.diversion_position and "(" .. creeper.diversion_position.x .. "," .. creeper.diversion_position.y .. ")" or "none"))

        -- Check if bot is stuck
        --game.print("Debug: Stuck check for unit " .. creeper.unit_number .. ": autopilot_destination=" .. (entity.autopilot_destination and "(" .. entity.autopilot_destination.x .. "," .. entity.autopilot_destination.y .. ")" or "none") .. ", last_position=" .. (creeper.last_position and "(" .. creeper.last_position.x .. "," .. creeper.last_position.y .. ")" or "none") .. ", last_position_tick=" .. (creeper.last_position_tick or "none") .. ", game.tick=" .. game.tick .. ", position=(" .. position.x .. "," .. position.y .. "), tick_check=" .. (creeper.last_position_tick and tostring(game.tick >= creeper.last_position_tick + 120) or "false") .. ", position_match=" .. (creeper.last_position and tostring(creeper.last_position.x == position.x and creeper.last_position.y == position.y) or "false"))
        -- solved because autopilot destinatino was nil
        -- distractor state logic reinitiated the attack
        if not entity.autopilot_destination and creeper.last_position and creeper.last_position_tick and game.tick >= creeper.last_position_tick and creeper.last_position.x == position.x and creeper.last_position.y == position.y then
            --game.print("Stuck: Distractor " .. creeper.unit_number .. " stuck at (" .. position.x .. "," .. position.y .. "), tick: " .. game.tick)
            creeper.final_diversion_position = creeper.diversion_position
            entity.autopilot_destination = nil
            local random = game.create_random_generator()
            local attempts = 0
            local max_attempts = 3
            local new_pos = nil
            while attempts < max_attempts do
                local angle = math.rad(random(0, 360))
                local distance = 3
                new_pos = {
                    x = math.floor(position.x + math.cos(angle) * distance),
                    y = math.floor(position.y + math.sin(angle) * distance)
                }
                local chunk_pos = {x = math.floor(new_pos.x / 32), y = math.floor(new_pos.y / 32)}
                if surface.is_chunk_generated(chunk_pos) and surface.can_place_entity{name = "character", position = new_pos} then
                    break
                end
                --game.print("Debug: Invalid new position for distractor " .. creeper.unit_number .. " at (" .. new_pos.x .. "," .. new_pos.y .. "), attempt: " .. (attempts + 1))
                attempts = attempts + 1
                new_pos = nil
            end
            if not new_pos then
                --game.print("Debug: Failed to find new position for distractor " .. creeper.unit_number .. " after " .. max_attempts .. " attempts, tick: " .. game.tick)
                creeper.last_position = nil
                creeper.last_position_tick = nil
                return false
            end
            schedule_autopilot_destination(creeper, {new_pos}, game.tick, false)
            creeper.autopilot_set_tick = game.tick
            creeper.last_position = nil
            creeper.last_position_tick = nil
            --game.print("Debug: Unstuck successful for distractor " .. creeper.unit_number .. ", new position: (" .. new_pos.x .. "," .. new_pos.y .. "), tick: " .. game.tick)
            return true
        else
            --game.print("Stuck: Distractor " .. creeper.unit_number .. " not stuck at (" .. position.x .. "," .. position.y .. "), tick: " .. game.tick)

        end

        -- Update last position and tick
        creeper.last_position = {x = position.x, y = position.y}
        creeper.last_position_tick = game.tick
        --game.print("Debug: Updated last position (" .. position.x .. "," .. position.y .. ") at tick " .. game.tick .. " for distractor " .. creeper.unit_number)
        --game.print("Debug: Distractor " .. creeper.unit_number .. ", dist_to_target: " .. dist_to_target .. ", target_pos: (" .. target_pos.x .. "," .. target_pos.y .. "), diversion_position: " .. (creeper.diversion_position and "(" .. creeper.diversion_position.x .. "," .. creeper.diversion_position.y .. ")" or "none"))
        --game.print("Debug: Autopilot set tick: " .. (creeper.autopilot_set_tick or "none") .. ", current tick: " .. game.tick .. " for unit " .. creeper.unit_number)
       
        if dist_to_target > 30 then
            local path_success = request_multiple_paths(position, target_pos, nil, surface, creeper.unit_number)
            --game.print("Debug: Distractor " .. creeper.unit_number .. " path request " .. (path_success and "succeeded" or "failed") .. " to " .. (creeper.diversion_position and "diversion" or "target") .. " (" .. target_pos.x .. "," .. target_pos.y .. "), tick: " .. game.tick)
            if not path_success then
                --game.print("Debug: Path request failed for distractor " .. creeper.unit_number .. " to " .. (creeper.diversion_position and "diversion" or "target") .. " (" .. target_pos.x .. "," .. target_pos.y .. ")")
                return false
            end
            local autopilot = entity.autopilot_destination
            --game.print("Debug: Distractor " .. creeper.unit_number .. " pathing to " .. (creeper.diversion_position and "diversion" or "target") .. " at (" .. target_pos.x .. "," .. target_pos.y .. "), autopilot: (" .. (autopilot and autopilot.x .. "," .. autopilot.y or "none") .. ")")
            creeper.autopilot_set_tick = game.tick
            return true
        end

        -- Handle diversion position selection when within 30 tiles and no diversion_position
        if not creeper.diversion_position then
            entity.autopilot_destination = nil
            local random = game.create_random_generator()
            local attempts = 0
            local max_attempts = 3
            local divert_pos = nil
            local base_angle, angle_variation
            while attempts < max_attempts do
                base_angle = random(1, 2) == 1 and 180 or 360
                angle_variation = random(-30, 30)
                local divert_angle = math.rad(base_angle + angle_variation)
                local divert_distance = 20
                divert_pos = {
                    x = math.floor(position.x + math.cos(divert_angle) * divert_distance),
                    y = math.floor(position.y + math.sin(divert_angle) * divert_distance)
                }
                local chunk_pos = {x = math.floor(divert_pos.x / 32), y = math.floor(divert_pos.y / 32)}
                if surface.is_chunk_generated(chunk_pos) and surface.can_place_entity{name = "character", position = divert_pos} then
                    break
                end
                --game.print("Debug: Invalid diversion position for distractor " .. creeper.unit_number .. " at (" .. divert_pos.x .. "," .. divert_pos.y .. "), attempt: " .. (attempts + 1))
                attempts = attempts + 1
                divert_pos = nil
            end
            if not divert_pos then
                --game.print("Debug: Failed to find valid diversion position for distractor " .. creeper.unit_number .. " after " .. max_attempts .. " attempts")
                return false
            end
            creeper.diversion_position = divert_pos
            local path_success = request_multiple_paths(position, divert_pos, nil, surface, creeper.unit_number)
            --game.print("Debug: Distractor " .. creeper.unit_number .. " diversion path request " .. (path_success and "succeeded" or "failed") .. " to (" .. divert_pos.x .. "," .. divert_pos.y .. "), tick: " .. game.tick)
            if not path_success then
                --game.print("Debug: Path request failed for distractor " .. creeper.unit_number .. " to diversion (" .. divert_pos.x .. "," .. divert_pos.y .. ")")
                return false
            end
            local autopilot = entity.autopilot_destination
            --game.print("Debug: Distractor " .. creeper.unit_number .. " diverting to (" .. divert_pos.x .. "," .. divert_pos.y .. "), angle: " .. (base_angle + angle_variation) .. ", dist_to_target: " .. dist_to_target .. ", autopilot: (" .. (autopilot and autopilot.x .. "," .. autopilot.y or "none") .. ")")
            creeper.autopilot_set_tick = game.tick
            return true
        end

        -- Check if at diversion position
        if creeper.diversion_position and not entity.autopilot_destination and calculate_distance(position, creeper.diversion_position) < 1 then
            local enemies = surface.find_entities_filtered{
                position = position,
                radius = 5,
                force = "enemy",
                type = "unit"
            }
            if #enemies >= 5 then
                if not creeper.explosion_wait_tick then
                    creeper.explosion_wait_tick = game.tick + 60
                    --game.print("Debug: Distractor " .. creeper.unit_number .. " found " .. #enemies .. " biters within 5 tiles, waiting 1 second to explode, tick: " .. game.tick)
                elseif game.tick >= creeper.explosion_wait_tick then
                    creeper.state = "exploding"
                    update_color(entity, "exploding")
                    --game.print("Debug: Distractor " .. creeper.unit_number .. " transitioning to exploding, tick: " .. game.tick)
                    creeper.explosion_wait_tick = nil
                end
            else
                if not creeper.explosion_wait_tick then
                    creeper.explosion_wait_tick = game.tick + 60
                    --game.print("Debug: Distractor " .. creeper.unit_number .. " found " .. #enemies .. " biters within 5 tiles, waiting 1 second to explode, tick: " .. game.tick)
                elseif game.tick >= creeper.explosion_wait_tick then
                    creeper.state = "exploding"
                    update_color(entity, "exploding")
                    --game.print("Debug: Distractor " .. creeper.unit_number .. " transitioning to exploding, tick: " .. game.tick)
                    creeper.explosion_wait_tick = nil
                end
            end
            return true
        end

        -- Continue moving to diversion position if not yet arrived
        if creeper.diversion_position and dist_to_target <= 30 and not entity.autopilot_destination then
            schedule_autopilot_destination(creeper, {creeper.diversion_position}, game.tick, false)
            --game.print("Debug: Distractor " .. creeper.unit_number .. " scheduled autopilot to diversion (" .. creeper.diversion_position.x .. "," .. creeper.diversion_position.y .. "), tick: " .. game.tick)
            creeper.autopilot_set_tick = game.tick
            return true
        end
        return true
    end

    -- Original leader logic (unchanged)
    if creeper.is_leader then
        local party = storage.parties[creeper.party_id]
        if not party then
            --game.print("Error: Invalid party for unit " .. (creeper.unit_number or "unknown") .. ", tick: " .. game.tick)
            return false
        end
        --game.print("Debug: Validation passed for unit " .. creeper.unit_number .. ", leader: " .. (creeper.is_leader and "yes" or "no") .. ", tick: " .. game.tick)
        
        if not config.tier_configs[entity.name] then
            --game.print("Error: Invalid tier config for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
            return false
        end
        --game.print("Debug: Tier config valid for unit " .. creeper.unit_number .. ", tier: " .. entity.name .. ", tick: " .. game.tick)
        
        if not entity.autopilot_destinations or #entity.autopilot_destinations == 0 then
            --game.print("Debug: No autopilot destinations for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
            if creeper.is_leader then
                local target_pos = get_unvisited_chunk(position, party)
                if target_pos.x ~= position.x or target_pos.y ~= position.y then
                    -- Verify target position is not in water
                    if is_position_on_water(surface, target_pos, 1.5) then
                        local safe_target = find_safe_position_away_from_water(surface, entity, target_pos, 30)
                        if safe_target then
                            target_pos = safe_target
                        else
                            --game.print("Error: Target chunk position is in water and no safe alternative found for leader " .. creeper.unit_number)
                            return false
                        end
                    end
                    --game.print("Debug: Leader " .. creeper.unit_number .. " requesting path to (" .. target_pos.x .. "," .. target_pos.y .. "), tick: " .. game.tick)
                    request_multiple_paths(position, target_pos, party, surface, creeper.unit_number)
                else
                   -- game.print("Error: No valid chunk found for leader " .. creeper.unit_number .. ", tick: " .. game.tick)
                end
            end
            return false
        end
        
        local current_destination = entity.autopilot_destination
        if not current_destination then
            --game.print("Debug: No current destination for unit " .. creeper.unit_number .. ", clearing autopilot, tick: " .. game.tick)
            entity.autopilot_destination = nil
            rendering_module.clear_renderings(creeper)
            return false
        end
        
        -- Check if current destination is in water - if so, skip it
        if is_position_on_water(surface, current_destination, 1.5) then
            --game.print("Debug: Current destination for unit " .. creeper.unit_number .. " is in water, skipping")
            entity.autopilot_destination = nil
            local remaining_waypoints = {}
            if entity.autopilot_destinations and #entity.autopilot_destinations > 1 then
                for i = 2, #entity.autopilot_destinations do
                    table.insert(remaining_waypoints, entity.autopilot_destinations[i])
                end
            end
            if #remaining_waypoints > 0 then
                for _, waypoint in ipairs(remaining_waypoints) do
                    -- Check if this waypoint is also in water
                    if not is_position_on_water(surface, waypoint, 1.5) then
                        entity.add_autopilot_destination(waypoint)
                    end
                end
            end
            -- If no safe waypoints remain, request a new path
            if not entity.autopilot_destination then
                if creeper.is_leader then
                    local target_pos = get_unvisited_chunk(position, party)
                    if target_pos.x ~= position.x or target_pos.y ~= position.y then
                        request_multiple_paths(position, target_pos, party, surface, creeper.unit_number)
                    end
                end
            end
            return false
        end
        
       -- game.print("Debug: Current destination for unit " .. creeper.unit_number .. ": (" .. current_destination.x .. "," .. current_destination.y .. "), tick: " .. game.tick)
        
        local distance = calculate_distance(position, current_destination)
        --game.print("Debug: Distance to current destination for unit " .. creeper.unit_number .. ": " .. distance .. ", tick: " .. game.tick)
        
        -- Check if leader is stuck (no speed, same position for a while)
        local no_speed = (entity.speed == 0)
        if no_speed and creeper.last_position and creeper.last_position_tick and 
           game.tick >= creeper.last_position_tick + 120 and
           creeper.last_position.x == position.x and creeper.last_position.y == position.y then
            
            -- Check if stuck near corner cliffs (2+ cliffs nearby = corner)
            local nearby_cliffs = surface.find_entities_filtered{
                position = position,
                radius = 3,
                type = "cliff"
            }
            local is_corner_cliff = (#nearby_cliffs >= 2)
            
            -- If corner cliff, skip waypoints more aggressively or request new path
            if is_corner_cliff then
                local next_waypoint = nil
                if entity.autopilot_destinations and #entity.autopilot_destinations > 1 then
                    next_waypoint = entity.autopilot_destinations[2]
                end
                
                if next_waypoint then
                    local dist_to_next = calculate_distance(position, next_waypoint)
                    -- For corner cliffs, skip to next waypoint even if further away (up to 30 tiles)
                    if dist_to_next <= 30 then
                        -- Check if next waypoint is in water
                        if is_position_on_water(surface, next_waypoint, 1.5) then
                            -- Skip water waypoint and find next safe one
                            entity.autopilot_destination = nil
                            local remaining_waypoints = {}
                            for i = 2, #entity.autopilot_destinations do
                                table.insert(remaining_waypoints, entity.autopilot_destinations[i])
                            end
                            local found_safe = false
                            for _, waypoint in ipairs(remaining_waypoints) do
                                if not is_position_on_water(surface, waypoint, 1.5) then
                                    entity.add_autopilot_destination(waypoint)
                                    found_safe = true
                                    break
                                end
                            end
                            if not found_safe then
                                -- No safe waypoints, request new path
                                entity.autopilot_destination = nil
                                request_multiple_paths(position, current_destination, party, surface, creeper.unit_number)
                                creeper.last_position = nil
                                creeper.last_position_tick = nil
                                return false
                            end
                            creeper.last_position = nil
                            creeper.last_position_tick = nil
                            --game.print("Debug: Leader " .. creeper.unit_number .. " stuck at corner cliff, skipped water waypoint")
                            return true
                        end
                        -- Clear current destination and skip to next waypoint
                        entity.autopilot_destination = nil
                        local remaining_waypoints = {}
                        for i = 2, #entity.autopilot_destinations do
                            table.insert(remaining_waypoints, entity.autopilot_destinations[i])
                        end
                        for _, waypoint in ipairs(remaining_waypoints) do
                            entity.add_autopilot_destination(waypoint)
                        end
                        creeper.last_position = nil
                        creeper.last_position_tick = nil
                        --game.print("Debug: Leader " .. creeper.unit_number .. " stuck at corner cliff, skipping to next waypoint at (" .. next_waypoint.x .. "," .. next_waypoint.y .. ")")
                        return true
                    else
                        -- Next waypoint is too far, request a new path to current destination (will route around corner)
                        entity.autopilot_destination = nil
                        request_multiple_paths(position, current_destination, party, surface, creeper.unit_number)
                        creeper.last_position = nil
                        creeper.last_position_tick = nil
                        --game.print("Debug: Leader " .. creeper.unit_number .. " stuck at corner cliff, requesting new path to current destination")
                        return false
                    end
                else
                    -- No next waypoint, request new path to current destination
                    entity.autopilot_destination = nil
                    request_multiple_paths(position, current_destination, party, surface, creeper.unit_number)
                    creeper.last_position = nil
                    creeper.last_position_tick = nil
                    --game.print("Debug: Leader " .. creeper.unit_number .. " stuck at corner cliff, requesting new path (no next waypoint)")
                    return false
                end
            end
            
            -- Otherwise, use existing logic (skip to next waypoint if close, etc.)
            local next_waypoint = nil
            if entity.autopilot_destinations and #entity.autopilot_destinations > 1 then
                next_waypoint = entity.autopilot_destinations[2]
            end
            
            if next_waypoint then
                local dist_to_next = calculate_distance(position, next_waypoint)
                -- If next waypoint is close (within 10 tiles), skip to it
                if dist_to_next <= 10 then
                    -- Check if next waypoint is in water - if so, skip it and find a safe one
                    if is_position_on_water(surface, next_waypoint, 1.5) then
                        -- Skip water waypoint and find next safe one
                        entity.autopilot_destination = nil
                        local remaining_waypoints = {}
                        for i = 2, #entity.autopilot_destinations do
                            table.insert(remaining_waypoints, entity.autopilot_destinations[i])
                        end
                        local found_safe = false
                        for _, waypoint in ipairs(remaining_waypoints) do
                            if not is_position_on_water(surface, waypoint, 1.5) then
                                entity.add_autopilot_destination(waypoint)
                                found_safe = true
                                break
                            end
                        end
                        if not found_safe then
                            -- No safe waypoints, request new path
                            entity.autopilot_destination = nil
                            request_multiple_paths(position, current_destination, party, surface, creeper.unit_number)
                            creeper.last_position = nil
                            creeper.last_position_tick = nil
                            return false
                        end
                        creeper.last_position = nil
                        creeper.last_position_tick = nil
                        --game.print("Debug: Leader " .. creeper.unit_number .. " stuck, skipped water waypoint")
                        return true
                    end
                    -- Clear current destination and skip to next waypoint
                    entity.autopilot_destination = nil
                    local remaining_waypoints = {}
                    for i = 2, #entity.autopilot_destinations do
                        table.insert(remaining_waypoints, entity.autopilot_destinations[i])
                    end
                    for _, waypoint in ipairs(remaining_waypoints) do
                        entity.add_autopilot_destination(waypoint)
                    end
                    creeper.last_position = nil
                    creeper.last_position_tick = nil
                    --game.print("Debug: Leader " .. creeper.unit_number .. " stuck, skipping to next waypoint at (" .. next_waypoint.x .. "," .. next_waypoint.y .. ")")
                    return true
                else
                    -- Next waypoint is far, request a new path to current destination
                    entity.autopilot_destination = nil
                    request_multiple_paths(position, current_destination, party, surface, creeper.unit_number)
                    creeper.last_position = nil
                    creeper.last_position_tick = nil
                    --game.print("Debug: Leader " .. creeper.unit_number .. " stuck, requesting new path to current destination")
                    return false
                end
            else
                -- No next waypoint, request new path to current destination
                entity.autopilot_destination = nil
                request_multiple_paths(position, current_destination, party, surface, creeper.unit_number)
                creeper.last_position = nil
                creeper.last_position_tick = nil
                --game.print("Debug: Leader " .. creeper.unit_number .. " stuck, requesting new path (no next waypoint)")
                return false
            end
        end
        
        -- Update last position and tick for stuck detection
        if not creeper.last_position or creeper.last_position.x ~= position.x or creeper.last_position.y ~= position.y then
            creeper.last_position = {x = position.x, y = position.y}
            creeper.last_position_tick = game.tick
        end
        
        if creeper.dynamic_line_id then
            if type(creeper.dynamic_line_id) == "userdata" and creeper.dynamic_line_id.valid then
                --game.print("Debug: Destroying userdata dynamic line for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
                creeper.dynamic_line_id.destroy()
            elseif type(creeper.dynamic_line_id) == "number" then
                local render_obj = rendering.get_object_by_id(creeper.dynamic_line_id)
                if render_obj and render_obj.valid then
                    --game.print("Debug: Destroying numeric dynamic line ID " .. creeper.dynamic_line_id .. " for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
                    render_obj.destroy()
                else
                    --game.print("Debug: Invalid numeric dynamic line ID " .. tostring(creeper.dynamic_line_id) .. " for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
                end
            end
            creeper.dynamic_line_id = nil
        end
        
        local threshold = 3
        if distance <= threshold and (creeper.last_waypoint_change or 0) + 20 < game.tick then
           -- game.print("Debug: Leader " .. creeper.unit_number .. " reached waypoint at (" .. current_destination.x .. "," .. current_destination.y .. ") on tick " .. game.tick)
            
            -- Mark chunks within view distance (3 chunks) when waypoint is reached
            if creeper.is_leader and party then
                local current_chunk_pos = get_chunk_pos(current_destination)
                -- Mark chunks in view distance, but don't set safety yet (wait for enemy scan)
                mark_chunks_in_view(surface, current_chunk_pos.x, current_chunk_pos.y, nil, game.tick, 3)
            end
            
           -- game.print("Debug: Scanning for enemies for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
            local target, target_type = behavior_utils.scan_for_enemies(position, surface, config.tier_configs[entity.name].max_targeting)
            
            if target then
                if target_type == "nest" then
                    -- Nests trigger preparing_to_attack
                    -- Mark chunks within view distance as unsafe when enemies are detected
                    if creeper.is_leader and party then
                        local current_chunk_pos = get_chunk_pos(current_destination)
                        mark_chunks_in_view(surface, current_chunk_pos.x, current_chunk_pos.y, false, game.tick, 3)
                        --game.print("Debug: Chunks within 3 chunks of (" .. current_chunk_pos.x .. "," .. current_chunk_pos.y .. ") marked as unsafe due to enemy detection")
                    end
                    
                    --game.print("Debug: Leader " .. creeper.unit_number .. " detected nest at (" .. target.position.x .. "," .. target.position.y .. "), transitioning party to preparing_to_attack, tick: " .. game.tick)
                    for unit_number, member in pairs(storage.creeperbots or {}) do
                        if member.party_id == creeper.party_id and member.entity and member.entity.valid then
                            -- Don't transition bots that are already in defensive attack
                            if not member.defensive_target then
                                -- Clear follow_target before transitioning
                                member.entity.follow_target = nil
                                member.state = "preparing_to_attack"
                                update_color(member.entity, "preparing_to_attack")
                                member.entity.autopilot_destination = nil
                                if storage.scheduled_autopilots and storage.scheduled_autopilots[unit_number] then
                                    storage.scheduled_autopilots[unit_number] = nil
                                    --game.print("Debug: Cleared scheduled autopilot for unit " .. unit_number .. ", tick: " .. game.tick)
                                end
                               --game.print("Debug: Unit " .. unit_number .. " transitioned to preparing_to_attack, tick: " .. game.tick)
                            end
                        end
                    end
                    return false
                elseif target_type == "unit" then
                    game.print("DEBUG: Waypoints detected UNIT at waypoint, leader=" .. creeper.unit_number)
                    -- Units trigger defensive formation - leader stops, other bots attack
                    -- Mark chunks as unsafe
                    if creeper.is_leader and party then
                        local current_chunk_pos = get_chunk_pos(current_destination)
                        mark_chunks_in_view(surface, current_chunk_pos.x, current_chunk_pos.y, false, game.tick, 3)
                        game.print("DEBUG: Chunks within 3 chunks of (" .. current_chunk_pos.x .. "," .. current_chunk_pos.y .. ") marked as unsafe due to enemy detection") -- logs once
                        
                        -- Leader stops and forms defensive formation
                        -- Clear all autopilot destinations aggressively
                        game.print("DEBUG: autopilot_destinations count: " .. #entity.autopilot_destinations)  -- logs once

                        game.print("DEBUG: Clearing leader autopilot destinations, unit=" .. creeper.unit_number) -- logs once
                        entity.autopilot_destination = nil
                        entity.follow_target = nil
                        
                        -- Check autopilot_destinations status
                        local dest_count = entity.autopilot_destinations and #entity.autopilot_destinations or 0
                        game.print("DEBUG: autopilot_destinations count: " .. dest_count) -- logs once
                        
                        -- Clear all autopilot destinations (autopilot_destinations is read-only, so we clear current destination repeatedly)
                        local attempts = 0
                        while entity.autopilot_destinations and #entity.autopilot_destinations > 0 and attempts < 20 do
                            entity.autopilot_destination = nil
                            attempts = attempts + 1
                            game.print("DEBUG: Cleared autopilot destination, attempt " .. attempts .. ", remaining: " .. (#entity.autopilot_destinations or 0))
                        end
                        game.print("DEBUG: Finished clearing autopilot destinations after " .. attempts .. " attempts") -- logs once
                        
                        -- Clear scheduled autopilots
                        if storage.scheduled_autopilots then
                            if storage.scheduled_autopilots[creeper.unit_number] then
                                storage.scheduled_autopilots[creeper.unit_number] = nil
                                game.print("DEBUG: Scheduled autopilot cleared")
                            else
                                game.print("DEBUG: No scheduled autopilot found for unit " .. creeper.unit_number) -- logs once
                            end
                        else
                            game.print("DEBUG: storage.scheduled_autopilots is nil")
                        end
                        
                        -- Also clear autopilot queue
                        if storage.autopilot_queue then
                            if storage.autopilot_queue[creeper.unit_number] then
                                storage.autopilot_queue[creeper.unit_number] = nil
                                game.print("DEBUG: Autopilot queue cleared") -- logs once
                            else
                                game.print("DEBUG: No autopilot queue found for unit " .. creeper.unit_number)
                            end
                        else
                            game.print("DEBUG: storage.autopilot_queue is nil")
                        end
                        
                        -- Set defensive formation flag so bots know to form up
                        party.defensive_formation = true
                        party.defensive_formation_tick = game.tick
                        party.defensive_formation_start_tick = game.tick  -- Initialize timer for 60-tick wait
                        party.state = "defensive_formation"
                        game.print("party state set to defensive_formation")    

                        -- Transition party to defensive_formation state (including leader)
                        -- This allows guards to position and followers to form up
                        for unit_number, member in pairs(storage.creeperbots or {}) do
                            if member.party_id == creeper.party_id and member.entity and member.entity.valid then
                                -- Don't transition bots that are already attacking
                                if not member.defensive_target and not member.guard_target then
                                    if member.state == "scouting" or member.state == "guard" then
                                        member.state = "defensive_formation"
                                        update_color(member.entity, member.is_guard and "guard" or "defensive_formation")
                                        -- game.print("DEBUG: Bot " .. member.unit_number .. " transitioning to defensive_formation")
                                    end
                                end
                            end
                        end
                        -- Also transition leader to defensive_formation state
                        if creeper.state == "scouting" then
                            creeper.state = "defensive_formation"
                            update_color(entity, "defensive_formation")
                            -- game.print("DEBUG: Leader " .. creeper.unit_number .. " transitioning to defensive_formation")
                        end
                        
                        game.print("DEBUG: Leader stopped for defensive formation, party transitioning to defensive_formation state")
                        
                        -- CRITICAL: Return early to prevent further waypoint processing
                        -- This ensures the leader stays stopped and doesn't get new destinations
                        game.print("DEBUG: Returning early from process_waypoints to prevent further processing")
                        return false
                    end
                    
                    -- Find all nearby enemy units and assign bots to attack them
                    game.print("DEBUG: Scanning for nearby enemies within 60 tiles...")
                    local nearby_enemies = surface.find_entities_filtered({
                        type = {"unit", "turret", "unit-spawner"},
                        position = position,
                        radius = 60,
                        force = "enemy"
                    })
                    
                    game.print("DEBUG: Found " .. #nearby_enemies .. " nearby enemies, party=" .. tostring(party ~= nil))
                    
                    if #nearby_enemies > 0 and party then
                        game.print("DEBUG: Processing " .. #nearby_enemies .. " enemies for assignment...")
                        -- Process each enemy and assign bots based on health
                        for _, enemy in ipairs(nearby_enemies) do
                            if enemy.valid and enemy.health > 0 then
                                game.print("DEBUG: Processing enemy unit " .. enemy.unit_number .. " with health " .. enemy.health)
                                
                                -- Count how many bots are already attacking this enemy
                                local attacking_count = 0
                                for unit_number, member in pairs(storage.creeperbots or {}) do
                                    if member.party_id == creeper.party_id and member.entity and member.entity.valid then
                                        -- Check if bot has this enemy as defensive target
                                        if (member.defensive_target and member.defensive_target.valid and member.defensive_target.unit_number == enemy.unit_number) or
                                           (member.guard_target and member.guard_target.valid and member.guard_target.unit_number == enemy.unit_number) then
                                            attacking_count = attacking_count + 1
                                        end
                                    end
                                end
                                game.print("DEBUG: Enemy " .. enemy.unit_number .. " already has " .. attacking_count .. " bots attacking")
                                
                                -- Calculate how many bots are needed based on enemy health
                                -- Get average damage of available bots
                                local total_damage = 0
                                local bot_count = 0
                                for unit_number, member in pairs(storage.creeperbots or {}) do
                                    if member.party_id == creeper.party_id and member.entity and member.entity.valid then
                                        local tier_config = config.tier_configs[member.entity.name] or config.tier_configs["creeperbot-mk1"]
                                        total_damage = total_damage + tier_config.damage
                                        bot_count = bot_count + 1
                                    end
                                end
                                local average_damage = bot_count > 0 and (total_damage / bot_count) or 200
                                game.print("DEBUG: Party has " .. bot_count .. " bots, average damage=" .. average_damage)
                                
                                -- Calculate required bots: ceil(enemy_health / average_damage) with 20% safety margin
                                local required_bots = math.ceil((enemy.health / average_damage) * 1.2)
                                required_bots = math.max(1, required_bots)  -- At least 1 bot
                                game.print("DEBUG: Enemy " .. enemy.unit_number .. " needs " .. required_bots .. " bots (health=" .. enemy.health .. ", avg_dmg=" .. average_damage .. ")")
                                
                                -- Assign more bots if needed
                                if attacking_count < required_bots then
                                    local needed = required_bots - attacking_count
                                    game.print("DEBUG: Need to assign " .. needed .. " more bots")
                                    
                                    -- Get available bots (not currently attacking anything, EXCLUDE LEADER)
                                    local available_bots = {}
                                    for unit_number, member in pairs(storage.creeperbots or {}) do
                                        if member.party_id == creeper.party_id and 
                                           member.entity and 
                                           member.entity.valid and
                                           not member.is_leader and  -- EXCLUDE LEADER - leader stays in formation
                                           not member.defensive_target and
                                           not member.target and  -- Don't assign if already approaching a nest
                                           not member.guard_target then
                                            table.insert(available_bots, member)
                                        end
                                    end
                                    game.print("DEBUG: Found " .. #available_bots .. " available bots to assign (leader excluded)")
                                    
                                    -- Sort by distance to enemy
                                    table.sort(available_bots, function(a, b)
                                        if not a.entity or not a.entity.valid then return false end
                                        if not b.entity or not b.entity.valid then return true end
                                        local dist_a = calculate_distance(a.entity.position, enemy.position)
                                        local dist_b = calculate_distance(b.entity.position, enemy.position)
                                        return dist_a < dist_b
                                    end)
                                    
                                    -- Assign closest bots
                                    local assigned_count = 0
                                    for i = 1, math.min(needed, #available_bots) do
                                        local bot = available_bots[i]
                                        bot.defensive_target = enemy
                                        bot.defensive_target_position = enemy.position
                                        
                                        -- Clear follow_target and autopilot so bot can move independently to attack
                                        -- Clear follow_target multiple times aggressively
                                        for i = 1, 5 do
                                            pcall(function() bot.entity.follow_target = nil end)
                                        end
                                        bot.entity.autopilot_destination = nil
                                        -- Clear all autopilot destinations
                                        local attempts = 0
                                        while bot.entity.autopilot_destinations and #bot.entity.autopilot_destinations > 0 and attempts < 20 do
                                            bot.entity.autopilot_destination = nil
                                            attempts = attempts + 1
                                        end
                                        if storage.scheduled_autopilots and storage.scheduled_autopilots[bot.unit_number] then
                                            storage.scheduled_autopilots[bot.unit_number] = nil
                                        end
                                        
                                        -- Update color to show bot is attacking
                                        update_color(bot.entity, "approaching")
                                        assigned_count = assigned_count + 1
                                        game.print("DEBUG: Assigned bot " .. bot.unit_number .. " to enemy " .. enemy.unit_number)
                                    end
                                    game.print("DEBUG: Total assigned: " .. assigned_count .. " bots to enemy " .. enemy.unit_number)
                                else
                                    game.print("DEBUG: Enemy " .. enemy.unit_number .. " already has enough bots (" .. attacking_count .. " >= " .. required_bots .. ")")
                                end
                            else
                                game.print("DEBUG: Enemy invalid or dead: valid=" .. tostring(enemy.valid) .. ", health=" .. (enemy.health or "nil"))
                            end
                        end
                    end
                end

            else
                -- No enemies detected - mark chunks within view distance as safe
                if creeper.is_leader and party then
                    local current_chunk_pos = get_chunk_pos(current_destination)
                    mark_chunks_in_view(surface, current_chunk_pos.x, current_chunk_pos.y, true, game.tick, 3)
                    --game.print("Debug: Chunks within 3 chunks of (" .. current_chunk_pos.x .. "," .. current_chunk_pos.y .. ") marked as safe (no enemies)")
                end
                --game.print("Debug: No enemies detected by unit " .. creeper.unit_number .. ", target_type: " .. (target_type or "none") .. ", target: " .. (target and "valid" or "nil") .. ", tick: " .. game.tick)
            end
            
            if creeper.render_ids and creeper.render_ids[1] then
                local id = creeper.render_ids[1]
                if type(id) == "number" then
                    local render_obj = rendering.get_object_by_id(id)
                    if render_obj and render_obj.valid then
                        --game.print("Debug: Destroying render ID " .. id .. " for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
                        render_obj.destroy()
                    else
                        --game.print("Debug: Invalid render ID " .. id .. " for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
                    end
                end
                table.remove(creeper.render_ids, 1)
            end
            creeper.last_waypoint_change = game.tick
           -- game.print("Debug: Updated last_waypoint_change for unit " .. creeper.unit_number .. " to tick " .. game.tick)
            
            local remaining_waypoints = {}
            if entity.autopilot_destinations and #entity.autopilot_destinations > 1 then
                for i = 2, #entity.autopilot_destinations do
                    table.insert(remaining_waypoints, entity.autopilot_destinations[i])
                end
            end
            --game.print("Debug: Remaining waypoints for unit " .. creeper.unit_number .. ": " .. #remaining_waypoints .. ", tick: " .. game.tick)
            
            entity.autopilot_destination = nil
            if #remaining_waypoints > 0 then
                local found_safe = false
                for _, waypoint in ipairs(remaining_waypoints) do
                    -- Only add waypoints that are not in water
                    if not is_position_on_water(surface, waypoint, 1.5) then
                        entity.add_autopilot_destination(waypoint)
                        found_safe = true
                    end
                end
                if found_safe then
                    --game.print("Debug: Leader " .. creeper.unit_number .. " moving to next waypoint, tick: " .. game.tick)
                    return true
                else
                    -- All remaining waypoints are in water, request new path
                    if creeper.is_leader then
                        local target_pos = get_unvisited_chunk(position, party)
                        if target_pos.x ~= position.x or target_pos.y ~= position.y then
                            request_multiple_paths(position, target_pos, party, surface, creeper.unit_number)
                        end
                    end
                    return false
                end
            else
                if creeper.is_leader then
                    local target_pos = get_unvisited_chunk(position, party)
                    if target_pos.x ~= position.x or target_pos.y ~= position.y then
                        -- Verify target position is not in water
                        if is_position_on_water(surface, target_pos, 1.5) then
                            local safe_target = find_safe_position_away_from_water(surface, entity, target_pos, 30)
                            if safe_target then
                                target_pos = safe_target
                            else
                                --game.print("Error: Target chunk position is in water and no safe alternative found for leader " .. creeper.unit_number)
                                return false
                            end
                        end
                        --game.print("Debug: Leader " .. creeper.unit_number .. " requested new path to (" .. target_pos.x .. "," .. target_pos.y .. "), tick: " .. game.tick)
                        request_multiple_paths(position, target_pos, party, surface, creeper.unit_number)
                    else
                        --game.print("Error: No valid chunk found for leader " .. creeper.unit_number .. ", tick: " .. game.tick)
                    end
                end
                return false
            end
        end
        
        --game.print("Debug: Unit " .. creeper.unit_number .. " still moving to waypoint, distance: " .. distance .. ", tick: " .. game.tick)
        return true
    end
end

return waypoints

