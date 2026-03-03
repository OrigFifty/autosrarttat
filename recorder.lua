local Globals = getgenv()

-- [DEBUG TOGGLE]
Globals.__TDS_DEBUG = true 

return function(ctx)
    if not ctx or not ctx.Window then
        return
    end

    local Window = ctx.Window
    local replicated_storage = ctx.ReplicatedStorage or game:GetService("ReplicatedStorage")
    local http_service = ctx.HttpService or game:GetService("HttpService")
    local game_state = ctx.GameState or "UNKNOWN"
    local workspace_ref = ctx.workspace or workspace

    local players_service = game:GetService("Players")
    local local_player = ctx.LocalPlayer or players_service.LocalPlayer or players_service.PlayerAdded:Wait()

    Globals.record_strat = Globals.record_strat or false

    local spawned_towers = {}
    local tower_count = 0
    local Recorder
    local has_hook = type(hookmetamethod) == "function"

    -- [DEBUG LOGGER]
    local function debug_warn(msg)
        if Globals.__TDS_DEBUG then
            warn("[TDS-DEBUG] " .. tostring(msg))
        end
    end

    local function record_action(command_str)
        if not Globals.record_strat then return end
        if appendfile then
            appendfile("Strat.txt", command_str .. "\n")
        end
    end

    local function log_line(message)
        if Recorder and Recorder.Log then
            Recorder:Log(message)
        end
    end

    local function resolve_tower_index(tower)
        if typeof(tower) ~= "Instance" then return nil end
        if spawned_towers[tower] then return spawned_towers[tower] end

        local current = tower.Parent
        while current do
            if spawned_towers[current] then
                return spawned_towers[current]
            end
            current = current.Parent
        end
        return nil
    end

    local function sync_existing_towers()
        if game_state ~= "GAME" then return end
        local towers_folder = workspace_ref:FindFirstChild("Towers")
        if not towers_folder then return end

        table.clear(spawned_towers)
        tower_count = 0

        for _, tower in ipairs(towers_folder:GetChildren()) do
            local replicator = tower:FindFirstChild("TowerReplicator")
            if replicator and replicator:GetAttribute("OwnerId") == local_player.UserId then
                tower_count += 1
                spawned_towers[tower] = tower_count
            end
        end
    end

    local function num_to_str(n)
        if type(n) ~= "number" then return tostring(n) end
        if n == math.huge then return "math.huge" end
        if n == -math.huge then return "-math.huge" end
        if n ~= n then return "0/0" end
        return tostring(n)
    end

    local serialize_value, serialize_value_raw, serialize_table, serialize_table_raw

    local function format_key(key)
        if type(key) == "string" and key:match("^[_%a][_%w]*$") then
            return "[" .. string.format("%q", key) .. "]"
        end
        if type(key) == "number" then
            return "[" .. num_to_str(key) .. "]"
        end
        return "[" .. serialize_value(key) .. "]"
    end

    local function is_array(tbl)
        local max_idx = 0
        for k, _ in pairs(tbl) do
            if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false, 0 end
            if k > max_idx then max_idx = k end
        end
        return true, max_idx
    end

    serialize_value = function(v, depth)
        depth = depth or 0
        if depth > 4 then return "nil" end
        local t = typeof(v)
        if t == "string" then return string.format("%q", v)
        elseif t == "number" then return num_to_str(v)
        elseif t == "boolean" then return tostring(v)
        elseif t == "Vector3" then return string.format("Vector3.new(%s, %s, %s)", num_to_str(v.X), num_to_str(v.Y), num_to_str(v.Z))
        elseif t == "CFrame" then
            local comps = {v:GetComponents()}
            local parts = {}
            for i = 1, #comps do parts[i] = num_to_str(comps[i]) end
            return "CFrame.new(" .. table.concat(parts, ", ") .. ")"
        elseif t == "Instance" then
            local idx = resolve_tower_index(v)
            if idx then return tostring(idx) end
            return "nil"
        elseif t == "table" then return serialize_table(v, depth + 1)
        end
        return "nil"
    end

    serialize_value_raw = function(v, depth)
        depth = depth or 0
        if depth > 4 then return "nil" end
        local t = typeof(v)
        if t == "string" then return string.format("%q", v)
        elseif t == "number" then return num_to_str(v)
        elseif t == "boolean" then return tostring(v)
        elseif t == "Vector3" then return string.format("Vector3.new(%s, %s, %s)", num_to_str(v.X), num_to_str(v.Y), num_to_str(v.Z))
        elseif t == "CFrame" then
            local comps = {v:GetComponents()}
            local parts = {}
            for i = 1, #comps do parts[i] = num_to_str(comps[i]) end
            return "CFrame.new(" .. table.concat(parts, ", ") .. ")"
        elseif t == "Instance" then
            local success, full = pcall(function() return v:GetFullName() end)
            if success and type(full) == "string" and full ~= "" then
                local parts = string.split(full, ".")
                local expr = 'game:GetService("' .. parts[1] .. '")'
                for i = 2, #parts do
                    local part = parts[i]
                    if part:match("^[_%a][_%w]*$") then expr = expr .. "." .. part
                    else expr = expr .. "[" .. string.format("%q", part) .. "]" end
                end
                return expr
            else
                local safe_name, safe_class = "Unknown", "Instance"
                pcall(function() safe_name = v.Name end)
                pcall(function() safe_class = v.ClassName end)
                return string.format('"%s_Fingerprint_%s"', safe_class, safe_name)
            end
        elseif t == "table" then return serialize_table_raw(v, depth + 1)
        end
        return "nil"
    end

    serialize_table = function(tbl, depth)
        local is_arr, max_idx = is_array(tbl)
        local parts = {}
        if is_arr then
            for i = 1, max_idx do parts[i] = serialize_value(tbl[i], depth) end
        else
            local keys = {}
            for k, _ in pairs(tbl) do table.insert(keys, k) end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                table.insert(parts, format_key(k) .. " = " .. serialize_value(tbl[k], depth))
            end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end

    serialize_table_raw = function(tbl, depth)
        local is_arr, max_idx = is_array(tbl)
        local parts = {}
        if is_arr then
            for i = 1, max_idx do parts[i] = serialize_value_raw(tbl[i], depth) end
        else
            local keys = {}
            for k, _ in pairs(tbl) do table.insert(keys, k) end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                local key_str
                if type(k) == "string" and k:match("^[_%a][_%w]*$") then key_str = k
                elseif type(k) == "number" then key_str = "[" .. num_to_str(k) .. "]"
                else key_str = "[" .. serialize_value_raw(k, depth) .. "]" end
                table.insert(parts, key_str .. " = " .. serialize_value_raw(tbl[k], depth))
            end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end

    local function build_remote_call(remote, method, args)
        if typeof(remote) ~= "Instance" then return nil end
        local success, full = pcall(function() return remote:GetFullName() end)
        if not success or type(full) ~= "string" or full == "" then return nil end

        local parts = string.split(full, ".")
        local expr = 'game:GetService("' .. parts[1] .. '")'
        for i = 2, #parts do
            local part = parts[i]
            if part:match("^[_%a][_%w]*$") then expr = expr .. "." .. part
            else expr = expr .. "[" .. string.format("%q", part) .. "]" end
        end

        local arg_parts = {}
        for i = 1, #args do arg_parts[i] = serialize_value_raw(args[i]) end
        return expr .. ":" .. method .. "(" .. table.concat(arg_parts, ", ") .. ")"
    end

    local function is_consumable_call(remote, args)
        local first = args[1]
        if type(first) == "string" then
            local lower = first:lower()
            if lower:find("consum") then return true end
            if lower:find("item") and type(args[2]) == "string" and tostring(args[2]):lower():find("use") then return true end
        end
        if typeof(remote) == "Instance" then
            local success, full = pcall(function() return remote:GetFullName() end)
            if success and type(full) == "string" then
                local lower = full:lower()
                if lower:find("consum") or (lower:find("item") and lower:find("use")) then return true end
            end
        end
        return false
    end

    -- [DEBUG UTILITY] Safely dump arguments without crashing Identity 2
    local function dump_args_safely(args)
        local out = {}
        for i, v in pairs(args) do
            local success, res = pcall(function()
                if typeof(v) == "Instance" then return "Instance("..v.ClassName..")" end
                if type(v) == "table" then return "Table(size:"..#v..")" end
                return tostring(v)
            end)
            table.insert(out, "["..tostring(i).."] = " .. (success and res or "ERR"))
        end
        return table.concat(out, " | ")
    end

    local function handle_namecall(remote, method, args)
        if not Globals.record_strat then return end
        if method ~= "InvokeServer" and method ~= "FireServer" then return end

        local a1 = args[1]
        local a2 = args[2]
        local a3 = args[3]
        local a4 = args[4]
        local a5 = args[5]

        -- [HEAVY DEBUGGING] - Print every single relevant remote call to F9 console
        if type(a1) == "string" and (a1 == "Troops" or a1 == "Streaming" or a1 == "Hotbar" or a1 == "Inventory") then
            debug_warn("Intercepted: " .. method .. " | Arg1: " .. a1 .. " | Arg2: " .. tostring(a2))
            debug_warn("Raw Args: " .. dump_args_safely(args))
        end

        local handled = false

        if method == "InvokeServer" and a1 == "Troops" and a2 == "Place" then
            debug_warn("-> MATCHED PLACEMENT LOGIC")
            local tower_name = args[3]
            local payload = args[4]
            if type(tower_name) == "string" and type(payload) == "table" then
                local pos = payload.Position
                if pos and typeof(pos) == "Vector3" then
                    local cmd = string.format('TDS:Place("%s", %s, %s, %s)', tower_name, num_to_str(pos.X), num_to_str(pos.Y), num_to_str(pos.Z))
                    record_line(cmd)
                    log_line("Placed Network: " .. tower_name)
                    debug_warn("-> SUCCESSFULLY RECORDED PLACE")
                    handled = true
                    return
                end
            end
        end

        if method == "FireServer" and a1 == "Streaming" and a2 == "SelectTower" then
            debug_warn("-> MATCHED SELECTION LOGIC")
            local target_tower = args[3]
            local idx = resolve_tower_index(target_tower)
            if idx then
                record_line(string.format("-- Selected Tower %d", idx))
                log_line("Selected: " .. idx)
                handled = true
                return
            else
                debug_warn("-> FAILED: Could not resolve tower index for selection.")
            end
        end

        if method == "FireServer" and a1 == "Hotbar" and a2 == "Click" then
            local slot = args[3]
            record_line(string.format("-- Clicked Hotbar Slot %s", tostring(slot)))
            log_line("Hotbar: " .. tostring(slot))
            handled = true
            return
        end

        if a1 == "Troops" and a2 == "Abilities" and a3 == "Activate" then
            if type(a4) == "table" then
                local idx = resolve_tower_index(a4.Troop)
                local name = a4.Name
                if idx and type(name) == "string" then
                    local data = a4.Data
                    local cmd
                    if data == nil or (type(data) == "table" and next(data) == nil) then
                        cmd = string.format("TDS:Ability(%d, %s)", idx, string.format("%q", name))
                    else
                        cmd = string.format("TDS:Ability(%d, %s, %s)", idx, string.format("%q", name), serialize_value(data))
                    end
                    record_line(cmd)
                    log_line("Ability: " .. name .. " (Index: " .. idx .. ")")
                    handled = true
                    return
                end
            end
        end

        if a1 == "Troops" and a2 == "TowerServerEvent" and a3 == "ToggleSelectedTower" then
            debug_warn("-> MATCHED MEDIC LOGIC")
            local idx = resolve_tower_index(a4)
            local target_idx = resolve_tower_index(a5)
            if idx and target_idx then
                local cmd = string.format("TDS:MedicSelect(%d, %d)", idx, target_idx)
                record_line(cmd)
                log_line("Medic: " .. idx .. " -> " .. target_idx)
                handled = true
                return
            else
                debug_warn("-> FAILED: Could not resolve Medic indexes. Medic: " .. tostring(idx) .. " Target: " .. tostring(target_idx))
            end
        end
    end

    local RecorderTab = Window:Tab({Title = "Recorder", Icon = "camera"}) do
        Recorder = RecorderTab:CreateLogger({
            Title = "RECORDER:",
            Size = UDim2.new(0, 330, 0, 230)
        })

        if has_hook then
            Globals.__tds_recorder_handler = function(remote, method, args)
                handle_namecall(remote, method, args)
            end

            if not Globals.__tds_recorder_hooked then
                Globals.__tds_recorder_hooked = true
                local original
                original = hookmetamethod(game, "__namecall", function(self, ...)
                    local method = getnamecallmethod and getnamecallmethod() or nil
                    local args = {...}
                    local results = table.pack(original(self, ...))
                    
                    local handler = Globals.__tds_recorder_handler
                    if handler and method then
                        task.spawn(function()
                            -- [DEBUG] Catch if the handler itself fails
                            local success, err = pcall(handler, self, method, args)
                            if not success then
                                warn("[TDS-CRITICAL ERROR] Handler crashed: " .. tostring(err))
                            end
                        end)
                    end
                    return table.unpack(results, 1, results.n)
                end)
                debug_warn("Hook successfully attached to __namecall")
            end
        end

        RecorderTab:Button({
            Title = "START",
            Desc = "",
            Callback = function()
                Recorder:Clear()
                Recorder:Log("Recorder started")
                debug_warn("START BUTTON PRESSED - RECORDING ENABLED")

                local current_mode = "Unknown"
                local current_map = "Unknown"
                local state_folder = replicated_storage:FindFirstChild("State")
                if state_folder then
                    current_mode = state_folder.Difficulty.Value
                    current_map = state_folder.Map.Value
                end

                local tower1, tower2, tower3, tower4, tower5 = "None", "None", "None", "None", "None"
                local current_modifiers = "" 
                local state_replicators = replicated_storage:FindFirstChild("StateReplicators")

                if state_replicators then
                    for _, folder in ipairs(state_replicators:GetChildren()) do
                        if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == local_player.UserId then
                            local equipped = folder:GetAttribute("EquippedTowers")
                            if type(equipped) == "string" then
                                local cleaned_json = equipped:match("%[.*%]") 
                                pcall(function()
                                    local tower_table = http_service:JSONDecode(cleaned_json)
                                    tower1 = tower_table[1] or "None"
                                    tower2 = tower_table[2] or "None"
                                    tower3 = tower_table[3] or "None"
                                    tower4 = tower_table[4] or "None"
                                    tower5 = tower_table[5] or "None"
                                end)
                            end
                        end
                    end
                end

                sync_existing_towers()
                Globals.record_strat = true

                if writefile then 
                    local config_header = string.format([[
local TDS = loadstring(game:HttpGet("https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua"))()

TDS:Loadout("%s", "%s", "%s", "%s", "%s")
TDS:Mode("%s")
TDS:GameInfo("%s", {%s})

]], tower1, tower2, tower3, tower4, tower5, current_mode, current_map, current_modifiers)
                    pcall(function() writefile("Strat.txt", config_header) end)
                end

                Window:Notify({
                    Title = "ADS",
                    Desc = "Recorder has started, check F9 Console for logs.",
                    Time = 3,
                    Type = "normal"
                })
            end
        })

        RecorderTab:Button({
            Title = "STOP",
            Desc = "",
            Callback = function()
                Globals.record_strat = false
                Recorder:Clear()
                Recorder:Log("Strategy saved.")
                debug_warn("STOP BUTTON PRESSED - RECORDING DISABLED")
            end
        })

        if game_state == "GAME" then
            local towers_folder = workspace_ref:WaitForChild("Towers", 5)

            towers_folder.ChildAdded:Connect(function(tower)
                if not Globals.record_strat then return end
                local replicator = tower:WaitForChild("TowerReplicator", 5)
                if not replicator then return end
                local owner_id = replicator:GetAttribute("OwnerId")
                if owner_id and owner_id ~= local_player.UserId then return end

                tower_count = tower_count + 1
                local my_index = tower_count
                spawned_towers[tower] = my_index
                debug_warn("WORKSPACE ADDED: Assigned Index " .. my_index .. " to " .. tower.Name)
            end)
        end
    end
end
