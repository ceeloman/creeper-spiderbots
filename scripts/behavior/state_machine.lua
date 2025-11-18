-- Creeperbots - State Machine Dispatcher
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

local waking_state = require "scripts.behavior.states.waking"
local grouping_state = require "scripts.behavior.states.grouping"
local scouting_state = require "scripts.behavior.states.scouting"
local approaching_state = require "scripts.behavior.states.approaching"
local preparing_to_attack_state = require "scripts.behavior.states.preparing_to_attack"
local distractor_state = require "scripts.behavior.states.distractor"
local exploding_state = require "scripts.behavior.states.exploding"
local remote_controlled_state = require "scripts.behavior.states.remote_controlled"
local waypoints = require "scripts.behavior.waypoints"

-- Main update function acting as a state machine dispatcher
function update_creeperbot(creeper, event)
    local entity = creeper.entity
    local position = entity.position
    local surface = entity.surface
    local tier = creeper.tier
    local party = creeper.party_id and storage.parties[creeper.party_id] or nil

    local has_valid_path = false

    local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] or {}

    if creeper.state == "waking" then
        waking_state.handle_waking_state(creeper, event, position, entity, surface, tier)
        local queue = storage.scheduled_autopilots and storage.scheduled_autopilots[entity.unit_number] or {}
        if not queue.destination and not entity.autopilot_destination and not creeper.waking_initialized then
            local random = game.create_random_generator()
            local roll = random(1, 100)
            if roll > 75 then
                storage.leader_candidates = storage.leader_candidates or {}
                storage.leader_candidates[entity.unit_number] = {creeper = creeper, position = position}
                --game.print("CreeperBot " .. entity.unit_number .. " is a leader candidate (roll: " .. roll .. ")")
            else
                local party_id = assign_to_party(entity)
                local new_party = storage.parties[party_id]
                if new_party and new_party.grouping_leader then
                    creeper.party_id = party_id
                    creeper.state = "grouping"
                    update_color(entity, "grouping")
                    new_party.last_join_tick = game.tick
                    --game.print("CreeperBot " .. entity.unit_number .. " joined group, leader: " .. new_party.grouping_leader)
                else
                    --game.print("CreeperBot " .. entity.unit_number .. " failed to join group, no leader found")
                end
            end
        end
    elseif creeper.state == "grouping" then
        grouping_state.handle_grouping_state(creeper, event, position, entity, surface, tier, party)
    elseif creeper.state == "scouting" or creeper.state == "guard" and not creeper.is_leader then
        scouting_state.handle_scouting_state(creeper, event, position, entity, party)
    elseif creeper.state == "scouting" and creeper.is_leader then
        scouting_state.handle_scouting_state(creeper, event, position, entity, party, waypoints.process_waypoints(creeper))
    elseif creeper.state == "approaching" then
        approaching_state.handle_approaching_state(creeper, event, position, entity, surface, tier, party)
    elseif creeper.state == "preparing_to_attack" then
        preparing_to_attack_state.handle_preparing_to_attack_state(creeper, event, position, entity, surface, tier, party)
    elseif creeper.state == "exploding" then
        -- Get the full tier config from entity name, not just the tier number
        local config = require "scripts.behavior.config"
        local tier_config = config.tier_configs[entity.name] or config.tier_configs["creeperbot-mk1"]
        exploding_state.handle_exploding_state(creeper, event, position, entity, surface, tier_config, party)
    end

    if party then
        party.pending_path_requests = party.pending_path_requests or {}
    end
end

