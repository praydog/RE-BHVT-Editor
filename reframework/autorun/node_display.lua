if imnodes == nil or imgui.set_next_window_size == nil or sdk.hook_vtable == nil then
    re.msg("Your REFramework version is not new enough to use the behavior tree viewer!")
    return
end

local ImGuiStyleVar =
{
    --Enum name --------------------- --Member in ImGuiStyle structure (see ImGuiStyle for descriptions)
    ImGuiStyleVar_Alpha=0,               --float     Alpha
    ImGuiStyleVar_WindowPadding=1,       --ImVec2    WindowPadding
    ImGuiStyleVar_WindowRounding=2,      --float     WindowRounding
    ImGuiStyleVar_WindowBorderSize=3,    --float     WindowBorderSize
    ImGuiStyleVar_WindowMinSize=4,       --ImVec2    WindowMinSize
    ImGuiStyleVar_WindowTitleAlign=5,    --ImVec2    WindowTitleAlign
    ImGuiStyleVar_ChildRounding=6,       --float     ChildRounding
    ImGuiStyleVar_ChildBorderSize=7,     --float     ChildBorderSize
    ImGuiStyleVar_PopupRounding=8,       --float     PopupRounding
    ImGuiStyleVar_PopupBorderSize=9,     --float     PopupBorderSize
    ImGuiStyleVar_FramePadding=10,        --ImVec2    FramePadding
    ImGuiStyleVar_FrameRounding=11,       --float     FrameRounding
    ImGuiStyleVar_FrameBorderSize=12,     --float     FrameBorderSize
    ImGuiStyleVar_ItemSpacing=13,         --ImVec2    ItemSpacing
    ImGuiStyleVar_ItemInnerSpacing=14,    --ImVec2    ItemInnerSpacing
    ImGuiStyleVar_IndentSpacing=15,       --float     IndentSpacing
    ImGuiStyleVar_CellPadding=16,         --ImVec2    CellPadding
    ImGuiStyleVar_ScrollbarSize=17,       --float     ScrollbarSize
    ImGuiStyleVar_ScrollbarRounding=18,   --float     ScrollbarRounding
    ImGuiStyleVar_GrabMinSize=19,         --float     GrabMinSize
    ImGuiStyleVar_GrabRounding=20,        --float     GrabRounding
    ImGuiStyleVar_TabRounding=21,         --float     TabRounding
    ImGuiStyleVar_ButtonTextAlign=22,     --ImVec2    ButtonTextAlign
    ImGuiStyleVar_SelectableTextAlign=23, --ImVec2    SelectableTextAlign
    ImGuiStyleVar_COUNT=24
};

local cached_node_names = {}
local cached_node_indices = {}

local node_input = 1
local node_replace_input = 1
local action_map = {}
local action_name_map = {}
local event_map = {}
local event_name_map = {}
local condition_map = {}
local condition_name_map = {}
local selection_map = {}
local condition_selection_map = {}
local node_map = {}
local node_names = {}
local first_times = {}
local sort_dict = {}

local node_replacements = {

}

local TAB = imgui.get_key_index(0)
local LEFT_ARROW = imgui.get_key_index(1)
local RIGHT_ARROW = imgui.get_key_index(2)
local UP_ARROW = imgui.get_key_index(3)
local DOWN_ARROW = imgui.get_key_index(4)
local ENTER = imgui.get_key_index(13)
local VK_LSHIFT = 0xA0

local cfg = {
    -- view
    always_show_node_editor = false,
    show_minimap = true,
    follow_active_nodes = false,
    display_parent_of_active = true,
    parent_display_depth = 0,
    default_node = 0,
    show_side_panels = true,
    graph_closes_with_reframework = true,

    -- editor
    pan_speed = 1000,
    lerp_speed = 2.0,
    lerp_nodes = true,

    -- search
    max_search_results = 200,
    default_node_search_name = "",
    default_condition_search_name = "",
    default_action_search_name = "",
    search_allow_duplicates = true
}

local cfg_path = "bhvteditor/main_config.json"

local function load_cfg()
    local loaded_cfg = json.load_file(cfg_path)

    if loaded_cfg == nil then
        json.dump_file(cfg_path, cfg)
        return
    end

    for k, v in pairs(loaded_cfg) do
        cfg[k] = v
    end
end

load_cfg()

re.on_config_save(function()
    json.dump_file(cfg_path, cfg)
end)

local function duplicate_managed_object_in_array(arr, i)
    first_times = {}

    local source = arr[i]

    -- Go through getter and setter methods and duplicate them.
    local duped = source:get_type_definition():create_instance():add_ref_permanent()
    log.info("[Dupe] Duped: " .. tostring(duped))

    local td = source:get_type_definition()

    while td ~= nil do
        for i, getter in ipairs(td:get_methods()) do
            if getter:get_name():find("get_") == 1 then -- start of string
                local isolated_name = getter:get_name():sub(5)
                local setter = td:get_method("set_" .. isolated_name)

                if setter then
                    log.info("[Dupe] Setting " .. tostring(isolated_name))

                    setter:call(duped, getter:call(source))
                end
            end
        end

        td = td:get_parent_type()
    end

    arr:push_back(duped)

    return duped
end

local function duplicate_global_static_action(tree, i)
    first_times = {}

    --re.msg("[Dupe] Duping " .. tostring(i))

    -- Duplicate the action method as well.
    local action_methods = tree:get_data():get_static_action_methods()
    action_methods:push_back(action_methods[i])

    return duplicate_managed_object_in_array(tree:get_data():get_static_actions(), i)
end

local function duplicate_global_action(tree, i)
    first_times = {}

    --re.msg("[Dupe] Duping " .. tostring(i))

    -- Duplicate the action method as well.
    local action_methods = tree:get_data():get_action_methods()
    action_methods:push_back(action_methods[i])

    return duplicate_managed_object_in_array(tree:get_actions(), i)
end

local function duplicate_global_condition(tree, i)
    return duplicate_managed_object_in_array(tree:get_conditions(), i)
end

local function duplicate_global_static_condition(tree, i)
    return duplicate_managed_object_in_array(tree:get_data():get_static_conditions(), i)
end

local function duplicate_global_static_transition_event(tree, i)
    return duplicate_managed_object_in_array(tree:get_data():get_static_transitions(), i)
end

local function duplicate_global_transition_event(tree, i)
    return duplicate_managed_object_in_array(tree:get_transitions(), i)
end

local function cache_node_indices(sorted_nodes, tree)
    if cached_node_indices[tree] ~= nil then
        return
    end

    cached_node_indices[tree] = {}

    for i=0, tree:get_node_count()-1 do
        local node = tree:get_node(i)

        if node then
            cached_node_indices[tree][node:as_memoryview():address()] = i
        end
    end

    action_map[tree] = {}
    action_name_map[tree] = {}

    event_map[tree] = {}
    event_name_map[tree] = {}

    node_map[tree] = {}
    node_names[tree] = {}
    
    for k, node in pairs(sorted_nodes) do
        table.insert(node_map[tree], node)
        table.insert(node_names[tree], tostring(cached_node_indices[tree][node:as_memoryview():address()]) .. ": " .. node:get_full_name())
    end
end

local function get_node_full_name(node)
    if node == nil then
        return ""
    end

    local addr = node:as_memoryview():get_address()

    if cached_node_names[addr] ~= nil then
        return cached_node_names[addr]
    end

    local fn = node:get_full_name()

    cached_node_names[addr] = fn

    return fn
end

local gn = reframework:get_game_name()

local function get_localplayer()
    if gn == "re2" or gn == "re3" then
        local player_manager = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
        if player_manager == nil then return nil end
    
        return player_manager:call("get_CurrentPlayer")
    elseif gn == "dmc5" then
        local player_manager = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
        if player_manager == nil then return nil end
    
        local player_comp = player_manager:call("get_manualPlayer")
        if player_comp == nil then return nil end

        return player_comp:call("get_GameObject")
    elseif gn == "mhrise" then
        local player_manager = sdk.get_managed_singleton(sdk.game_namespace("player.PlayerManager"))
        if player_manager == nil then return nil end
    
        local player_comp = player_manager:call("findMasterPlayer")
        if player_comp == nil then return nil end

        return player_comp:call("get_GameObject")
    end

    return nil
end

local last_layer = nil
local last_player = nil

local function get_sorted_nodes(tree)
    local out = {}

    if sort_dict[tree] ~= nil then
        local res = sort_dict[tree]

        if res ~= nil then
            return res
        end
    end

    for j=0, tree:get_node_count() do
        local node = tree:get_node(j)

        if node then
            table.insert(out, node)
        end
    end

    table.sort(out, function(a, b)
        return get_node_full_name(a) < get_node_full_name(b)
    end)

    sort_dict[tree] = out

    return out
end

local find_action_index = function(tree, action)
    for i, v in ipairs(action_map[tree]) do
        if v.action == action then
            return v.index
        end
    end

    return 0
end

local find_event_index = function(tree, event)
    for i, v in ipairs(event_map[tree]) do
        if v.event == event then
            return v.index
        end
    end

    return 0
end

