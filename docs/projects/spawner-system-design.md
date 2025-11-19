# Creeperbot Spawner System - Design Document

## Overview

The spawner system automates the production and deployment of creeperbots. Players place a spawner chest, configure requirements via a combinator, and bots are automatically spawned when all conditions are met. The system uses circuit network signals to control spawn direction and requirements.

## System Components

### 1. Creeperbot Spawner Chest
- **Base**: Reskinned steel chest with custom graphics mask
- **Name**: `creeperbot-spawner-chest`
- **Functionality**:
  - Stores creeperbot items (mk1, mk2, mk3)
  - Circuit network enabled (read mode)
  - Reads signals from connected combinator
  - Spawns bots when requirements met
  - Consumes items from inventory when spawning

### 2. Creeperbot Config Combinator
- **Base**: Constant combinator
- **Name**: `creeperbot-config-combinator`
- **Functionality**:
  - Outputs required bot counts as item signals
  - Outputs direction preference via arrow signals
  - Connected to spawner chest via circuit network

### 3. Display Panel (Optional)
- **Base**: Display panel entity
- **Functionality**:
  - Auto-spawns when spawner chest is placed (if mod setting enabled)
  - Shows usage instructions
  - Can be disabled via mod settings

## Circuit Network Signal Mapping

### Direction Signals
Arrow virtual signals control initial movement direction. The signal count value indicates the initial waypoint distance in chunks.

**Supported Directions:**
- `signal-arrow-up` → North (0°)
- `signal-arrow-down` → South (180°)
- `signal-arrow-left` → West (270°)
- `signal-arrow-right` → East (90°)
- `signal-arrow-up-right` → Northeast (45°)
- `signal-arrow-down-right` → Southeast (135°)
- `signal-arrow-down-left` → Southwest (225°)
- `signal-arrow-up-left` → Northwest (315°)

**Distance Calculation:**
- Signal count value = initial waypoint distance in chunks
- Example: `signal-arrow-down` with value `5` = move south 5 chunks initially
- Default: If no distance specified, use 10 chunks

### Required Count Signals
The combinator outputs item signals representing required bot counts:
- `creeperbot-mk1` signal count = required mk1 bots
- `creeperbot-mk2` signal count = required mk2 bots  
- `creeperbot-mk3-nuclear` signal count = required mk3 bots

**Example Configuration:**
- Combinator outputs: `creeperbot-mk1 = 10`, `creeperbot-mk2 = 5`, `creeperbot-mk3-nuclear = 1`
- Chest must contain at least: 10 mk1, 5 mk2, 1 mk3
- When final item (mk3) is added, all bots spawn

## Spawn Logic

### Condition Checking
The spawner checks conditions every 60 ticks (1 second at 60 UPS):

