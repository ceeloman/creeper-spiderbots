-- Creeperbots - Behavior script
-- Defines tier-specific behaviors and state machine logic
-- Extension mod based on SpiderBots © 2023-2025 by asher_sky (licensed under CC BY-NC-SA 4.0)
-- This derivative work is also licensed under CC BY-NC-SA 4.0

-- Load all behavior modules
local config = require "scripts.behavior.config"
local behavior_utils = require "scripts.behavior.utils"
local state_machine = require "scripts.behavior.state_machine"

-- Re-export tier_configs for backward compatibility
tier_configs = config.tier_configs

-- Re-export functions that other files depend on
get_creeperbot_tier = config.get_creeperbot_tier
get_guard_positions = config.get_guard_positions
log_to_file = behavior_utils.log_to_file
scan_for_enemies = behavior_utils.scan_for_enemies
broadcast_target = behavior_utils.broadcast_target

-- Re-export main update function
update_creeperbot = state_machine.update_creeperbot
