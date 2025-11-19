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
       -- game.print("Debug: Current destination for unit " .. creeper.unit_number .. ": (" .. current_destination.x .. "," .. current_destination.y .. "), tick: " .. game.tick)
        
        local distance = calculate_distance(position, current_destination)
        --game.print("Debug: Distance to current destination for unit " .. creeper.unit_number .. ": " .. distance .. ", tick: " .. game.tick)
        
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
        
        local render_obj = rendering.draw_line({
            color = {r = 1, g = 0, b = 0, a = 1},
            width = 2,
            from = position,
            to = current_destination,
            surface = surface,
            time_to_live = 600,
            draw_on_ground = false
        })
        
        if render_obj and render_obj.valid then
            --game.print("Debug: Created new dynamic line ID " .. render_obj.id .. " for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
            creeper.dynamic_line_id = render_obj.id
        else
            --game.print("Debug: Failed to create dynamic line for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
        end
        
        local threshold = 3
        if distance <= threshold and (creeper.last_waypoint_change or 0) + 20 < game.tick then
           -- game.print("Debug: Leader " .. creeper.unit_number .. " reached waypoint at (" .. current_destination.x .. "," .. current_destination.y .. ") on tick " .. game.tick)
            
           -- game.print("Debug: Scanning for enemies for unit " .. creeper.unit_number .. ", tick: " .. game.tick)
            local target, target_type = behavior_utils.scan_for_enemies(position, surface, config.tier_configs[entity.name].max_targeting)
            if target and (target_type == "unit" or target_type == "nest") then
                --game.print("Debug: Leader " .. creeper.unit_number .. " detected " .. target_type .. " at (" .. target.position.x .. "," .. target.position.y .. "), transitioning party to preparing_to_attack, tick: " .. game.tick)
                for unit_number, member in pairs(storage.creeperbots or {}) do
                    if member.party_id == creeper.party_id and member.entity and member.entity.valid then
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
                return false
            else
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
                for _, waypoint in ipairs(remaining_waypoints) do
                    entity.add_autopilot_destination(waypoint)
                end
                --game.print("Debug: Leader " .. creeper.unit_number .. " moving to next waypoint, tick: " .. game.tick)
                return true
            else
                if creeper.is_leader then
                    local target_pos = get_unvisited_chunk(position, party)
                    if target_pos.x ~= position.x or target_pos.y ~= position.y then
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