1. **Read Circuit Signals**:
   - Get required counts from combinator (via chest's circuit network)
   - Get direction signal (arrow + count)
   - If no direction signal, default to south (down) with 10 chunk distance

2. **Check Chest Inventory**:
   - Count actual items in chest: `creeperbot-mk1`, `creeperbot-mk2`, `creeperbot-mk3-nuclear`
   - Compare against required counts from signals

3. **Spawn Condition**:
   - All required counts must be met or exceeded
   - Example: If requirements are 10/5/1 and chest has 20/10/0, wait for mk3
   - When requirements become 20/10/1 (or more), spawn all bots

### Spawn Process

When all requirements are met:

1. **Calculate Spawn Positions**:
   - For each bot to spawn, generate random position within 3-tile radius of chest
   - Check position is valid (not on water, not colliding)
   - Retry up to 5 times if position invalid

2. **Spawn Bots**:
   - Create entities using `surface.create_entity({name = bot_name, position = spawn_pos})`
   - Spawn in order: mk1s first, then mk2s, then mk3s
   - Create smoke effect at each spawn position: `surface.create_entity({name = "smoke", position = spawn_pos})`
   - Small delay between spawns (2-3 ticks) for visual effect

3. **Consume Items**:
   - Remove exact required count from chest inventory
   - Example: If spawned 10 mk1, remove 10 mk1 items
   - Use `inventory.remove({name = item_name, count = amount})`

4. **Register Bots**:
   - Bots are automatically registered via `on_built_entity` event
   - They enter "waking" state as normal
   - They will form parties via existing grouping logic

5. **Set Initial Direction**:
   - Calculate waypoint position based on direction signal
   - Formula: `waypoint = chest_position + (direction_vector * chunk_size * distance)`
   - Chunk size = 32 tiles
   - Store waypoint in party data for leader to use

## Bot Behavior After Spawning

### Initial State
- Bots spawn in "waking" state (standard behavior)
- They will naturally transition to "grouping" state
- Party formation happens automatically via existing `assign_to_party()` logic

### Direction Integration
The spawner sets an initial waypoint for the party:

1. **Party Leader Selection**:
   - First bot to reach "grouping" state becomes leader
   - Or highest tier bot (mk3 > mk2 > mk1) if multiple reach grouping simultaneously

2. **Waypoint Assignment**:
   - Store initial waypoint in party data: `party.initial_waypoint = {x, y}`
   - When leader has no waypoint, use `initial_waypoint`
   - Leader moves toward waypoint using existing pathfinding system

3. **Waypoint Behavior**:
   - Once initial waypoint reached, bots continue normal scouting behavior
   - They search for enemies in unvisited chunks
   - Direction preference only affects initial movement

### Party Formation
- Bots spawned together will naturally form a party (within 50-tile radius)
- Party ID assigned via existing `assign_to_party()` function
- All bots in party share the same initial waypoint direction

## Integration Points

### Existing Systems

1. **Creeperbot Manager** (`scripts/creeperbot_manager.lua`):
   - `register_creeperbot()` - Called automatically when bots spawn
   - `assign_to_party()` - Forms parties from spawned bots
   - No changes needed, works as-is

2. **Waypoint System** (`scripts/behavior/waypoints.lua`):
   - `get_unvisited_chunk()` - Used for scouting
   - Need to add: Check for `party.initial_waypoint` before using unvisited chunk logic
   - If `initial_waypoint` exists and not reached, use it instead

3. **State Machine** (`scripts/behavior/state_machine.lua`):
   - Bots follow normal state transitions: waking → grouping → scouting → attacking
   - Initial waypoint only affects grouping/scouting phase

### Storage Structure

```lua
storage.spawners = {
    [unit_number] = {
        chest = entity,              -- Spawner chest entity
        combinator = entity,          -- Config combinator entity (optional, can be nil)
        panel = entity,              -- Display panel entity (optional)
        last_check_tick = tick,      -- Last condition check tick
        requirements = {              -- Cached requirements
            mk1 = 0,
            mk2 = 0,
            mk3 = 0
        },
        direction = {                 -- Cached direction
            signal = "signal-arrow-down",
            distance = 10
        },
        initial_waypoint = nil        -- Calculated waypoint position
    }
}
```

### Party Data Extension

```lua
party = {
    -- ... existing fields ...
    initial_waypoint = {x, y},      -- Set by spawner, used by leader
    initial_waypoint_reached = false -- Track if waypoint was reached
}
```

## Event Handlers

### Required Events

1. **on_built_entity**:
   - Detect spawner chest placement
   - Register spawner in storage
   - Optionally spawn display panel (if mod setting enabled)
   - Find and link combinator if nearby

2. **on_entity_died**:
   - Clean up destroyed spawners
   - Remove from storage
   - Destroy associated display panel

3. **on_tick**:
   - Check spawn conditions every 60 ticks
   - Only check spawners that are valid and have circuit network

4. **on_trigger_created_entity** (optional):
   - Could be used if we want to detect bots spawned via other means
   - Currently not needed as `on_built_entity` handles spawned bots

## Technical Implementation Details

### Spawn Position Calculation

```lua
function find_spawn_position(chest, attempts)
    local chest_pos = chest.position
    local surface = chest.surface
    local random = game.create_random_generator()
    
    for i = 1, attempts do
        local angle = math.rad(random(0, 360))
        local distance = random(1, 3)  -- 1-3 tiles from chest
        local pos = {
            x = chest_pos.x + math.cos(angle) * distance,
            y = chest_pos.y + math.sin(angle) * distance
        }
        
        -- Check if position is valid
        if not is_position_on_water(surface, pos, 2.5) then
            local can_place = surface.can_place_entity{
                name = "creeperbot-mk1",  -- Check with smallest bot
                position = pos
            }
            if can_place then
                return pos
            end
        end
    end
    return nil  -- Fallback to chest position
end
```

### Direction to Waypoint Calculation

```lua
function calculate_initial_waypoint(chest_pos, direction_signal, distance)
    local angles = {
        ["signal-arrow-up"] = 0,
        ["signal-arrow-up-right"] = math.pi / 4,
        ["signal-arrow-right"] = math.pi / 2,
        ["signal-arrow-down-right"] = 3 * math.pi / 4,
        ["signal-arrow-down"] = math.pi,
        ["signal-arrow-down-left"] = 5 * math.pi / 4,
        ["signal-arrow-left"] = 3 * math.pi / 2,
        ["signal-arrow-up-left"] = 7 * math.pi / 4
    }
    
    local angle = angles[direction_signal] or math.pi  -- Default south
    local chunk_size = 32
    local total_distance = chunk_size * distance
    
    return {
        x = chest_pos.x + math.cos(angle) * total_distance,
        y = chest_pos.y + math.sin(angle) * total_distance
    }
end
```

### Circuit Signal Reading

```lua
function read_spawner_signals(chest)
    local control_behavior = chest.get_control_behavior()
    if not control_behavior then return nil, nil end
    
    local circuit_network = control_behavior.get_circuit_network(defines.wire_type.red)
    if not circuit_network then
        circuit_network = control_behavior.get_circuit_network(defines.wire_type.green)
    end
    if not circuit_network then return nil, nil end
    
    local signals = circuit_network.signals or {}
    local requirements = {mk1 = 0, mk2 = 0, mk3 = 0}
    local direction = {signal = "signal-arrow-down", distance = 10}
    
    -- Read required counts
    for _, signal in pairs(signals) do
        if signal.signal.type == "item" then
            if signal.signal.name == "creeperbot-mk1" then
                requirements.mk1 = signal.count
            elseif signal.signal.name == "creeperbot-mk2" then
                requirements.mk2 = signal.count
            elseif signal.signal.name == "creeperbot-mk3-nuclear" then
                requirements.mk3 = signal.count
            end
        elseif signal.signal.type == "virtual" then
            -- Check for arrow signals
            local arrow_signals = {
                "signal-arrow-up", "signal-arrow-down", "signal-arrow-left", "signal-arrow-right",
                "signal-arrow-up-right", "signal-arrow-down-right", "signal-arrow-down-left", "signal-arrow-up-left"
            }
            for _, arrow in ipairs(arrow_signals) do
                if signal.signal.name == arrow then
                    direction.signal = arrow
                    direction.distance = math.max(1, signal.count)  -- Minimum 1 chunk
                    break
                end
            end
        end
    end
    
    return requirements, direction
end
```

## Mod Settings

### Setting: `creeperbot-spawner-show-panel`
- **Type**: `bool-setting`
- **Default**: `true`
- **Description**: "Automatically show instruction panel when placing spawner chest"
- **Effect**: Controls whether display panel auto-spawns with chest

## Display Panel Content

### Instructions Text

```
Creeperbot Spawner Configuration

1. Connect a constant combinator to this chest via circuit network

2. Set required bot counts in combinator:
   - creeperbot-mk1 signal = number of mk1 bots needed
   - creeperbot-mk2 signal = number of mk2 bots needed
   - creeperbot-mk3-nuclear signal = number of mk3 bots needed

3. Set direction preference (optional):
   - Use arrow virtual signals (up, down, left, right, etc.)
   - Signal count = initial waypoint distance in chunks
   - Example: down-arrow with value 5 = move south 5 chunks

4. Fill chest with required bot items

5. When all requirements are met, bots will spawn automatically

Note: Items are consumed when bots spawn. Use inserters to refill.
```

## Localization

### Entity Names
- `entity-name.creeperbot-spawner-chest` = "Creeperbot Spawner Chest"
- `entity-name.creeperbot-config-combinator` = "Creeperbot Config Combinator"

### Descriptions
- `entity-description.creeperbot-spawner-chest` = "Automatically spawns creeperbots when configured requirements are met. Connect a combinator to set requirements and direction."
- `entity-description.creeperbot-config-combinator` = "Outputs signals for creeperbot spawner configuration. Set bot counts and direction preferences."

### Mod Setting
- `mod-setting-name.creeperbot-spawner-show-panel` = "Show spawner instruction panel"
- `mod-setting-description.creeperbot-spawner-show-panel` = "Automatically display instruction panel when placing a spawner chest"

## Future Enhancements (Not in Initial Implementation)

1. **Multiple Spawn Patterns**: Configurable spawn formations (line, circle, etc.)
2. **Spawn Delays**: Configurable delay between bot spawns
3. **Advanced Filtering**: Filter bots by tier for different spawn groups
4. **Spawn Limits**: Maximum bots per spawner, cooldown periods
5. **Visual Indicators**: LED lights showing spawn readiness
6. **Statistics**: Track bots spawned, success rates, etc.

## Testing Considerations

1. **Edge Cases**:
   - Chest destroyed during spawn
   - Combinator disconnected
   - Invalid spawn positions (all positions blocked)
   - Water near spawner
   - Multiple spawners spawning simultaneously

2. **Performance**:
   - Check interval (60 ticks) should be sufficient
   - Limit spawner checks to active spawners only
   - Cache signal reads to avoid repeated circuit network queries

3. **Integration**:
   - Verify bots form parties correctly
   - Verify waypoint system respects initial direction
   - Verify item consumption works correctly
   - Verify smoke effects render properly

