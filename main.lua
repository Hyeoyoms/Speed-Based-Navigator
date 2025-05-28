-- Speed Based Navigator (v1.9.1)

SpeedNavigator = {
    min_speed = 24.0,
    max_speed = 600.0,
    status_message = "",
    enable_debug_prints = false, -- User toggle for verbose logging (original script feature)
    last_known_match_index = -1, -- Stores the index of the last found action (1-based)
    last_script_id_searched = nil -- Stores the ID of the script last searched
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

    local current_script_obj = ofs.Script(ofs.ActiveIdx())
    local current_script_id = ofs.ActiveIdx()

    if current_script_obj == nil or current_script_obj.actions == nil or #current_script_obj.actions < 2 then
        SpeedNavigator.status_message = "Error: Script needs at least 2 actions to define a segment."
        SpeedNavigator.last_known_match_index = -1
        SpeedNavigator.last_script_id_searched = nil
        return
    end

    local actions = current_script_obj.actions
    local num_actions = #actions
    local found_action_at_s_for_seek = nil
    local found_speed_info = ""
    local p1_action_index_of_match = -1 -- Stores the index of p1 for the matched segment in the current search

    local start_index_for_search = 1
    if SpeedNavigator.last_script_id_searched == current_script_id and
       SpeedNavigator.last_known_match_index > 0 and
       SpeedNavigator.last_known_match_index < num_actions then
        start_index_for_search = SpeedNavigator.last_known_match_index + 1
    else
        SpeedNavigator.last_known_match_index = -1 -- Reset if different script or invalid previous index
    end

    local search_occurred_and_found = false

    -- First search attempt: from start_index_for_search to the end of the script
    for i = start_index_for_search, num_actions - 1 do
        local p1 = actions[i]
        local p2 = actions[i+1]

        if p1 == nil or type(p1.pos) ~= "number" or type(p1.at) ~= "number" or
           p2 == nil or type(p2.pos) ~= "number" or type(p2.at) ~= "number" then
            goto continue_loop_primary
        end
        
        local p1_time_at_s = p1.at
        local p2_time_at_s = p2.at
        local time_diff_s = p2_time_at_s - p1_time_at_s

        if time_diff_s <= 0 then
            goto continue_loop_primary
        end

        local distance = math.abs(p2.pos - p1.pos)
        local current_speed_units_per_sec = distance / time_diff_s

        local is_slower_than_min = (SpeedNavigator.min_speed > 0) and (current_speed_units_per_sec < SpeedNavigator.min_speed) and (current_speed_units_per_sec > 0.00001)
        local is_faster_than_max = (SpeedNavigator.max_speed > 0) and (current_speed_units_per_sec > SpeedNavigator.max_speed)

        if is_slower_than_min or is_faster_than_max then
            found_action_at_s_for_seek = p1_time_at_s
            p1_action_index_of_match = i
            found_speed_info = string.format("%.2f units/s", current_speed_units_per_sec)
            search_occurred_and_found = true
            break
        end
        ::continue_loop_primary::
    end

    -- Second search attempt (wrap around): from the beginning to start_index_for_search - 1
    if not search_occurred_and_found and start_index_for_search > 1 then
        if SpeedNavigator.enable_debug_prints then print("Wrapping search to beginning...") end
        for i = 1, start_index_for_search - 1 do
            local p1 = actions[i]
            local p2 = actions[i+1]

            if p1 == nil or type(p1.pos) ~= "number" or type(p1.at) ~= "number" or
               p2 == nil or type(p2.pos) ~= "number" or type(p2.at) ~= "number" then
                goto continue_loop_wrap
            end
            
            local p1_time_at_s = p1.at
            local p2_time_at_s = p2.at
            local time_diff_s = p2_time_at_s - p1_time_at_s

            if time_diff_s <= 0 then
                goto continue_loop_wrap
            end

            local distance = math.abs(p2.pos - p1.pos)
            local current_speed_units_per_sec = distance / time_diff_s

            local is_slower_than_min = (SpeedNavigator.min_speed > 0) and (current_speed_units_per_sec < SpeedNavigator.min_speed) and (current_speed_units_per_sec > 0.00001)
            local is_faster_than_max = (SpeedNavigator.max_speed > 0) and (current_speed_units_per_sec > SpeedNavigator.max_speed)

            if is_slower_than_min or is_faster_than_max then
                found_action_at_s_for_seek = p1_time_at_s
                p1_action_index_of_match = i
                found_speed_info = string.format("%.2f units/s", current_speed_units_per_sec)
                search_occurred_and_found = true
                break
            end
            ::continue_loop_wrap::
        end
    end

    SpeedNavigator.last_script_id_searched = current_script_id

    if search_occurred_and_found and found_action_at_s_for_seek ~= nil and p1_action_index_of_match ~= -1 then
        SpeedNavigator.last_known_match_index = p1_action_index_of_match
        local seek_target_s = found_action_at_s_for_seek
        player.Seek(seek_target_s)
        local found_at_ms_display = seek_target_s * 1000
        SpeedNavigator.status_message = string.format("Found: %s at %.3fs (%.0fms) (Action Index: %d). Jumped.", found_speed_info, seek_target_s, found_at_ms_display, p1_action_index_of_match)
    else
        SpeedNavigator.last_known_match_index = -1 -- Reset if no new match found
        if type(found_action_at_s_for_seek) ~= "number" and found_action_at_s_for_seek ~= nil then
             SpeedNavigator.status_message = "Error: Calculated seek time is not a valid number."
        else
            SpeedNavigator.status_message = "No (new) sections found matching criteria. Search will restart from beginning on next try."
        end
    end
end

function update(delta)
    -- No periodic action required
end