local function display_action(tree, i, node, name, action)
    local enabled = action:call("get_Enabled")
    local status = enabled and "ON" or "OFF"
    if imgui.button(status) then
        action:call("set_Enabled", not enabled)
        enabled = not enabled
    end
    
    imgui.same_line()
    local made = imgui.tree_node(tostring(i) .. ": ")
    imgui.same_line()
    imgui.text(name)
    if made then
        if node ~= nil then
            if action ~= nil then
                imgui.input_text("Address", string.format("%X", action:get_address()))
            end

            local input_text = tostring(node_replace_input)
            local changed = false
            --[[changed, input_text = imgui.input_text("Replace action", input_text, 1 << 5)

            if changed then
                node:replace_action(i-1, tonumber(input_text))
            end]]

            if selection_map[tree] == nil then
                selection_map[tree] = {}
            end

            local selection = selection_map[tree][i]

            if selection == nil then
                selection = 1
            end

            for j, v in ipairs(action_map[tree]) do
                if v.action == action then
                    selection = j
                    break
                end
            end

            changed, selection = imgui.combo("Replace Action", selection, action_name_map[tree])

            if changed then
                first_times = {}

                node:get_data():get_actions()[i] = action_map[tree][selection].index
                selection_map[tree][i] = selection
            end
        end

        object_explorer:handle_address(action)
        

        imgui.tree_pop()
    end
end

local function display_event(tree, i, j, node, name, event)
    local enabled = event:call("get_Enabled")
    local status = enabled and "ON" or "OFF"
    if imgui.button(status) then
        event:call("set_Enabled", not enabled)
        enabled = not enabled
    end
    
    imgui.same_line()
    local made = imgui.tree_node(tostring(i) .. ": ")
    imgui.same_line()
    imgui.text(name)
    if made then
        if node ~= nil then
            if event ~= nil then
                imgui.input_text("Address", string.format("%X", event:get_address()))
            end

            local input_text = tostring(node_replace_input)
            local changed = false
            --[[changed, input_text = imgui.input_text("Replace event", input_text, 1 << 5)

            if changed then
                node:replace_event(i-1, tonumber(input_text))
            end]]

            if selection_map[tree] == nil then
                selection_map[tree] = {}
            end

            local selection = selection_map[tree][i]

            if selection == nil then
                selection = 1
            end

            for j, v in ipairs(event_map[tree]) do
                if v.event == event then
                    selection = j
                    break
                end
            end

            changed, selection = imgui.combo("Replace event", selection, event_name_map[tree])

            if changed then
                first_times = {}

                node:get_data():get_transition_events()[i][j] = event_map[tree][selection].index
                selection_map[tree][i] = selection
            end
        end

        object_explorer:handle_address(event)
        

        imgui.tree_pop()
    end
end

local replace_condition_id_text = ""

local custom_condition_evaluators = {}

local function display_condition(tree, i, node, name, cond)
    if imgui.tree_node(name) then
        if not custom_condition_evaluators[cond] then
            if imgui.button("Add Lua Driven Evaluator") then
                custom_condition_evaluators[cond] = {}
                custom_condition_evaluators[cond].str = "return function(storage, cond, arg, retval)\n\treturn retval\nend"
                custom_condition_evaluators[cond].eval = load(custom_condition_evaluators[cond].str)
                custom_condition_evaluators[cond].storage = {}

                local add_evaluator = function()
                    local prev_args = nil
    
                    sdk.hook_vtable(
                        cond, 
                        cond:get_type_definition():get_method("evaluate"), 
                        function(args)
                            prev_args = args
                        end,
                        function(retval)
                            local old_retval = (sdk.to_int64(retval) & 1) == 1
                            local new_retval = 
                                custom_condition_evaluators[cond].eval()(
                                    custom_condition_evaluators[cond].storage,
                                    sdk.to_managed_object(prev_args[2]), 
                                    sdk.to_managed_object(prev_args[3]), 
                                    old_retval
                                )

                            --[[if sdk.to_int64(new_retval) ~= old_retval then
                                log.debug("Condition changed by Lua!" .. " " .. string.format("%i->%i", old_retval, sdk.to_int64(new_retval)))
                            else                  
                                if sdk.to_int64(retval) == 1 then
                                    log.debug("Condition met!")
                                else
                                    log.debug("Condition not met!")
                                end
                            end]]

                            return sdk.to_ptr(new_retval)
                        end
                    )
                end
    
                add_evaluator()
            end
        else
            imgui.text("Press CTRL+Enter for the changes to take effect.")

            local changed = false

            local cursor_screen_pos = imgui.get_cursor_screen_pos()
            changed, custom_condition_evaluators[cond].str = imgui.input_text_multiline("Evaluator", custom_condition_evaluators[cond].str)
    
            if imgui.is_item_active() then
                imgui.open_popup(tostring(cond) .. ": Evaluator")
            end
    
            local last_input_width = imgui.calc_item_width()
    
            -- Causes the textbox to be overlayed on top of the existing textbox
            -- because for some reason the textbox inside the node doesn't accept TAB input
            -- however, the popup version does.
            imgui.set_next_window_pos(cursor_screen_pos)
    
            if imgui.begin_popup(tostring(cond) .. ": Evaluator", (1 << 18) | (1 << 19)) then
                imgui.set_next_item_width(last_input_width)
                changed, custom_condition_evaluators[cond].str, tstart, tend = imgui.input_text_multiline("Evaluator", custom_condition_evaluators[cond].str, {0,0}, (1 << 5) | (1 << 10) | (1 << 8))
        
                if changed then
                    local err = nil
                    custom_condition_evaluators[cond].eval, custom_condition_evaluators[cond].err = load(custom_condition_evaluators[cond].str)
                end
        
                imgui.end_popup()
            end
    
    
            --[[if changed then
                local err = nil
                custom_condition_evaluators[cond].eval, custom_condition_evaluators[cond].err = load(custom_condition_evaluators[cond].str)
                
            end]]
            if custom_condition_evaluators[cond].err then
                imgui.text(custom_condition_evaluators[cond].err)
            end
        end

        if cond ~= nil then
            imgui.input_text("Address", string.format("%X", cond:get_address()))
        end

        if node ~= nil then
            local changed = false

            if condition_selection_map[tree] == nil then
                condition_selection_map[tree] = {}
            end
    
            local selection = condition_selection_map[tree][i]
    
            if selection == nil then
                selection = 1
            end
    
            for j, v in ipairs(condition_map[tree]) do
                if v.condition == cond then
                    selection = j
                    break
                end
            end

            changed, selection = imgui.combo("Replace Condition", selection, condition_name_map[tree])

            if changed then
                first_times = {}

                node:get_data():get_transition_conditions()[i] = condition_map[tree][selection].index
                condition_selection_map[tree][i] = selection
            end

            changed, replace_condition_id_text = imgui.input_text("Replace Condition by ID", replace_condition_id_text, 1 << 5)

            if changed then
                first_times = {}
                node:get_data():get_transition_conditions()[i] = tonumber(replace_condition_id_text)
            end

        end

        object_explorer:handle_address(cond)

        imgui.tree_pop()
    end
end

local function display_bhvt_array(tree, node, bhvt_array, tree_func, predicate, on_duplicate)
    imgui.push_id(bhvt_array:as_memoryview():address())

    for i=0, bhvt_array:size()-1 do
        local child = tree_func(tree, bhvt_array[i])
        imgui.push_id(i)

        if imgui.button("Erase") then
            first_times = {}
            bhvt_array:erase(i)
        end

        imgui.same_line()

        if imgui.button("Null") then
            first_times = {}
            bhvt_array[i] = -1
        end

        imgui.same_line()

        if imgui.button("Dupe") then
            first_times = {}

            if on_duplicate ~= nil then
                on_duplicate(i, child)
            else
                bhvt_array:push_back(bhvt_array[i])
            end

            --[[for j, v in pairs(action_map[tree]) do
                if v.action == child then
                    bhvt_array:push_back(v.index)
                    break
                end
            end]]

            return
        end

        imgui.same_line()

        if imgui.button("^") then
            first_times = {}

            if i > 0 and bhvt_array:size() > 1 then
                -- swap/insert is not implemented, so we must do it manually
                local tmp = bhvt_array[i-1]

                if type(tmp) == "table" or type(tmp) == "userdata" then
                    if tmp.to_valuetype ~= nil then
                        tmp = tmp:to_valuetype()
                    end
                end

                bhvt_array[i-1] = bhvt_array[i]
                bhvt_array[i] = tmp
            end
        end

        imgui.same_line()

        if imgui.button("v") then
            first_times = {}

            if i < bhvt_array:size()-1 then
                -- swap/insert is not implemented, so we must do it manually
                local tmp = bhvt_array[i+1]

                if type(tmp) == "table" or type(tmp) == "userdata" then
                    if tmp.to_valuetype ~= nil then
                        tmp = tmp:to_valuetype()
                    end
                end

                bhvt_array[i+1] = bhvt_array[i]
                bhvt_array[i] = tmp
            end
        end

        imgui.same_line()

        if predicate then
            predicate(tree, i, node, child)
        end

        imgui.pop_id()
    end

    imgui.pop_id()
end

local function display_node_replacement(text, tree, node, node_array, node_array_idx)
    local node_data = node:get_data()

    if node_array ~= nil then
        if selection_map[tree] == nil then
            selection_map[tree] = {}
            selection_map[tree][node:get_id()] = 1
        end

        local changed = false
        local selection = selection_map[tree][node:get_id()] 
        changed, selection = imgui.combo(text, selection, node_names[tree])

        if changed then
            local target_node = node_map[tree][selection]
            node_array[node_array_idx] = cached_node_indices[tree][target_node:as_memoryview():address()]
            selection_map[tree][node:get_id()] = selection
        end
    end
end

