-- Speed Based Navigator (v1.9.1)

SpeedNavigator = {
    min_speed = 24.0,
    max_speed = 600.0,
    status_message = "",
    enable_debug_prints = false, -- User toggle for verbose logging (original script feature)
    last_known_match_index = -1, -- Stores the index of the last found action (1-based)
    last_script_id_searched = nil, -- Stores the ID of the script last searched
    scan_from_current_timeline = false, -- User toggle for scanning from current timeline
    timeline_last_found_at_s = nil, -- Stores the 'at' time of the last segment found via timeline scan
    timeline_last_found_action_idx = nil -- Stores the action index of the last segment found via timeline scan
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

    local prev_scan_from_timeline = SpeedNavigator.scan_from_current_timeline
    SpeedNavigator.scan_from_current_timeline = ofs.Checkbox("Scan from current timeline", SpeedNavigator.scan_from_current_timeline)
    if prev_scan_from_timeline ~= SpeedNavigator.scan_from_current_timeline then
        -- Reset timeline specific state if the mode is toggled
        SpeedNavigator.timeline_last_found_at_s = nil
        SpeedNavigator.timeline_last_found_action_idx = nil
        if SpeedNavigator.enable_debug_prints then print("Timeline scan mode toggled. Resetting timeline state.") end
    end
    ofs.Tooltip("If checked, scanning will start from the current video player timeline.\nIf unchecked, scanning will start from the beginning or after the last found position.")

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
    local search_occurred_and_found = false
    local initial_scan_from_timeline_done = false -- Flag to indicate if the first scan from timeline is done

    local use_timeline_scan_logic = SpeedNavigator.scan_from_current_timeline
    if use_timeline_scan_logic then
        if player == nil or type(player.CurrentTime) ~= "function" then
            if SpeedNavigator.enable_debug_prints then print("Player or player.CurrentTime() not available. Disabling timeline scan for this attempt.") end
            use_timeline_scan_logic = false -- Fallback to default search
            SpeedNavigator.status_message = "Warning: Player not ready for timeline scan. Used default scan."
        end
    end

    if use_timeline_scan_logic then
        local current_player_time_s = player.CurrentTime()
        local timeline_scan_start_index = 1

        if SpeedNavigator.timeline_last_found_at_s ~= nil and
           SpeedNavigator.timeline_last_found_action_idx ~= nil and
           math.abs(current_player_time_s - SpeedNavigator.timeline_last_found_at_s) < 0.05 and -- Increased tolerance to 50ms
           SpeedNavigator.timeline_last_found_action_idx < num_actions -1 then -- Ensure there's a next action to scan from
            
            timeline_scan_start_index = SpeedNavigator.timeline_last_found_action_idx + 1
            if SpeedNavigator.enable_debug_prints then
                print(string.format("Timeline scan: Resuming from index %d (after last found at %.3fs, action idx %d). Current player time: %.3fs",
                    timeline_scan_start_index, SpeedNavigator.timeline_last_found_at_s, SpeedNavigator.timeline_last_found_action_idx, current_player_time_s))
            end
        else
            -- Player time has changed, or no previous timeline find, or at the end of actions: reset and find from current player time
            if SpeedNavigator.enable_debug_prints then
                if SpeedNavigator.timeline_last_found_at_s == nil then
                    print(string.format("Timeline scan: Starting fresh. Player time: %.3fs", current_player_time_s))
                else
                    print(string.format("Timeline scan: Player time (%.3fs) differs from last found (%.3fs) or other condition. Resetting. Last action idx: %s",
                        current_player_time_s, SpeedNavigator.timeline_last_found_at_s or -1, SpeedNavigator.timeline_last_found_action_idx or "nil"))
                end
            end
            SpeedNavigator.timeline_last_found_at_s = nil
            SpeedNavigator.timeline_last_found_action_idx = nil

            for i = 1, num_actions do
                if actions[i].at >= current_player_time_s then
                    timeline_scan_start_index = i
                    break
                end
                if i == num_actions then
                    timeline_scan_start_index = num_actions
                end
            end
            if SpeedNavigator.enable_debug_prints then print(string.format("Timeline scan: Determined start index %d from player time %.3fs", timeline_scan_start_index, current_player_time_s)) end
        end
        
        local current_search_start_idx = timeline_scan_start_index
        if current_search_start_idx > num_actions -1 then current_search_start_idx = num_actions -1 end
        if current_search_start_idx < 1 then current_search_start_idx = 1 end

        -- First scan (timeline): from current_search_start_idx to end
        for i = current_search_start_idx, num_actions - 1 do
            local p1 = actions[i]
            local p2 = actions[i+1]

            if p1 == nil or type(p1.pos) ~= "number" or type(p1.at) ~= "number" or
               p2 == nil or type(p2.pos) ~= "number" or type(p2.at) ~= "number" then
                goto continue_loop_timeline_primary
            end
            
            local p1_time_at_s = p1.at
            local p2_time_at_s = p2.at
            local time_diff_s = p2_time_at_s - p1_time_at_s

            if time_diff_s <= 0 then
                goto continue_loop_timeline_primary
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
            ::continue_loop_timeline_primary::
        end
        initial_scan_from_timeline_done = true
    end

    -- Standard search logic (or fallback/wrap-around for timeline search)
    if not search_occurred_and_found then
        if use_timeline_scan_logic and initial_scan_from_timeline_done then
            -- This is the wrap-around part for "scan_from_current_timeline"
            if SpeedNavigator.enable_debug_prints then print("Timeline scan: Wrapping search to beginning until original timeline start...") end
            local timeline_wrap_end_index = 1
            
            local current_player_time_s_for_timeline_wrap
            if player == nil or type(player.CurrentTime) ~= "function" then
                 if SpeedNavigator.enable_debug_prints then print("Player or player.CurrentTime() not available for timeline wrap. Defaulting to full wrap before timeline_scan_start_index.") end
                 local temp_timeline_start_idx_for_fallback = 1
                 -- Attempt to get current time again for fallback. If still nil, this part won't be accurate.
                 local fallback_player_time_s = nil
                 if player and type(player.CurrentTime) == "function" then
                    fallback_player_time_s = player.CurrentTime()
                 end

                 if fallback_player_time_s then
                    for k_idx = 1, num_actions do
                        if actions[k_idx].at >= fallback_player_time_s then
                            temp_timeline_start_idx_for_fallback = k_idx
                            break
                        end
                        if k_idx == num_actions then temp_timeline_start_idx_for_fallback = num_actions end
                    end
                 else
                    -- If player.CurrentTime() is still not available, we can't accurately determine the wrap end point based on current time.
                    -- As a last resort, wrap up to the originally calculated timeline_scan_start_index (which itself might be 1 if player.CurrentTime failed initially).
                    -- This requires timeline_scan_start_index to be accessible here.
                    -- For simplicity in this diff, let's assume if player.CurrentTime fails here, we make wrap empty or up to num_actions-1.
                    -- A more robust solution would pass the initial current_player_time_s or timeline_scan_start_index.
                    -- Given the current structure, if player.CurrentTime fails here, the wrap will be less precise.
                    if SpeedNavigator.enable_debug_prints then print("Cannot determine precise wrap end due to player.CurrentTime() failure. Wrapping up to num_actions-1 or 0.") end
                    -- Defaulting to a safe, potentially full wrap if time is unavailable.
                    -- This could be improved by passing the initial current_player_time_s.
                    -- For now, let's make it wrap up to num_actions -1 if player time is unavailable.
                    temp_timeline_start_idx_for_fallback = num_actions -- This will make end_index num_actions -1
                 end
                 timeline_wrap_end_index = temp_timeline_start_idx_for_fallback -1
                 if timeline_wrap_end_index < 0 then timeline_wrap_end_index = 0 end
            else
                current_player_time_s_for_timeline_wrap = player.CurrentTime()
                if SpeedNavigator.enable_debug_prints then print(string.format("Timeline wrap: Player time for end index: %.3fs", current_player_time_s_for_timeline_wrap)) end
                for k_idx = 1, num_actions do
                    if actions[k_idx].at >= current_player_time_s_for_timeline_wrap then
                        timeline_wrap_end_index = k_idx -1
                        break
                    end
                     if k_idx == num_actions then
                        timeline_wrap_end_index = num_actions -1
                    end
                end
            end

            if timeline_wrap_end_index < 1 then timeline_wrap_end_index = 0 end -- Allow empty loop if needed
            if SpeedNavigator.enable_debug_prints then print(string.format("Timeline wrap: Scanning from index 1 to %d", timeline_wrap_end_index)) end

            for i = 1, timeline_wrap_end_index do
                 if i >= num_actions then break end -- ensure p2 is valid
                local p1 = actions[i]
                local p2 = actions[i+1]

                if p1 == nil or type(p1.pos) ~= "number" or type(p1.at) ~= "number" or
                   p2 == nil or type(p2.pos) ~= "number" or type(p2.at) ~= "number" then
                    goto continue_loop_timeline_wrap
                end
                
                local p1_time_at_s = p1.at
                local p2_time_at_s = p2.at
                local time_diff_s = p2_time_at_s - p1_time_at_s

                if time_diff_s <= 0 then
                    goto continue_loop_timeline_wrap
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
                ::continue_loop_timeline_wrap::
            end

        elseif not use_timeline_scan_logic then -- Covers both original "false" and fallback from "true"
             -- This is the original default search logic
            if SpeedNavigator.last_script_id_searched == current_script_id and
               SpeedNavigator.last_known_match_index > 0 and
               SpeedNavigator.last_known_match_index < num_actions then
                start_index_for_search = SpeedNavigator.last_known_match_index + 1
            else
                SpeedNavigator.last_known_match_index = -1
                start_index_for_search = 1
            end
            if SpeedNavigator.enable_debug_prints then print(string.format("Standard search: Starting from index %d", start_index_for_search)) end

            -- First search attempt: from start_index_for_search to the end of the script
            for i = start_index_for_search, num_actions - 1 do
                local p1 = actions[i]
                local p2 = actions[i+1]

                if p1 == nil or type(p1.pos) ~= "number" or type(p1.at) ~= "number" or
                   p2 == nil or type(p2.pos) ~= "number" or type(p2.at) ~= "number" then
                    goto continue_loop_primary_default
                end
                
                local p1_time_at_s = p1.at
                local p2_time_at_s = p2.at
                local time_diff_s = p2_time_at_s - p1_time_at_s

                if time_diff_s <= 0 then
                    goto continue_loop_primary_default
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
                ::continue_loop_primary_default::
            end

            -- Second search attempt (wrap around): from the beginning to start_index_for_search - 1
            if not search_occurred_and_found and start_index_for_search > 1 then
                if SpeedNavigator.enable_debug_prints then print("Standard search: Wrapping search to beginning...") end
                for i = 1, start_index_for_search - 1 do
                    local p1 = actions[i]
                    local p2 = actions[i+1]

                    if p1 == nil or type(p1.pos) ~= "number" or type(p1.at) ~= "number" or
                       p2 == nil or type(p2.pos) ~= "number" or type(p2.at) ~= "number" then
                        goto continue_loop_wrap_default
                    end
                    
                    local p1_time_at_s = p1.at
                    local p2_time_at_s = p2.at
                    local time_diff_s = p2_time_at_s - p1_time_at_s

                    if time_diff_s <= 0 then
                        goto continue_loop_wrap_default
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
                    ::continue_loop_wrap_default::
                end
            end
        end
    end

    SpeedNavigator.last_script_id_searched = current_script_id

    if search_occurred_and_found and found_action_at_s_for_seek ~= nil and p1_action_index_of_match ~= -1 then
        local seek_target_s = found_action_at_s_for_seek
        player.Seek(seek_target_s) -- Seek first

        if use_timeline_scan_logic then
            SpeedNavigator.timeline_last_found_at_s = seek_target_s -- Store the actual time we jumped to
            SpeedNavigator.timeline_last_found_action_idx = p1_action_index_of_match
            if SpeedNavigator.enable_debug_prints then
                print(string.format("Timeline scan: Stored last found at %.3fs, action index %d", seek_target_s, p1_action_index_of_match))
            end
        else
            SpeedNavigator.last_known_match_index = p1_action_index_of_match
        end
        
        local found_at_ms_display = seek_target_s * 1000
        SpeedNavigator.status_message = string.format("Found: %s at %.3fs (%.0fms) (Action Index: %d). Jumped.", found_speed_info, seek_target_s, found_at_ms_display, p1_action_index_of_match)
    else
        if use_timeline_scan_logic then
            -- If timeline scan found nothing, reset its state so next timeline scan starts fresh from player time
            SpeedNavigator.timeline_last_found_at_s = nil
            SpeedNavigator.timeline_last_found_action_idx = nil
            if SpeedNavigator.enable_debug_prints then print("Timeline scan: No match found, resetting timeline state.") end
        else
            SpeedNavigator.last_known_match_index = -1 -- Reset if no new match found for default scan
        end

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