local Globals = getgenv()

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

    -- [FIX: Safe Dictionary Formatting]
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
            -- [FIX: The GetFullName Identity 2 Kill Zone Patch]
            local success, full = pcall(function() return v:GetFullName() end)
            
            if success and type(full) == "string" and full ~= "" then
                local parts = string.split(full, ".")
                local expr = 'game:GetService("' .. parts[1] .. '")'
                for i = 2, #parts do
                    local part = parts[i]
                    if part:match("^[_%a][_%w]*$") then
                        expr = expr .. "." .. part
                    else
                        expr = expr .. "[" .. string.format("%q", part) .. "]"
                    end
                end
                return expr
            else
                -- Fallback Fingerprint for protected instances
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

    -- [FIX: Safe Hooking for build_remote_call]
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

    local function record_line(line, message)
        record_action(line)
        if message then log_line(message) end
    end

    local function handle_namecall(remote, method, args)
        if not Globals.record_strat then return end
        if method ~= "InvokeServer" and method ~= "FireServer" then return end

        local handled = false
        local a1 = args[1]
        local a2 = args[2]
        local a3 = args[3]
        local a4 = args[4]
        local a5 = args[5]

        -- [FIX: 1. Confirmed Placement Pattern]
        if method == "InvokeServer" and a1 == "Troops" and a2 == "Place" then
            local tower_name = args[3]
            local payload = args[4]
            if type(tower_name) == "string" and type(payload) == "table" then
                local pos = payload.Position
                if pos and typeof(pos) == "Vector3" then
                    local cmd = string.format('TDS:Place("%s", %s, %s, %s)', tower_name, num_to_str(pos.X), num_to_str(pos.Y), num_to_str(pos.Z))
                    record_line(cmd, "Placed Network: " .. tower_name)
                    handled = true
                    return
                end
            end
        end

        -- [FIX: 2. Confirmed Selection Pattern]
        if method == "FireServer" and a1 == "Streaming" and a2 == "SelectTower" then
            local target_tower = args[3]
            local idx = resolve_tower_index(target_tower)
            if idx then
                record_line(string.format("-- Selected Tower %d", idx), "Selected: " .. idx)
                handled = true
                return
            end
        end

        -- [FIX: 3. Confirmed Hotbar Pattern]
        if method == "FireServer" and a1 == "Hotbar" and a2 == "Click" then
            local slot = args[3]
            record_line(string.format("-- Clicked Hotbar Slot %s", tostring(slot)), "Hotbar: " .. tostring(slot))
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
                    record_line(cmd, "Ability: " .. name .. " (Index: " .. idx .. ")")
                    handled = true
                    return
                end
            end
        end

        if a1 == "Troops" and a2 == "Target" and a3 == "Set" then
            if type(a4) == "table" then
                local idx = resolve_tower_index(a4.Troop)
                local target_type = a4.Target
                if idx and type(target_type) == "string" then
                    local cmd = string.format("TDS:SetTarget(%d, %s)", idx, string.format("%q", target_type))
                    record_line(cmd, "Target: " .. idx .. " -> " .. target_type)
                    handled = true
                    return
                end
            end
        end

        if a1 == "Troops" and a2 == "Option" then
            local payload = type(a3) == "table" and a3 or (type(a4) == "table" and a4)
            if payload then
                local idx = resolve_tower_index(payload.Troop)
                local opt_name = payload.Name or payload.Option or payload.Key or payload.Track or (payload["Unit 1"] and "Unit 1") or (payload["Unit 2"] and "Unit 2") or (payload["Unit 3"] and "Unit 3") or (payload.Trap and "Trap")
                local opt_val = payload.Value or payload.Val or payload["Unit 1"] or payload["Unit 2"] or payload["Unit 3"] or payload.Trap
                if idx and type(opt_name) == "string" then
                    local cmd = string.format("TDS:SetOption(%d, %s, %s)", idx, string.format("%q", opt_name), serialize_value(opt_val))
                    record_line(cmd, "Option: " .. idx .. " " .. opt_name .. " = " .. tostring(opt_val))
                    handled = true
                    return
                end
            end
        end

        if a1 == "Troops" and a2 == "TowerServerEvent" and a3 == "ToggleSelectedTower" then
            local idx = resolve_tower_index(a4)
            local target_idx = resolve_tower_index(a5)
            if idx and target_idx then
                local cmd = string.format("TDS:MedicSelect(%d, %d)", idx, target_idx)
                record_line(cmd, "Medic: " .. idx .. " -> " .. target_idx)
                handled = true
                return
            end
        end

        if a1 == "Voting" and a2 == "Skip" then
            record_line("TDS:VoteSkip()", "Voted to skip wave")
            handled = true
            return
        end

        if a1 == "Inventory" and a2 == "Equip" and a3 == "tower" then
            if type(args[4]) == "string" then
                local tower_name = args[4]
                local cmd = string.format("TDS:Equip(%s)", string.format("%q", tower_name))
                record_line(cmd, "Equipped: " .. tower_name)
            end
            handled = true
            return
        end

        if a1 == "Inventory" and a2 == "Unequip" and a3 == "tower" then
            if type(args[4]) == "string" then
                local tower_name = args[4]
                local cmd = string.format("TDS:Unequip(%s)", string.format("%q", tower_name))
                record_line(cmd, "Unequipped: " .. tower_name)
            end
            handled = true
            return
        end

        if is_consumable_call(remote, args) then
            local raw_call = build_remote_call(remote, method, args)
            if raw_call then
                record_line(raw_call, "Consumable used")
            end
            handled = true
            return
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
                        -- Safe, passive hook (Does not attempt to elevate identity)
                        task.spawn(function()
                            pcall(handler, self, method, args)
                        end)
                    end
                    return table.unpack(results, 1, results.n)
                end)
            end
        end

        RecorderTab:Button({
            Title = "START",
            Desc = "",
            Callback = function()
                Recorder:Clear()
                Recorder:Log("Recorder started")

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
                                local success, tower_table = pcall(function()
                                    return http_service:JSONDecode(cleaned_json)
                                end)
                                if success and type(tower_table) == "table" then
                                    tower1 = tower_table[1] or "None"
                                    tower2 = tower_table[2] or "None"
                                    tower3 = tower_table[3] or "None"
                                    tower4 = tower_table[4] or "None"
                                    tower5 = tower_table[5] or "None"
                                end
                            end
                        end

                        if folder.Name == "ModifierReplicator" then
                            local raw_votes = folder:GetAttribute("Votes")
                            if type(raw_votes) == "string" then
                                local cleaned_json = raw_votes:match("{.*}") 
                                local success, mod_table = pcall(function()
                                    return http_service:JSONDecode(cleaned_json)
                                end)
                                if success and type(mod_table) == "table" then
                                    local mods = {}
                                    for mod_name, _ in pairs(mod_table) do
                                        table.insert(mods, mod_name .. " = true")
                                    end
                                    current_modifiers = table.concat(mods, ", ")
                                end
                            end
                        end
                    end
                end

                Recorder:Log("Mode: " .. current_mode)
                Recorder:Log("Map: " .. current_map)
                Recorder:Log("Towers: " .. tower1 .. ", " .. tower2)
                Recorder:Log(tower3 .. ", " .. tower4 .. ", " .. tower5)

                sync_existing_towers()
                Globals.record_strat = true
                if has_hook then
                    Recorder:Log("Extended recording enabled")
                else
                    Recorder:Log("Limited recording (place/upgrade/sell)")
                end

                if writefile then 
                    local config_header = string.format([[
local TDS = loadstring(game:HttpGet("https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua"))()

TDS:Loadout("%s", "%s", "%s", "%s", "%s")
TDS:Mode("%s")
TDS:GameInfo("%s", {%s})

]], tower1, tower2, tower3, tower4, tower5, current_mode, current_map, current_modifiers)
                    writefile("Strat.txt", config_header)
                end

                Window:Notify({
                    Title = "ADS",
                    Desc = "Recorder has started, you may place down your towers now.",
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
                Recorder:Log("Strategy saved, you may find it in \nyour workspace folder called 'Strat.txt'")
                Window:Notify({
                    Title = "ADS",
                    Desc = "Recording has been saved!\nCheck your workspace folder for Strat.txt",
                    Time = 3,
                    Type = "normal"
                })
            end
        })

        if game_state == "GAME" then
            local towers_folder = workspace_ref:WaitForChild("Towers", 5)

            -- Keep Workspace fallback logic in case the network placement fails
            towers_folder.ChildAdded:Connect(function(tower)
                if not Globals.record_strat then return end
                
                local replicator = tower:WaitForChild("TowerReplicator", 5)
                if not replicator then return end

                local owner_id = replicator:GetAttribute("OwnerId")
                if owner_id and owner_id ~= local_player.UserId then return end

                tower_count = tower_count + 1
                local my_index = tower_count
                spawned_towers[tower] = my_index

                local tower_name = replicator:GetAttribute("Name") or tower.Name
                local raw_pos = replicator:GetAttribute("Position")
                
                local pos_x, pos_y, pos_z
                if typeof(raw_pos) == "Vector3" then
                    pos_x, pos_y, pos_z = raw_pos.X, raw_pos.Y, raw_pos.Z
                else
                    local p = tower:GetPivot().Position
                    pos_x, pos_y, pos_z = p.X, p.Y, p.Z
                end
                
                -- Only log if not already handled by network
                -- (You may see duplicates if both trigger, but one can be commented out later if needed)
                local command = 'TDS:Place("' .. tower_name .. '", ' .. tostring(pos_x) .. ', ' .. tostring(pos_y) .. ', ' .. tostring(pos_z) .. ')'
                record_action(command)
                Recorder:Log("Placed " .. tower_name .. " (Index: " .. my_index .. ")")

                replicator:GetAttributeChangedSignal("Upgrade"):Connect(function()
                    if not Globals.record_strat then return end
                    record_action(string.format('TDS:Upgrade(%d)', my_index))
                    Recorder:Log("Upgraded Tower " .. my_index)
                end)
            end)

            towers_folder.ChildRemoved:Connect(function(tower)
                if not Globals.record_strat then return end
                
                local my_index = spawned_towers[tower]
                if my_index then
                    record_action(string.format('TDS:Sell(%d)', my_index))
                    Recorder:Log("Sold Tower " .. my_index)
                    spawned_towers[tower] = nil
                end
            end)
        end
    end
end