local function display_node_addition(text, tree, node, node_array)
    local node_data = node:get_data()

    if node_array ~= nil then
        if selection_map[tree] == nil then
            selection_map[tree] = {}
            selection_map[tree][node:get_id()] = 1
        end

        local changed = false
        local selection = selection_map[tree][node:get_id()] 
        changed, selection = imgui.combo(text, selection, node_names[tree])

        if changed then
            local target_node = node_map[tree][selection]
            node_array:push_back(cached_node_indices[tree][target_node:as_memoryview():address()])
            selection_map[tree][node:get_id()] = selection

            -- add dummy (-1) transitions so the game doesn't crash
            --local node_data = node:get_data()
            return true
        end
    end

    return false
end

local transition_state_id_text = "0"
local replace_node_id_text = "0"
local add_action_id_text = "0"
local add_event_id_text = "0"

local queued_editor_id_move = nil

local function display_node(tree, node, node_array, node_array_idx, cond)
    local changed = false

    imgui.push_id(node:get_id())

    if imgui.button("Goto") then
        for i=0, tree:get_node_count()-1 do
            local test_node = tree:get_node(i)

            if test_node == node then
                queued_editor_id_move = {["i"] = i, ["id"] = node:get_id()}
                break
            end
        end
    end

    imgui.same_line()

    local name = "Run"

    if node:get_status1() == 2 or node:get_status2() == 2 then
        name = "Running"
    end

    if imgui.button(name) then
        last_layer:call("setCurrentNode(System.UInt64, via.behaviortree.SetNodeInfo, via.motion.SetMotionTransitionInfo)", node:get_id(), nil, nil)
    end

    imgui.same_line()

    local node_name = cached_node_indices[tree][node:as_memoryview():address()] .. ": " .. node:get_full_name()

    local made_node = imgui.tree_node(node_name)

    if cond ~= nil then
        imgui.same_line()
        imgui.text_colored("[" .. cond:get_type_definition():get_full_name() .. "]", 0xFF00FF00)
    end

    if made_node then
        local node_data = node:get_data()

        imgui.input_text("Address", string.format("%X", node:as_memoryview():get_address()))

        display_node_replacement("Replace Node", tree, node, node_array, node_array_idx)

        local changed, replace_node_id_text = imgui.input_text("Replace Node ID by ID", replace_node_id_text, 1 << 5)
        
        if changed then
            node_array[node_array_idx] = tonumber(replace_node_id_text)
        end

        --imgui.text("Full name: " .. get_node_full_name(node))
        imgui.text("ID: " .. node:get_id())
        --imgui.text("Status: " .. node:get_status1())

        if cond ~= nil then 
            display_condition(tree, node_array_idx, node, cond:get_type_definition():get_full_name(), cond)
        end

        if imgui.tree_node("Children") then
            display_bhvt_array(tree, node, node_data:get_children(), tree.get_node, 
                function(tree, i, node, element)
                    display_node(tree, element, node_data:get_children(), i)
                end
            )

            imgui.tree_pop()
        end

        --------------------------------------------------
        ----------------- NODE ACTIONS -------------------
        --------------------------------------------------
        local made = imgui.tree_node("Actions")
        imgui.same_line()
        imgui.text("[" .. tostring(#node:get_actions()) .. "]")

        if made then
            if selection_map[tree] == nil then
                selection_map[tree] = {}
                selection_map[tree][node:get_id()] = 1
            end

            local selection = selection_map[tree][node:get_id()] 

            changed, selection = imgui.combo("Add Action", selection, action_name_map[tree])

            if changed then
                first_times = {}

                --node:append_action(action_map[tree][selection].index)
                node_data:get_actions():push_back(action_map[tree][selection].index)
                selection_map[tree][node:get_id()] = selection
            end
            
            changed, add_action_id_text = imgui.input_text("Add Action by ID", add_action_id_text, 1 << 5)

            if changed then
                first_times = {}

                node_data:get_actions():push_back(tonumber(add_action_id_text))
            end

            changed, selection = imgui.combo("Copy from", selection, node_names[tree])

            if changed then
                first_times = {}

                local copy_node = node_map[tree][selection]
                last_layer:call("setCurrentNode(System.UInt64, via.behaviortree.SetNodeInfo, via.motion.SetMotionTransitionInfo)", copy_node:get_id(), nil, nil)

                --if copy_node ~= nil then
                    for i, v in ipairs(copy_node:get_actions()) do
                        --node:append_action(find_action_index(tree, v))
                        node_data:get_actions():push_back(find_action_index(tree, v))
                    end

                    for j, g in ipairs(copy_node:get_children()) do
                        for i, v in ipairs(g:get_actions()) do
                            --node:append_action(find_action_index(tree, v))
                            node_data:get_actions():push_back(find_action_index(tree, v))
                        end
                    end
                --end
            end

            display_bhvt_array(tree, node, node_data:get_actions(), tree.get_action, 
                function(tree, i, node, element)
                    display_action(tree, i, node, element:get_type_definition():get_full_name(), element)
                end,
                function(i, element)
                    if element == nil then
                        return
                    end

                    local global_index = node_data:get_actions()[i]

                    local duped_element = nil
                    local duped_index = 0

                    if (global_index & (1 << 30)) ~= 0 then
                        duped_element = duplicate_global_static_action(tree, global_index & 0xFFFFFFF)
                        duped_index = (tree:get_data():get_static_actions():size() - 1) | (1 << 30)
                    else
                        duped_element = duplicate_global_action(tree, global_index)
                        duped_index = tree:get_actions():size() - 1
                    end

                    if duped_element ~= nil then
                        node_data:get_actions():push_back(duped_index)
                    end
                end
            )

            imgui.tree_pop()
        end

        --[[if imgui.tree_node("Unloaded Actions [" .. tostring(#node:get_unloaded_actions()) .. "]") then
            local actions = node:get_unloaded_actions()

            for i=1, #actions do
                local child = actions[i]

                if child ~= nil then
                    display_action(tree, i, node, tostring(i) .. ": " .. child:get_type_definition():get_full_name() .. " [ NOT YET LOADED ] ", child)
                end
            end

            imgui.tree_pop()
        end]]

        --------------------------------------------------
        ----------- NODE TRANSITION STATES ---------------
        --------------------------------------------------
        if imgui.tree_node("Transition States") then
            if display_node_addition("Add Transition State", tree, node, node_data:get_states()) then
                first_times = {}

                node_data:get_transition_conditions():push_back(0)
                node_data:get_transition_events():emplace()
                node_data:get_states_2():push_back(0)
                node_data:get_transition_ids():push_back(0)
                node_data:get_transition_attributes():push_back(0)
            end

            changed, transition_state_id_text = imgui.input_text("Add Transition State (ID)", transition_state_id_text, 1 << 5)

            if changed then
                first_times = {}

                node_data:get_states():push_back(tonumber(transition_state_id_text))
                node_data:get_transition_conditions():push_back(0)
                node_data:get_transition_events():emplace()
                node_data:get_states_2():push_back(0)
                node_data:get_transition_ids():push_back(0)
                node_data:get_transition_attributes():push_back(0)
            end
 
            display_bhvt_array(tree, node, node_data:get_states(), tree.get_node, 
                function(tree, i, node, element)
                    local conditions = node:get_data():get_transition_conditions()
                    local condition = tree:get_condition(conditions[i])

                    display_node(tree, element, node_data:get_states(), i, condition)
                end,
                -- duplication predicate
                function(i, element)
                    first_times = {}

                    node_data:get_states():push_back(node_data:get_states()[i])
                    node_data:get_transition_conditions():push_back(0)
                    node_data:get_transition_events():emplace()
                    node_data:get_states_2():push_back(0)
                    node_data:get_transition_ids():push_back(0)
                    node_data:get_transition_attributes():push_back(0)
                end
            )

            imgui.tree_pop()
        end

        --------------------------------------------------
        ----------- NODE TRANSITION CONDITONS ------------
        --------------------------------------------------
        local draw_conditions = function(transition_array, transition_array_name)
            local changed = false

            if selection_map[tree] == nil then
                selection_map[tree] = {}
                selection_map[tree][node:get_id()] = 1
            end

            local selection = selection_map[tree][node:get_id()] 

            changed, selection = imgui.combo("Add Condition", selection, condition_name_map[tree])

            if changed then
                first_times = {}

                --node:append_action(action_map[tree][selection].index)
                transition_array:push_back(condition_map[tree][selection].index)
                selection_map[tree][node:get_id()] = selection
            end
            
            changed, selection = imgui.combo("Copy from", selection, node_names[tree])

            if changed then
                first_times = {}

                local copy_node = node_map[tree][selection]
                local copy_node_data = copy_node:get_data()
                last_layer:call("setCurrentNode(System.UInt64, via.behaviortree.SetNodeInfo, via.motion.SetMotionTransitionInfo)", copy_node:get_id(), nil, nil)

                --if copy_node ~= nil then
                    for j=0, copy_node_data[transition_array_name](copy_node_data):size() do
                        --node:append_action(find_action_index(tree, v))
                        local v = tree:get_condition(j)
                        transition_array:push_back(v)
                    end
                --end
            end

            display_bhvt_array(tree, node, transition_array, tree.get_condition,
                -- display predicate
                function(tree, i, node, element)
                    if element == nil then
                        imgui.text(tostring(i) .. ": [ NULL -1 ]")
                    else
                        display_condition(tree, i, node, tostring(i) .. ": " .. element:get_type_definition():get_full_name(), element)
                    end
                end,
                -- duplication predicate
                function(i, element)
                    if element == nil then
                        return
                    end

                    local global_index = transition_array[i]

                    local duped_element = nil
                    local duped_index = 0

                    if (global_index & (1 << 30)) ~= 0 then
                        duped_element = duplicate_global_static_condition(tree, global_index & 0xFFFFFFF)
                        duped_index = (tree:get_data():get_static_conditions():size() - 1) | (1 << 30)
                    else
                        duped_element = duplicate_global_condition(tree, global_index)
                        duped_index = tree:get_conditions():size() - 1
                    end

                    if duped_element ~= nil then
                        transition_array:push_back(duped_index)
                    end
                end
            )
        end

        if imgui.tree_node("Transition Conditions") then
            draw_conditions(node_data:get_transition_conditions(), "get_transition_conditions")
            imgui.tree_pop()
        end

        if imgui.tree_node("Transition StatesEx") then
            if display_node_addition("Add Transition StateEx", tree, node, node_data:get_states_2()) then
                node_data:get_transition_conditions():push_back(-1)
            end
 
            display_bhvt_array(tree, node, node_data:get_states_2(), tree.get_node, function(tree, i, node, element)
                display_node(tree, element, node_data:get_states_2(), i)
            end)

            imgui.tree_pop()
        end

        if imgui.tree_node("Transition Start States") then
            display_node_addition("Add Start State", tree, node, node_data:get_start_states())

            display_bhvt_array(tree, node, node_data:get_start_states(), tree.get_node, function(tree, i, node, element)
                display_node(tree, element, node_data:get_start_states(), i)
            end)

            imgui.tree_pop()
        end

        if imgui.tree_node("Transition IDs") then
            display_bhvt_array(tree, node, node_data:get_transition_ids(), 
                function(tree, x)
                    return x
                end,
                function(tree, i, node, element)
                    imgui.text(tostring(i))
                    imgui.same_line()
                    --local changed, val = imgui.drag_int(tostring(i), element, 1)
                    imgui.push_item_width(150)
                    local changed, val = imgui.input_text(tostring(i), tostring(element))
                    imgui.pop_item_width()

                    if changed then
                        first_times = {}
                        node_data:get_transition_ids()[i] = tonumber(val)
                    end
                end
            )

            imgui.tree_pop()
        end

        if imgui.tree_node("Transition Attributes") then
            display_bhvt_array(tree, node, node_data:get_transition_attributes(), 
                function(tree, x)
                    return x
                end,
                function(tree, i, node, element)
                    imgui.text(tostring(i))
                    imgui.same_line()
                    --local changed, val = imgui.drag_int(tostring(i), element, 1)
                    imgui.push_item_width(150)
                    local changed, val = imgui.input_text(tostring(i), tostring(element))
                    imgui.pop_item_width()

                    if changed then
                        first_times = {}
                        node_data:get_transition_attributes()[i] = tonumber(val)
                    end
                end
            )

            imgui.tree_pop()
        end

        --------------------------------------------------
        ----------- NODE TRANSITION EVENTS ---------------
        --------------------------------------------------
        if imgui.tree_node("Transition Events") then
            if selection_map[tree] == nil then
                selection_map[tree] = {}
                selection_map[tree][node:get_id()] = 1
            end

            display_bhvt_array(tree, node, node_data:get_transition_events(), 
                function(tree, x)
                    return x
                end,
                function(tree, i, node, element)
                    local evts = element
                    local made = imgui.tree_node(tostring(i) .. " [" .. tostring(evts:size()) .. "]")

                    imgui.same_line()

                    local state_index = node_data:get_states()[i]

                    if state_index >= 0 and state_index < tree:get_node_count() then
                        local state_name = get_node_full_name(tree:get_node(state_index))
                        imgui.text_colored("[" .. state_name .. "]", 0xFF00FF00)
                    end

                    if made then
                        local selection = selection_map[tree][node:get_id()] 

                        changed, selection = imgui.combo("Add event", selection, event_name_map[tree])
            
                        if changed then
                            first_times = {}
            
                            evts:push_back(event_map[tree][selection].index)
                            selection_map[tree][node:get_id()] = selection
                        end
                        
                        changed, add_event_id_text = imgui.input_text("Add event by ID", add_event_id_text, 1 << 5)
            
                        if changed then
                            first_times = {}
            
                            evts:push_back(tonumber(add_event_id_text))
                        end

                        if evts:size() == 0 then
                            imgui.text("[ EMPTY ]")
                            imgui.tree_pop()
                            return
                        end

                        imgui.push_id(tostring(evts:as_memoryview():get_address()))

                        display_bhvt_array(tree, node, evts, 
                            function(tree, x)
                                return tree:get_transitions()[x]
                            end,
                            function(tree, j, node, element_tree)
                                display_event(tree, i, j, node, tostring(evts[j]) .. ": " .. tostring(element_tree:get_type_definition():get_full_name()), element_tree) -- TODO, DO THAT ONE!
                            end,
                            function(j, element)
                                if element == nil then
                                    return
                                end
            
                                local global_index = evts[j]
            
                                local duped_element = nil
                                local duped_index = 0
            
                                if (global_index & (1 << 30)) ~= 0 then
                                    duped_element = duplicate_global_static_transition_event(tree, global_index & 0xFFFFFFF)
                                    duped_index = (tree:get_data():get_static_transitions():size() - 1) | (1 << 30)
                                else
                                    duped_element = duplicate_global_transition_event(tree, global_index)
                                    duped_index = tree:get_transitions():size() - 1
                                end
            
                                if duped_element ~= nil then
                                    evts:push_back(duped_index)
                                end
                            end
                        )

                        imgui.pop_id()
                        imgui.tree_pop()
                    end
                end
            )

            imgui.tree_pop()
        end

        if imgui.tree_node("Conditions") then
            draw_conditions(node_data:get_conditions(), "get_conditions")
            imgui.tree_pop()
        end

        if imgui.tree_node("Tags") then
            display_bhvt_array(tree, node, node_data:get_tags(), 
                function(tree, x)
                    return x
                end,
                function(tree, i, node, element)
                    imgui.text(tostring(i))
                    imgui.same_line()
                    --local changed, val = imgui.drag_int(tostring(i), element, 1)

                    imgui.push_item_width(150)
                    local changed, val = imgui.input_text(tostring(i), tostring(element))
                    imgui.pop_item_width()

                    if changed then
                        first_times = {}
                        node_data:get_transition_ids()[i] = tonumber(val)
                    end
                end
            )

            imgui.tree_pop()
        end

        imgui.tree_pop()
    end
    imgui.pop_id()
end

local last_action_update_time = 0
local id_lookup = 0
local duplicate_id = 0

local function cache_tree(core, tree)
    local sorted_nodes = get_sorted_nodes(tree)

    cache_node_indices(sorted_nodes, tree)

    local now = os.clock()

    --if now - last_action_update_time > 0.5 then
    if first_times[tree] == nil then
        first_times[tree] = true
        action_map[tree] = {}
        action_name_map[tree] = {}
        event_map[tree] = {}
        event_name_map[tree] = {}
        condition_map[tree] = {}
        condition_name_map[tree] = {}

        local action_count = tree:get_action_count()
        
        for i=0, action_count-1 do
            local action = tree:get_action(i)
    
            if action ~= nil then
                table.insert(action_map[tree], {index=i, ["action"]=action})
                table.insert(action_name_map[tree], tostring(i) .. ": " .. action:get_type_definition():get_full_name())
            end
        end

        local transition_event_count = tree:get_transition_count()

        for i=0, transition_event_count-1 do
            local evt = tree:get_transition(i)

            if evt ~= nil then
                table.insert(event_map[tree], {index=i, ["event"]=evt})
                table.insert(event_name_map[tree], tostring(i) .. ": " .. evt:get_type_definition():get_full_name())
            end
        end

        local static_condition_count = tree:get_static_condition_count()

        for i=0, static_condition_count-1 do
            local real_index = i | (1 << 30)
            local condition = tree:get_condition(real_index)
    
            if condition ~= nil then
                table.insert(condition_map[tree], {index=real_index, ["condition"]=condition})
                table.insert(condition_name_map[tree], tostring(real_index) .. ": " .. condition:get_type_definition():get_full_name())
            end
        end

        local condition_count = tree:get_condition_count()

        for i=0, condition_count-1 do
            local condition = tree:get_condition(i)
    
            if condition ~= nil then
                table.insert(condition_map[tree], {index=i, ["condition"]=condition})
                table.insert(condition_name_map[tree], tostring(i) .. ": " .. condition:get_type_definition():get_full_name())
            end
        end

        last_action_update_time = os.clock()
    end
end

local function display_tree(core, tree)
    local sorted_nodes = get_sorted_nodes(tree)
    local made = false

    local now = os.clock()

    cache_tree(core, tree)

    changed, duplicate_id = imgui.input_text("Duplicate Action", duplicate_id, 1 << 5)

    if changed then
        first_times = {}

        local id = tonumber(duplicate_id)
        if id < tree:get_action_count() then
            duplicate_global_action(tree, id)
        end
    end

    changed, duplicate_id = imgui.input_text("Duplicate Condition", duplicate_id, 1 << 5)

    if changed then
        first_times = {}

        local id = tonumber(duplicate_id)
        if id < tree:get_condition_count() then
            duplicate_global_condition(tree, id)
        end
    end

    changed, duplicate_id = imgui.input_text("Duplicate Static Condition", duplicate_id, 1 << 5)

    if changed then
        first_times = {}

        local id = tonumber(duplicate_id)
        if id < tree:get_static_condition_count() then
            duplicate_global_static_condition(tree, id)
        end
    end

    changed, id_lookup = imgui.input_text("ID lookup", id_lookup)

    if tonumber(id_lookup) ~= 0 then
        local node = tree:get_node_by_id(tonumber(id_lookup))

        if node ~= nil then
            display_node(tree, node)
        end
    end

    ------------------------------------
    ---------- TREE ACTIONS ------------
    ------------------------------------
    made = imgui.tree_node("Actions")
    imgui.same_line()
    imgui.text(" [" .. tostring(tree:get_action_count()) .. "] ")

    if made then
        if imgui.tree_node("Action Methods") then
            --[[for i=0, tree:get_action_count()-1 do
                local action = tree:get_action(i)
    
                if action ~= nil then
                    display_action(tree, i, nil, tostring(i) .. ": " .. action:get_type_definition():get_full_name(), action)
                end
            end]]
    
            display_bhvt_array(tree, node, tree:get_data():get_action_methods(), 
            function(tree, x) 
                return x
            end, 
            function(tree, i, node, element)
                imgui.text(tostring(i) .. ": " .. tostring(element))
            end)
            
            imgui.tree_pop()
        end

        --[[for i=0, tree:get_action_count()-1 do
            local action = tree:get_action(i)

            if action ~= nil then
                display_action(tree, i, nil, tostring(i) .. ": " .. action:get_type_definition():get_full_name(), action)
            end
        end]]

        display_bhvt_array(tree, node, tree:get_actions(), 
            function(tree, x) 
                return x
            end, 
            function(tree, i, node, element)
                if element ~= nil then
                    display_action(tree, i, nil, tostring(i) .. ": " .. element:get_type_definition():get_full_name(), element)
                else
                    imgui.text(tostring(i) .. ": [ null ]")
                end
            end,
            function(i, element)
                duplicate_global_action(tree, i)
            end
        )
        
        imgui.tree_pop()
    end

    ------------------------------------
    ---------- TREE CONDITIONS ---------
    ------------------------------------
    made = imgui.tree_node("Conditions")
    imgui.same_line()
    imgui.text(" [" .. tostring(tree:get_static_condition_count() + tree:get_condition_count()) .. "] ")

    if made then
        --[[local cond = tree:get_condition(i | (1 << 30))

        if cond ~= nil then
            display_condition(tostring(i | (1 << 30)) .. ": " .. cond:get_type_definition():get_full_name(), cond)
        end]]

        display_bhvt_array(tree, node, tree:get_data():get_static_conditions(), 
            function(tree, x) 
                return x
            end, 
            function(tree, i, node, element)
                if element ~= nil then
                    display_condition(tree, i, nil, tostring(i | (1 << 30)) .. ": " .. element:get_type_definition():get_full_name(), element)
                else
                    imgui.text(tostring(i) .. ": [ null ]")
                end
            end,
            function(i, element)
                duplicate_global_static_condition(tree, i)
            end
        )

        imgui.separator()

        display_bhvt_array(tree, node, tree:get_conditions(), 
            function(tree, x) 
                return x
            end, 
            function(tree, i, node, element)
                if element ~= nil then
                    display_condition(tree, i, nil, tostring(i) .. ": " .. element:get_type_definition():get_full_name(), element)
                else
                    imgui.text(tostring(i) .. ": [ null ]")
                end
            end,
            function(i, element)
                duplicate_global_condition(tree, i)
            end
        )
        
        imgui.tree_pop()
    end

    made = imgui.tree_node("Transition Events")
    imgui.same_line()
    imgui.text(" [" .. tostring(tree:get_static_transition_count() + tree:get_transition_count()) .. "] ")

    if made then
        display_bhvt_array(tree, nil, tree:get_data():get_static_transitions(), 
            function(tree, x) 
                return x
            end, 
            function(tree, i, node, element)
                if element ~= nil then
                    display_event(tree, i, nil, nil, tostring(i | (1 << 30)) .. ": " .. element:get_type_definition():get_full_name(), element)
                else
                    imgui.text(tostring(i) .. ": [ null ]")
                end
            end,
            function(i, element)
                duplicate_global_static_transition_event(tree, i)
            end
        )
        
        imgui.separator()

        display_bhvt_array(tree, nil, tree:get_transitions(),
            function(tree, x) 
                return x
            end, 
            function(tree, i, node, element)
                if element ~= nil then
                    display_event(tree, i, nil, nil, tostring(i) .. ": " .. element:get_type_definition():get_full_name(), element)
                else
                    imgui.text(tostring(i) .. ": [ null ]")
                end
            end,
            function(i, element)
                duplicate_global_transition_event(tree, i)
            end
        )

        imgui.tree_pop()
    end

    --[[if imgui.tree_node("All nodes") then
        for k, node in pairs(sorted_nodes) do
            imgui.push_id(node:get_id())
            if imgui.button(get_node_full_name(node)) then
                last_layer:call("setCurrentNode(System.UInt64, via.behaviortree.SetNodeInfo, via.motion.SetMotionTransitionInfo)", node:get_id(), nil, nil)
            end

            imgui.same_line()
            imgui.text(tostring(node:get_id()))
            imgui.pop_id()
        end

        imgui.tree_pop()
    end]]


    ------------------------------------
    ---------- TREE NODES --------------
    ------------------------------------
    made = imgui.tree_node("Nodes")
    imgui.same_line()
    imgui.text(" [" .. tostring(tree:get_nodes():size()) .. "]")

    if made then
        display_bhvt_array(tree, node, tree:get_nodes(), 
            function(tree, x) 
                return x
            end, 
            function(tree, i, node, element)
                if element ~= nil then
                    display_node(tree, tree:get_node(i), tree:get_nodes(), i)
                else
                    imgui.text(tostring(i) .. ": [ null ]")
                end
            end,
            function(i, element)
                local selectors = {}
                local nodes = tree:get_nodes()
                local nodes_start = nodes[0]:as_memoryview():get_address()
                local nodes_end = nodes[nodes:size()]:as_memoryview():address()
                --[[local element_size = (nodes[nodes:size()]:as_memoryview:address() - nodes_start) / nodes:size()

                log.info("element_size: " .. string.format("%x", element_size))

                for i=0, nodes:size()-1 do
                    local node = tree:get_node(i)
                    local selector = node:get_selector()
                end]]

                tree:get_nodes():push_back(tree:get_nodes()[i])
                core:relocate(nodes_start, nodes_end, tree:get_data():get_nodes())
                tree:get_nodes()[tree:get_nodes():size()-1] = tree:get_nodes()[i]:to_valuetype()
                --tree:get_data():get_nodes():push_back(tree:get_data():get_nodes()[i])
            end
        )

        --[[for k, node in pairs(sorted_nodes) do
            display_node(tree, node)
        end]]

        imgui.tree_pop()
    end

    if imgui.tree_node("Sorted Nodes") then
        for k, node in pairs(sorted_nodes) do
            display_node(tree, node)
        end

        imgui.tree_pop()
    end

    if imgui.tree_node("Root node") then
        display_node(tree, tree:get_node(0))
    end
end

local function display_internal_handle_body(layer, tree, i)
    object_explorer:handle_address(layer)

    imgui.input_text("MotionFsm2Resource", string.format("%x", layer:call("get_MotionFsm2Resource"):read_qword(0x10)))

    display_tree(layer, tree)
end

local function display_core_handle(layer, i)
    last_layer = layer

    local tree = layer:get_tree_object()
    if tree ~= nil then
        if imgui.tree_node("Layer " .. tostring(i)) then
            display_internal_handle_body(layer, tree, i)
            imgui.tree_pop()
        end
    end
end

local custom_addr = 0

re.on_draw_ui(function()
    local player = get_localplayer()
    if not player then return end

    local motion_fsm2 = player:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2"))
    local motion_jack_fsm2 = player:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionJackFsm2"))
    local bhvt = player:call("getComponent(System.Type)", sdk.typeof("via.behaviortree.BehaviorTree"))

    local changed = false
    changed, custom_addr = imgui.input_text("Custom address", custom_addr)

    local custom_obj = sdk.to_managed_object(tonumber(custom_addr))

    if custom_obj ~= nil then
        for i=0, custom_obj:call("getLayerCount")-1 do
            local layer = custom_obj:call("getLayer", i)
            if layer ~= nil then
                display_core_handle(layer, i)
            end
        end
    end
        
    if motion_fsm2 ~= nil and imgui.tree_node("Motion FSM2") then
        object_explorer:handle_address(motion_fsm2:get_address())

        imgui.text(tostring(bhvt) .. " " .. tostring(bhvt:get_address()))

        for i=0, motion_fsm2:call("getLayerCount")-1 do
            local layer = motion_fsm2:call("getLayer", i)
            if layer ~= nil then
                display_core_handle(layer, i)
            end
        end
    
        imgui.tree_pop()
    end

    if motion_jack_fsm2 ~= nil and imgui.tree_node("Motion Jack FSM2") then
        object_explorer:handle_address(motion_jack_fsm2)

        for i=0, motion_jack_fsm2:call("getLayerCount")-1 do
            local layer = motion_jack_fsm2:call("getLayer", i)
            if layer ~= nil then
                display_core_handle(layer, i)
            end
        end
    
        imgui.tree_pop()
    end

    if bhvt ~= nil and imgui.tree_node("Behavior Tree") then
        object_explorer:handle_address(bhvt:get_address())

        imgui.text(tostring(bhvt) .. " " .. tostring(bhvt:get_address()))

        for i, tree in ipairs(bhvt:get_trees()) do
            if tree ~= nil then
                display_core_handle(tree, i)
            end
        end
    end

    last_player = player
end)


local unlock_node_positioning = false

local function draw_link(active, id, attr_start, attr_end)
    if active then
        local alpha = math.floor(math.abs(math.sin(os.clock() * math.pi)) * 255)
        imnodes.push_color_style(7, (alpha << 24) | 0x0000FF00)
        imnodes.link(id, attr_start, attr_end)
        imnodes.pop_color_style()
    else
        imnodes.link(id, attr_start, attr_end)
    end
end

local function draw_stupid_node(name, custom_id, render_inputs_cb, render_outputs_cb, render_after_cb)
    local out = {}

    if custom_id then
        out.id = custom_id
    else
        out.id = imgui.get_id(name)
    end

    out.inputs = {}
    out.outputs = {}

    imnodes.begin_node(out.id)

    imnodes.begin_node_titlebar()
    imgui.text(name)
    imnodes.end_node_titlebar()

    if render_inputs_cb then
        out.inputs = render_inputs_cb()
    end

    if render_outputs_cb then
        out.outputs = render_outputs_cb()
    end

    if render_after_cb then
        render_after_cb()
    end

    imnodes.end_node()

    return out
end

local function draw_standard_node(name, custom_id, render_after_cb)
    local out = draw_stupid_node(name, custom_id,
        function()
            local out2 = {}

            if custom_id then
                table.insert(out2, imgui.get_id(tostring(custom_id) .. "parent"))
            else
                table.insert(out2, imgui.get_id(name .. "parent"))
            end
        
            imnodes.begin_input_attribute(out2[1])
            imgui.text("parent")
            imnodes.end_input_attribute()

            return out2
        end,
        function()
            local out2 = {}

            if custom_id then
                table.insert(out2, imgui.get_id(tostring(custom_id) .. "children"))
            else
                table.insert(out2, imgui.get_id(name .. "children"))
            end
        
            imnodes.begin_output_attribute(out2[1])
            imgui.indent(math.max(imgui.calc_text_size(name).x, 60))
            imgui.text("children")
            imnodes.end_output_attribute()

            return out2
        end,
        function()
            if render_after_cb then
                render_after_cb()
            end
            --imgui.text(tostring(imnodes.get_node_dimensions(imgui.get_id(name)).y))
        end
    )

    return out
end

local custom_tree = {
    {
        name = "root",
        children = { 2, 3, 4, 5 }
    },
    {
        name = "node2",
        children = { 21 }
    },
    {
        name = "node3",
        children = {}
    },
    {
        name = "node4",
        children = { 10, 11, 12, 13 }
    },
    {
        name = "node5",
        children = { 6, 7, 8, 9, 16, 17 }
    },
    {
        name = "node6",
        children = {}
    },
    {
        name = "node7",
        children = { 15, 18 }
    },
    {
        name = "node8",
        children = {}
    },
    {
        name = "node9",
        children = {}
    },
    {
        name = "node10",
        children = {}
    },
    {
        name = "node11",
        children = {}
    },
    {
        name = "node12",
        children = {}
    },
    {
        name = "node13",
        children = {}
    },
    {
        name = "node14",
        children = {}
    },
    {
        name = "node15",
        children = { 14 }
    },
    {
        name = "node16",
        children = {  }
    },
    {
        name = "node17",
        children = {  }
    },
    {
        name = "node18",
        children = { 19, 20 }
    },
    {
        name = "node19",
        children = {  }
    },
    {
        name = "node20",
        children = {  }
    },
    {
        name = "node21",
        children = {  }
    }
}

local updated_tree = false
local node_is_hovered = false
local node_hovered_id = 0
local node_map = {}

local draw_node_children = nil
local draw_node = nil

local active_tree = nil
local last_time = 0.0
local delta_time = 0.0

-- Draw children and compute space requirements
draw_node_children = function(i, node, seen, active)
    seen = seen or {}
    if seen[node] then return end

    local node_descriptor = custom_tree[i]

    --[[if not node_descriptor.children or #node_descriptor.children == 0 then
        return { x=0, y=0 }
    end]]

    local node_pos = imnodes.get_node_grid_space_pos(node.id)
    local node_dims = imnodes.get_node_dimensions(node.id)

    local out_dim_requirements = { x=0, y=0 }

    for j, child_id in ipairs(node_descriptor.children) do
        local child, node_dim_requirements, child_active = draw_node(child_id, seen)
        -- Y needs to be dynamic
        local child_render_pos = {
            x = node_pos.x + node_dims.x + 20,
            y = node_pos.y + out_dim_requirements.y
            --y = node_pos.y - ((#node_descriptor.children - 1) * (node_dims.y / 2)) + node_dim_requirements.y + ((j-1) * node_dims.y)
        }

        if not unlock_node_positioning then
            if cfg.lerp_nodes then
                local current_child_pos = imnodes.get_node_grid_space_pos(child.id)

                local crp = Vector2f.new(child_render_pos.x, child_render_pos.y)
                local dist = (current_child_pos - crp):length()

                if dist < 20 then
                    crp = current_child_pos + ((crp - current_child_pos) * math.min(delta_time, 0.5))
                else
                    crp = current_child_pos + ((crp - current_child_pos):normalized() * math.min(math.min(delta_time, 0.5) * dist * cfg.lerp_speed * 10.0, dist))
                end

                imnodes.set_node_grid_space_pos(child.id, crp.x, crp.y)
            else
                imnodes.set_node_grid_space_pos(child.id, child_render_pos.x, child_render_pos.y)
            end
        end

        local link_id = imgui.get_id(node_descriptor.name .. custom_tree[child_id].name .. "LINK")

        if node_is_hovered then
            if node_hovered_id == node_map[i].id then
                draw_link(false, link_id, node_map[i].outputs[1], node_map[child_id].inputs[1])
            end

            if node_hovered_id == node_map[child_id].id then
                draw_link(false, link_id, node_map[i].outputs[1], node_map[child_id].inputs[1])
            end
        elseif active and child_active then
            draw_link(active, link_id, node_map[i].outputs[1], node_map[child_id].inputs[1])
        end

        out_dim_requirements.x = out_dim_requirements.x + node_dim_requirements.x
        out_dim_requirements.y = out_dim_requirements.y + node_dim_requirements.y --[[+ (imnodes.get_node_dimensions(child.id).y * #custom_tree[child_id].children)]]
        --out_dim_requirements.y = out.y + imnodes.get_node_dimensions(child_node.id).y
    end

    -- Only add the node dimensions to the out dim requirements
    -- if the node has no children, meaning it's the end of the chain
    if #node_descriptor.children == 0 then
        out_dim_requirements.y = out_dim_requirements.y + node_dims.y + 5
    else
        if node_dims.y > out_dim_requirements.y then
            out_dim_requirements.y = node_dims.y + 5
        end
    end

    return out_dim_requirements, active
end

draw_node = function(i, seen)
    seen = seen or {}
    if seen[i] then return end
    if not custom_tree[i] then return end

    local custom_id = nil

    if active_tree ~= nil then
        custom_id = active_tree:get_node(i):get_id()
    end

    local node_descriptor = custom_tree[i]
    local node = draw_standard_node(
        "[" .. tostring(i) .. "]" .. node_descriptor.name, 
        custom_id,
        function()
            if not node_map[i] then return end

            if active_tree then
                --imgui.text(tostring(active_tree:get_node(i)))
                --if imgui.begin_child_window("Test" .. tostring(i), 100, 100) then
                    display_node(active_tree, active_tree:get_node(i))
                    --imgui.end_child_window()
                --end
            end
        end
    )

    --[[if imgui.begin_popup_context_item(node_descriptor.name, 1) then
        if active_tree ~= nil then
            if imgui.button("Isolate") then
                queued_editor_id_move = {["i"] = i, ["id"] = active_tree:get_node(i):get_id()}
            end

            if imgui.button("Display parent") then
                queued_editor_id_move = {["i"] = active_tree:get_node(i):get_data().parent, ["id"] = active_tree:get_node(active_tree:get_node(i):get_data().parent):get_id()}
            end
        end

        imgui.end_popup()
    end]]

    node_map[i] = node

    local active = false

    if active_tree ~= nil then
        local real_node = active_tree:get_node(i)

        active = real_node:get_status1() == 2 or real_node:get_status2() == 2
    end

    return node, draw_node_children(i, node, seen, active)
end

local last_editor_size = Vector2f.new(0, 0)
local was_hovering_sidebar = false
local queued_editor_id_move_step2 = nil
local queued_editor_id_start_time = os.clock()
local SIDEBAR_BASE_WIDTH = 500

local panning_decay = Vector2f.new(0, 0)

local HORIZONTAL_ARROW_INDENT = 50

local VERTICAL_ARROW_INDENT = math.floor(HORIZONTAL_ARROW_INDENT / 2)

local function perform_panning()

    local panning = imnodes.editor_get_panning()
    local new_panning = panning:clone()

    imgui.indent(VERTICAL_ARROW_INDENT)

    local arrow_active = function(name, idx)
        return imgui.arrow_button(name, idx) or imgui.is_item_active()
    end

    if arrow_active("Pan_Up", 2) or imgui.is_key_down(UP_ARROW) then
        new_panning.y = panning.y + cfg.pan_speed  * delta_time
    end

    imgui.unindent(VERTICAL_ARROW_INDENT)

    if arrow_active("Pan_Left", 0) or imgui.is_key_down(LEFT_ARROW) then
        new_panning.x = panning.x + cfg.pan_speed * delta_time
    end

    
    imgui.same_line()
    imgui.indent(HORIZONTAL_ARROW_INDENT)


    if arrow_active("Pan_Right", 1) or imgui.is_key_down(RIGHT_ARROW) then
        new_panning.x = panning.x - cfg.pan_speed * delta_time
    end

    imgui.unindent(HORIZONTAL_ARROW_INDENT)
    imgui.indent(VERTICAL_ARROW_INDENT)

    if arrow_active("Pan_Down", 3) or imgui.is_key_down(DOWN_ARROW) then
        new_panning.y = panning.y - cfg.pan_speed * delta_time
    end

    imgui.unindent(VERTICAL_ARROW_INDENT)

    local panning_delta = new_panning - panning

    panning_decay = panning_decay + ((panning_delta - panning_decay) * (delta_time))

    if panning_decay:length() > 0 then
        panning = imnodes.editor_get_panning()
        panning_decay = panning_decay * 0.999999 * (1.0 - delta_time)
        imnodes.editor_reset_panning(panning.x + panning_decay.x, panning.y + panning_decay.y)
    end
end

local function move_to_node(id)
    imnodes.editor_move_to_node(id)

    local panning = imnodes.editor_get_panning()
    local node_dims =  imnodes.get_node_dimensions(id)

    local wnd = imgui.get_window_size()

    local new_panning = {
        x = math.floor(panning.x+(wnd.x / 2) - (node_dims.x / 2)),
        y = math.floor(panning.y+(wnd.y / 2) - (node_dims.y / 2))
    }

    imnodes.editor_reset_panning(new_panning.x, new_panning.y)
end

local function set_base_node_to_parent(tree, i)
    local prev_default = cfg.default_node

    if cfg.display_parent_of_active and i > 0 then
        local node = tree:get_node(i)
        if not node then return end

        local parent_i = node:get_data().parent

        if parent_i > 0 then
            cfg.default_node = parent_i
        else
            cfg.default_node = i
        end

        if parent_i > 0 then
            for j=0, cfg.parent_display_depth-1 do
                local parent_node = tree:get_node(cfg.default_node)

                if parent_node then
                    local parent = parent_node:get_data().parent

                    if parent ~= 0 then
                        cfg.default_node = parent
                    else
                        break
                    end
                else
                    break
                end
            end
        end
    else
        cfg.default_node = i
    end
end

local last_search_results_node = {}
local last_search_results_condition = {}
local last_search_results_action = {}
local last_search_results_set = {} -- to prevent duplicates in the search (optional)

local function draw_stupid_editor(name)
    if cfg.graph_closes_with_reframework then
        if not reframework:is_drawing_ui() then return end
    end

    if not imgui.begin_window(name, true, 1 << 10) then return end
    --[[if not imgui.begin_child_window(name .. "2") then 
        imgui.end_window()
        return 
    end]]

    local tree = nil
    local layer = nil

    local player = get_localplayer()

    if player ~= nil then
        local motion_fsm2 = player:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2"))

        if motion_fsm2 ~= nil then
            layer = motion_fsm2:call("getLayer", 0)

            if layer ~= nil then
                tree = layer:get_tree_object()

                if tree ~= nil then
                end
            end
        end
    end

    local changed = false
    local now = os.clock()

    if imgui.begin_menu_bar() then
        if imgui.begin_menu("File") then
            imgui.text("This literally does nothing.")

            imgui.end_menu()
        end

        if imgui.begin_menu("View") then
            changed, cfg.graph_closes_with_reframework = imgui.checkbox("Graph closes with REFramework", cfg.graph_closes_with_reframework)
            changed, cfg.show_side_panels = imgui.checkbox("Show side panel", cfg.show_side_panels)
            changed, unlock_node_positioning = imgui.checkbox("Unlock Node Positioning", unlock_node_positioning)
            changed, cfg.show_minimap = imgui.checkbox("Show Minimap", cfg.show_minimap)
    
            changed, cfg.follow_active_nodes = imgui.checkbox("Follow Active Nodes", cfg.follow_active_nodes)
            changed, cfg.display_parent_of_active = imgui.checkbox("Display Parent of Active", cfg.display_parent_of_active)
            changed, cfg.parent_display_depth = imgui.slider_int("Parent Display Depth", cfg.parent_display_depth, 0, 10)

            imgui.end_menu()
        end

        if imgui.begin_menu("Search") then
            imgui.text("Results will initially show as tooltips.")
            imgui.text("Press enter to interact with the results.")

            changed, cfg.search_allow_duplicates = imgui.checkbox("Allow Duplicates in Search", cfg.search_allow_duplicates)
            changed, cfg.max_search_results = imgui.slider_int("Max Results", cfg.max_search_results, 1, 1000)
            changed, cfg.default_node_search_name = imgui.input_text("Node Search (Name, ID, or Index)", cfg.default_node_search_name)
            local search_by_name_active = imgui.is_item_active()

            --------------------------------------------------
            ---------------- NODE SEARCH----------------------
            --------------------------------------------------
            if changed then
                last_search_results_set = {}
                last_search_results_node = {}
                last_search_results_action = {}
                last_search_results_condition = {}
                local already_set = false

                for i, v in ipairs(custom_tree) do
                    local name = v.name:lower()
                    local search_name = cfg.default_node_search_name:lower()
                    local id = tree:get_node(i):get_id()

                    if name:find(search_name) or search_name == tostring(id) or search_name == tostring(i) then
                        local node = tree:get_node(i)

                        if node then

                            if not cfg.search_allow_duplicates then
                                if not last_search_results_set[get_node_full_name(node)] then
                                    table.insert(last_search_results_node, node)
                                    last_search_results_set[get_node_full_name(node)] = true
                                end
                            else
                                table.insert(last_search_results_node, node)
                            end
                        end

                        if not already_set then
                            queued_editor_id_move = {["i"] = i, ["id"] = id}
                            already_set = true
                        end

                        -- Limit the search results to 200 and break out early
                        if #last_search_results_node > cfg.max_search_results then
                            break
                        end
                    end
                end
            end

            --------------------------------------------------
            ---------------- CONDITION SEARCH-----------------
            --------------------------------------------------
            changed, cfg.default_condition_search_name = imgui.input_text("Condition Search (Name, Index)", cfg.default_condition_search_name)
            search_by_name_active = search_by_name_active or imgui.is_item_active()

            if changed then
                last_search_results_set = {}
                last_search_results_node = {}
                last_search_results_action = {}
                last_search_results_condition = {}

                for i=0, tree:get_static_condition_count()-1 do
                    local real_index = i | (1 << 30)
                    local condition = tree:get_condition(real_index)

                    if condition then
                        local name = condition:get_type_definition():get_full_name():lower()
                        local search_name = cfg.default_condition_search_name:lower()

                        if name:find(search_name) or search_name == tostring(i) then
                            if not cfg.search_allow_duplicates then
                                if last_search_results_set[name] == nil then
                                    table.insert(last_search_results_condition, { ["i"] = real_index, cond = condition })
                                    last_search_results_set[name] = true
                                end
                            else
                                table.insert(last_search_results_condition, { ["i"] = real_index, cond = condition })
                            end

                            -- Limit the search results to 200 and break out early
                            if #last_search_results_condition > cfg.max_search_results then
                                break
                            end
                        end
                    end
                end

                for i=0, tree:get_condition_count()-1 do
                    local condition = tree:get_condition(i)

                    if condition then
                        local name = condition:get_type_definition():get_full_name():lower()
                        local search_name = cfg.default_condition_search_name:lower()

                        if name:find(search_name) or search_name == tostring(i) then
                            if not cfg.search_allow_duplicates then
                                if last_search_results_set[name] == nil then
                                    table.insert(last_search_results_condition, { ["i"] = i, cond = condition })
                                    last_search_results_set[name] = true
                                end
                            else
                                table.insert(last_search_results_condition, { ["i"] = i, cond = condition })
                            end

                            -- Limit the search results to 200 and break out early
                            if #last_search_results_condition > cfg.max_search_results then
                                break
                            end
                        end
                    end
                end
            end

            --------------------------------------------------
            ---------------- ACTION SEARCH--------------------
            --------------------------------------------------
            changed, cfg.default_action_search_name = imgui.input_text("Action Search (Name, Index)", cfg.default_action_search_name)
            search_by_name_active = search_by_name_active or imgui.is_item_active()

            if changed then
                last_search_results_set = {}
                last_search_results_node = {}
                last_search_results_action = {}
                last_search_results_condition = {}

                for i=0, tree:get_static_action_count() - 1 do
                    local real_index = i | (1 << 30)
                    local action = tree:get_action(real_index)

                    if action then
                        local name = action:get_type_definition():get_full_name():lower()
                        local search_name = cfg.default_action_search_name:lower()

                        if name:find(search_name) or search_name == tostring(i) then
                            if not cfg.search_allow_duplicates then
                                if last_search_results_set[name] == nil then
                                    table.insert(last_search_results_action, { ["i"] = real_index, act = action })
                                    last_search_results_set[name] = true
                                end
                            else
                                table.insert(last_search_results_action, { ["i"] = real_index, act = action })
                            end

                            -- Limit the search results to 200 and break out early
                            if #last_search_results_action > cfg.max_search_results then
                                break
                            end
                        end
                    end
                end

                for i=0, tree:get_action_count()-1 do
                    local action = tree:get_action(i)

                    if action then
                        local name = action:get_type_definition():get_full_name():lower()
                        local search_name = cfg.default_action_search_name:lower()

                        if name:find(search_name) or search_name == tostring(i) then
                            if not cfg.search_allow_duplicates then
                                if last_search_results_set[name] == nil then
                                    table.insert(last_search_results_action, { ["i"] = i, act = action })
                                    last_search_results_set[name] = true
                                end
                            else
                                table.insert(last_search_results_action, { ["i"] = i, act = action })
                            end

                            -- Limit the search results to 200 and break out early
                            if #last_search_results_action > cfg.max_search_results then
                                break
                            end
                        end
                    end
                end
            end

            --------------------------------------------------
            ---------------- SEARCH RESULTS ------------------
            --------------------------------------------------
            if imgui.is_key_pressed(ENTER) then
                imgui.open_popup("Search_Results_Name")
            elseif not imgui.is_popup_open("Search_Results_Name") and search_by_name_active then
                -- Display a tooltip instead of a popup.
                imgui.begin_tooltip()
                    for i, node in ipairs(last_search_results_node) do
                        display_node(tree, node)
                    end

                    for i, cond in ipairs(last_search_results_condition) do
                        display_condition(tree, nil, nil, tostring(cond.i) .. ": " .. cond.cond:get_type_definition():get_full_name(), cond.cond)
                    end

                    for i, act in ipairs(last_search_results_action) do
                        display_action(tree, act.i, nil, act.act:get_type_definition():get_full_name(), act.act)
                    end
                imgui.end_tooltip()
            end

            if imgui.begin_popup("Search_Results_Name") then
                for i, node in ipairs(last_search_results_node) do
                    display_node(tree, node)
                end
    
                for i, cond in ipairs(last_search_results_condition) do
                    display_condition(tree, nil, nil, tostring(cond.i) .. ": " .. cond.cond:get_type_definition():get_full_name(), cond.cond)
                end

                for i, act in ipairs(last_search_results_action) do
                    display_action(tree, act.i, nil, act.act:get_type_definition():get_full_name(), act.act)
                end

                imgui.end_popup()
            end

            imgui.end_menu()
        end

        if imgui.begin_menu("Editor") then
            if imgui.begin_menu("Lerp Settings") then
                changed, cfg.lerp_nodes = imgui.checkbox("Lerp Nodes", cfg.lerp_nodes)
                changed, cfg.lerp_speed = imgui.slider_float("Lerp Speed", cfg.lerp_speed, 0, 5.0)

                imgui.end_menu()
            end

            if imgui.begin_menu("Pan Settings") then
                changed, cfg.pan_speed = imgui.slider_float("Pan Speed", cfg.pan_speed, 100.0, 5000.0)
                
                imgui.end_menu()
            end

            imgui.end_menu()
        end

        if imgui.begin_menu("About") then
            imgui.text("An editor/viewer for the RE Engine's behavior tree/finite state machine system.")
            imgui.text("Author: praydog")
            imgui.text("https://github.com/praydog/REFramework")

            imgui.end_menu()
        end

        -- Selected node
        imgui.separator()
        imgui.text(tostring(#imnodes.get_selected_nodes()) .. " selected nodes")

        -- Display node
        imgui.separator()
        imgui.push_item_width(100)
        changed, cfg.default_node = imgui.slider_int("Display Node", cfg.default_node, 0, #custom_tree)
        if changed and tree ~= nil and cfg.default_node < tree:get_node_count() then
            queued_editor_id_move = {["i"] = cfg.default_node, ["id"] = tree:get_node(cfg.default_node):get_id()}
        end

        imgui.pop_item_width()

        imgui.separator()

        imgui.end_menu_bar()
    end

    if (tree ~= nil and (active_tree == nil or tree:as_memoryview():address() ~= active_tree:as_memoryview():address())) then
        custom_tree = {}
        updated_tree = true
        active_tree = tree        

        for i=0, tree:get_node_count()-1 do
            local node = tree:get_node(i)

            if node then
                local insertion = {
                    name = node:get_full_name(),
                    children = {}
                }

                for j=0, #node:get_data():get_children()-1 do
                    local child_index = node:get_data():get_children()[j]
                    table.insert(insertion.children, child_index)
                end

                table.sort(insertion.children)

                custom_tree[i] = insertion
            end
        end
    end

    if layer ~= nil and tree ~= nil then
        last_layer = layer
        cache_tree(layer, tree)
    end

    if cfg.show_side_panels then
        local ws = imgui.get_window_size()

        local made_child = false
        
        if was_hovering_sidebar then
            made_child = imgui.begin_child_window("SidePanel",  Vector2f.new(math.max(ws.x / 4, SIDEBAR_BASE_WIDTH), 0), true, 1 << 6)
        else
            made_child = imgui.begin_child_window("SidePanel",  Vector2f.new(math.min(ws.x / 8, SIDEBAR_BASE_WIDTH), 0), true, 1 << 6)
        end

        if made_child then
            -- Search
            --[[if imgui.begin_child_window("Search", Vector2f.new(SIDEBAR_BASE_WIDTH, 100), true) then

                changed, cfg.default_node = imgui.slider_int("Node to Draw", cfg.default_node, 0, #custom_tree)
    
                if changed then
                    for k, v in pairs(custom_tree) do
                        if v.name == cfg.default_node_search_name then
                            cfg.default_node = k
                            break
                        end
                    end
                end
    
                imgui.end_child_window()
            end]]

            -- Tree overview
            if layer ~= nil and tree ~= nil then
                if imgui.begin_child_window("Tree", Vector2f.new(SIDEBAR_BASE_WIDTH, ws.y - 50), true) then
                    last_layer = layer
                    display_internal_handle_body(layer, tree, 0)
                    imgui.end_child_window()
                end
            end

            was_hovering_sidebar = imgui.is_item_hovered((1 << 5))

            imgui.end_child_window()

            was_hovering_sidebar = was_hovering_sidebar or imgui.is_item_hovered((1 << 5))
        else
            was_hovering_sidebar = false
        end

        imgui.same_line()
    end

    imnodes.begin_node_editor()

    perform_panning()

    if layer ~= nil and tree ~= nil then
        if queued_editor_id_move ~= nil then
            local node = tree:get_node(queued_editor_id_move.i)

            if node then
                --[[if queued_editor_id_move.i > 0 then
                    local parent = node:get_data().parent

                    if parent > 0 then
                        cfg.default_node = parent
                    else
                        cfg.default_node = queued_editor_id_move.i
                    end
                else
                    cfg.default_node = queued_editor_id_move.i
                end]]

                set_base_node_to_parent(tree, queued_editor_id_move.i)
                queued_editor_id_move_step2 = queued_editor_id_move.id
                queued_editor_id_start_time = os.clock()
                cfg.follow_active_nodes = false
            end

            queued_editor_id_move = nil
        end

        if cfg.follow_active_nodes then
            for i=0, tree:get_node_count()-1 do
                local node = tree:get_node(i)

                if (node:get_status1() == 2 or node:get_status2() == 2) and #node:get_children() == 0 then
                    local prev_default = cfg.default_node

                    set_base_node_to_parent(tree, i)

                    queued_editor_id_move_step2 = node:get_id()
                    queued_editor_id_start_time = os.clock()

                    break
                end
            end
        end
    end

    -- draw_node draws all children, so only draw the root node
    if cfg.default_node == 0 then
        if custom_tree[0] then
            if node_map[0] and not unlock_node_positioning then
                imnodes.set_node_grid_space_pos(node_map[0].id, 0, 0)
            end

            local node, req, active = draw_node(0)
        else
            if node_map[1] and not unlock_node_positioning then
                imnodes.set_node_grid_space_pos(node_map[1].id, 0, 0)
            end

            draw_node(1)
        end
    else
        draw_node(cfg.default_node)
    end

    if queued_editor_id_move_step2 ~= nil then
        move_to_node(queued_editor_id_move_step2)

        if os.clock() - queued_editor_id_start_time > 1.0 then
            queued_editor_id_move_step2 = nil
        end
    end

    if cfg.show_minimap then
        imnodes.minimap(0.5, 0)
    end

    -- Editor context menu
    if not node_is_hovered then
        if not imgui.is_popup_open("", (1 << 7) | (1 << 8)) then
            if imnodes.is_editor_hovered() and imgui.is_mouse_released(1) then
                imgui.open_popup("EditorContextMenu")
            end

            if imgui.begin_popup("EditorContextMenu") then
                if imgui.button("Recenter") and tree ~= nil then
                    queued_editor_id_move = {["i"] = cfg.default_node, ["id"] = tree:get_node(cfg.default_node):get_id()}
                end

                imgui.end_popup()
            end
        end
    end

    imnodes.end_node_editor()


    node_is_hovered, node_hovered_id = imnodes.is_node_hovered()
    node_hovered_id = node_hovered_id & 0xFFFFFFFF

    last_editor_size = imgui.get_window_size()

    --imgui.end_window()
    imgui.end_window()
end

local EDITOR_SIZE = {
    x = math.max(imgui.get_display_size().x / 4, 640),
    y = math.max(imgui.get_display_size().y / 2, 480)
}

re.on_frame(function()
    imgui.push_style_var(ImGuiStyleVar.ImGuiStyleVar_WindowRounding, 10.0)

    delta_time = os.clock() - last_time

    local disp_size = imgui.get_display_size()
    imgui.set_next_window_size({EDITOR_SIZE.x, EDITOR_SIZE.y}, 1 << 1) -- ImGuiCond_Once
    imgui.set_next_window_pos({disp_size.x / 2 - (EDITOR_SIZE.x / 2), disp_size.y / 2 - (EDITOR_SIZE.y / 2)}, 1 << 1)
    draw_stupid_editor("Behavior Tree Editor v0.1337")

    last_time = os.clock()

    imgui.pop_style_var()
end)