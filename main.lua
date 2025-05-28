-- Speed Based Navigator (v1.9.1)

SpeedNavigator = {
    min_speed = 24.0,
    max_speed = 600.0,
    status_message = "",
    enable_debug_prints = false, -- User toggle for verbose logging (original script feature)
    found_action_index = -1
}

function init()
    print("Speed Based Navigator Initialized (v1.9.1 - Debug Print Format Fix)")
end

function gui()
    SpeedNavigator.min_speed = ofs.Input("Minimum Speed (units/s)", SpeedNavigator.min_speed, 1.0)
    if SpeedNavigator.min_speed < 0 then
        SpeedNavigator.min_speed = 0
    end
    ofs.Tooltip("Find sections SLOWER than this speed (but > 0 units/s).\nThe script will jump to the start of the first found section.")

    SpeedNavigator.max_speed = ofs.Input("Maximum Speed (units/s)", SpeedNavigator.max_speed, 1.0)
    if SpeedNavigator.max_speed <= 0 then
        if SpeedNavigator.max_speed < 0 then SpeedNavigator.max_speed = 0 end
    end
    ofs.Tooltip("Find sections FASTER than this speed.\nEnsure this is > 0 if you want to use this condition.")

    SpeedNavigator.enable_debug_prints = ofs.Checkbox("Enable Debug Prints", SpeedNavigator.enable_debug_prints)
    ofs.Tooltip("Show detailed processing logs in the OFS console.")

    ofs.Separator()

    if ofs.Button("Find and Go To Matching Section") then
        Execute_FindAndNavigate()
    end

    ofs.NewLine()

    if SpeedNavigator.status_message ~= "" and SpeedNavigator.status_message ~= nil then
        ofs.Text(SpeedNavigator.status_message)
    end
end

function Execute_FindAndNavigate()
    SpeedNavigator.status_message = "Processing..."
    SpeedNavigator.found_action_index = -1

    local current_script = ofs.Script(ofs.ActiveIdx())

    if current_script == nil or current_script.actions == nil or #current_script.actions < 2 then
        SpeedNavigator.status_message = "Error: Script needs at least 2 actions to define a segment."
        return
    end

    local actions = current_script.actions
    local found_action_at_s_for_seek = nil -- Stores the start time (in seconds) of the first matched segment
    local found_speed_info = ""
    local p1_action_index_of_match = -1

    -- Iterate through action pairs (segments) to calculate speed
    for i = 1, #actions - 1 do
        local p1 = actions[i]
        local p2 = actions[i+1]

        -- Validate action data; actions require 'pos' (position) and 'at' (time in seconds)
        if p1 == nil or type(p1.pos) ~= "number" or type(p1.at) ~= "number" or
           p2 == nil or type(p2.pos) ~= "number" or type(p2.at) ~= "number" then
            goto continue_loop -- Skip corrupted or incomplete segment data
        end
        
        local p1_time_at_s = p1.at
        local p2_time_at_s = p2.at
        local time_diff_s = p2_time_at_s - p1_time_at_s

        -- Time difference must be positive to calculate speed
        if time_diff_s <= 0 then
            goto continue_loop -- Skip segment if time difference is zero or negative
        end

        local distance = math.abs(p2.pos - p1.pos)
        local current_speed_units_per_sec = distance / time_diff_s

        -- Speed criteria checks:
        -- is_slower_than_min: speed > 0.00001 ensures actual movement, not static points.
        local is_slower_than_min = (SpeedNavigator.min_speed > 0) and (current_speed_units_per_sec < SpeedNavigator.min_speed) and (current_speed_units_per_sec > 0.00001)
        local is_faster_than_max = (SpeedNavigator.max_speed > 0) and (current_speed_units_per_sec > SpeedNavigator.max_speed)

        if is_slower_than_min or is_faster_than_max then
            found_action_at_s_for_seek = p1_time_at_s
            p1_action_index_of_match = i
            SpeedNavigator.found_action_index = p1_action_index_of_match -- Store matched action index globally
            found_speed_info = string.format("%.2f units/s", current_speed_units_per_sec)
            
            break -- Found the first matching segment, stop searching
        end
        ::continue_loop::
    end

    if found_action_at_s_for_seek ~= nil and type(found_action_at_s_for_seek) == "number" and p1_action_index_of_match ~= -1 then
        local seek_target_s = found_action_at_s_for_seek
        
        player.Seek(seek_target_s) -- Jump player to the start of the found segment
        
        local found_at_ms_display = seek_target_s * 1000
        SpeedNavigator.status_message = string.format("Found: %s at %.3fs (%.0fms) (Action Index: %d). Jumped.", found_speed_info, seek_target_s, found_at_ms_display, p1_action_index_of_match)
    else
        if type(found_action_at_s_for_seek) ~= "number" and found_action_at_s_for_seek ~= nil then
             SpeedNavigator.status_message = "Error: Calculated seek time is not a valid number."
        else
            SpeedNavigator.status_message = "No sections found matching the specified speed criteria."
        end
    end
end

function update(delta)
    -- No periodic action required
end