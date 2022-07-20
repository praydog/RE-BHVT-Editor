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

local function recreate_globals()
    action_map = {}
    action_name_map = {}
    event_map = {}
    event_name_map = {}
    condition_map = {}
    condition_name_map = {}
    selection_map = {}
    condition_selection_map = {}
    node_map = {}
    node_names = {}
    first_times = {}
    sort_dict = {}
end

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
            local name_start = 5

            local is_potential_getter = getter:get_num_params() == 0 and getter:get_name():find("get") == 1

            if is_potential_getter and not getter:get_name():find("get_") and getter:get_name():find("get") == 1 then
                name_start = 4
            end

            if is_potential_getter then -- start of string
                local isolated_name = getter:get_name():sub(name_start)
                local setter = td:get_method("set_" .. isolated_name) or td:get_method("set" .. isolated_name)

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

    if sort_dict[tree] ~= nil and tree:get_node_count() == #sort_dict[tree] then
        local res = sort_dict[tree]

        if res ~= nil then
            return res
        end
    end

    log.debug("Sorting nodes for tree " .. string.format("%x", tree:as_memoryview():address()))

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

local function display_hook(metaname, hook_tbl, obj, creation_function)
    local hook = hook_tbl[obj]

    if not hook then
        if imgui.button("Add Lua Driven " .. metaname) then
            creation_function(obj)
        end
    else
        imgui.text("Press CTRL+Enter for the changes to take effect.")

        local changed = false

        local cursor_screen_pos = imgui.get_cursor_screen_pos()
        changed, hook.payload = imgui.input_text_multiline(metaname, hook.payload)

        if imgui.begin_popup_context_item(metaname .. "_popup") then
            if imgui.button("Remove " .. metaname) then
                hook_tbl[obj] = nil
            end

            imgui.end_popup()
        end

        if not hook.init or not hook.func then
            hook.init, hook.err = load(hook.payload)

            if not hook.err then
                hook.err, hook.func = pcall(hook.init)
            end
        end

        if imgui.is_item_active() then
            imgui.open_popup(tostring(obj) .. ": " .. metaname)
        end

        local last_input_width = imgui.calc_item_width()

        -- Causes the textbox to be overlayed on top of the existing textbox
        -- because for some reason the textbox inside the node doesn't accept TAB input
        -- however, the popup version does.
        imgui.set_next_window_pos(cursor_screen_pos)

        if imgui.begin_popup(tostring(obj) .. ": " .. metaname, (1 << 18) | (1 << 19)) then
            
            imgui.set_next_item_width(last_input_width)
            changed, hook.payload, tstart, tend = imgui.input_text_multiline(metaname, hook.payload, {0,0}, (1 << 5) | (1 << 10) | (1 << 8))
    
            if changed then
                hook.init, hook.err = load(hook.payload)

                if not hook.err then
                    hook.err, hook.func = pcall(hook.init)
                end
            end

            if imgui.begin_popup_context_item(metaname .. "_popup2") then
                if imgui.button("Remove " .. metaname) then
                    hook_tbl[obj] = nil
                end

                imgui.end_popup()
            end
    
            imgui.end_popup()
        end


        --[[if changed then
            local err = nil
            custom_condition_evaluators[cond].eval, custom_condition_evaluators[cond].err = load(custom_condition_evaluators[cond].str)
            
        end]]
        if hook.err then
            imgui.text(hook.err)
        end
    end
end

local action_hooks = {
    storage = {},
    start = {
        default_payload = "return function(storage, action, arg)\nend"
    },
    update = {
        default_payload = "return function(storage, action, arg)\nend"
    },
    ["end"] = {
        default_payload = "return function(storage, action, arg)\nend"
    },
}

local custom_action_start_hooks = {}

local function add_action_hook(hook_name, action, payload, postfunc)
    if not action_hooks[hook_name] then
        log.debug("Unknown action hook " .. hook_name)
        return
    end

    if payload == nil then
        payload = action_hooks[hook_name].default_payload
    end

    local hook = action_hooks[hook_name][action]

    if hook == nil then
        action_hooks[hook_name][action] = {}

        hook = action_hooks[hook_name][action]

        -- Only hook function once if it didn't exist before.
        local add_start = function()
            local prev_args = nil
    
            sdk.hook_vtable(
                action, 
                action:get_type_definition():get_method(hook_name), 
                function(args)
                    prev_args = args
                end,
                function(retval)
                    local hook = action_hooks[hook_name][action]
                    if not hook then
                        return retval
                    end
    
                    return hook.func(action_hooks.storage, table.unpack(postfunc(prev_args, retval)))
                end
            )
        end
    
        add_start()
    end

    hook.payload = payload
    hook.init, hook.err = load(hook.payload)

    if not hook.err then
        hook.err, hook.func = pcall(hook.init)

        if hook.err == false then
            log.debug("Error in " .. hook_name .. " hook for action: " .. tostring(hook.err) .. " " .. tostring(hook.func))
            log.error("Error in " .. hook_name .. " hook for action: " .. tostring(hook.err) .. " " .. tostring(hook.func))
            hook.err = hook.func
            hook.func = nil
        end
    else
        hook.func = nil
    end
end

local function add_action_start_hook(action, payload)
    add_action_hook("start", action, payload, function(prev_args, retval)
        return { 
                sdk.to_managed_object(prev_args[2]), 
                sdk.to_managed_object(prev_args[3])
            }
    end)
end

local function add_action_update_hook(action, payload)
    add_action_hook("update", action, payload, function(prev_args, retval)
        return { 
                sdk.to_managed_object(prev_args[2]), 
                sdk.to_managed_object(prev_args[3])
            }
    end)
end

local function add_action_end_hook(action, payload)
    add_action_hook("end", action, payload, function(prev_args, retval)
        return { 
                sdk.to_managed_object(prev_args[2]), 
                sdk.to_managed_object(prev_args[3])
            }
    end)
end

local replace_action_id_text = ""

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
        display_hook("Start", action_hooks.start, action, add_action_start_hook)
        display_hook("Update", action_hooks.update, action, add_action_update_hook)
        display_hook("End", action_hooks["end"], action, add_action_end_hook)

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

local custom_condition_evaluators = {}

local function add_condition_hook(cond, eval_payload)
    if eval_payload == nil then
        eval_payload = "return function(storage, cond, arg, retval)\n\treturn retval\nend"
    end

    local hook = custom_condition_evaluators[cond]

    if hook == nil then
        custom_condition_evaluators[cond] = {}
        custom_condition_evaluators[cond].storage = {}

        hook = custom_condition_evaluators[cond]

        -- Only hook function once if it didn't exist before.
        local add_evaluator = function()
            local prev_args = nil
    
            sdk.hook_vtable(
                cond, 
                cond:get_type_definition():get_method("evaluate"), 
                function(args)
                    prev_args = args
                end,
                function(retval)
                    local hook = custom_condition_evaluators[cond]
                    if not hook then
                        return retval
                    end

                    local old_retval = (sdk.to_int64(retval) & 1) == 1
                    local new_retval = 
                        hook.eval(
                            hook.storage,
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

    hook.eval_str = eval_payload
    hook.eval_init, hook.err = load(hook.eval_str)

    if not hook.err then
        hook.eval = hook.eval_init()
    else
        hook.eval = nil
    end
end

local replace_condition_id_text = ""

local function display_condition(tree, i, node, name, cond)
    if cond ~= nil then
        -- These are pretty opaque without metadata, so we need to display the name next to the condition.
        if cond:get_type_definition():is_a("via.behaviortree.ConditionUserVariable") then
            local guid = cond:get_Expression()
            local uvar_hub = tree:get_uservariable_hub()
            local uvar = uvar_hub:call("findVariable(System.Guid)", guid)
            if uvar ~= nil then
                name = name .. ": [" .. uvar:get_Name() .. "]"
            end
        end
    end

    if imgui.tree_node(name) then
        if not custom_condition_evaluators[cond] then
            if imgui.button("Add Lua Driven Evaluator") then
                add_condition_hook(cond)
            end
        else
            imgui.text("Press CTRL+Enter for the changes to take effect.")

            local hook = custom_condition_evaluators[cond]
            local changed = false

            local cursor_screen_pos = imgui.get_cursor_screen_pos()
            changed, hook.eval_str = imgui.input_text_multiline("Evaluator", custom_condition_evaluators[cond].eval_str)

            if imgui.begin_popup_context_item("evaluator_popup") then
                if imgui.button("Remove Evaluator") then
                    custom_condition_evaluators[cond] = nil
                end

                imgui.end_popup()
            end

            if not hook.eval_init or not hook.eval then
                hook.eval_init, hook.err = load(hook.eval_str)

                if not hook.err then
                    hook.eval = hook.eval_init()
                end
            end
    
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
                changed, hook.eval_str, tstart, tend = imgui.input_text_multiline("Evaluator", hook.eval_str, {0,0}, (1 << 5) | (1 << 10) | (1 << 8))
        
                if changed then
                    local err = nil
                    hook.eval_init, hook.err = load(hook.eval_str)

                    if not hook.err then
                        hook.eval = hook.eval_init()
                    end
                end

                if imgui.begin_popup_context_item("evaluator_popup2") then
                    if imgui.button("Remove Evaluator") then
                        custom_condition_evaluators[cond] = nil
                    end
    
                    imgui.end_popup()
                end
        
                imgui.end_popup()
            end
    
    
            --[[if changed then
                local err = nil
                custom_condition_evaluators[cond].eval, custom_condition_evaluators[cond].err = load(custom_condition_evaluators[cond].str)
                
            end]]
            if hook.err then
                imgui.text(hook.err)
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

            changed = imgui.button("Add Dummy Action")

            if changed then
                first_times = {}

                tree:get_actions():push_back(sdk.create_instance("via.behaviortree.Action"):add_ref_permanent())
                tree:get_data():get_action_methods():push_back(1 | 2 | 4 | 8 | 16 | 32)

                node_data:get_actions():push_back(tree:get_action_count() - 1)
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
                                if element_tree ~= nil then
                                    display_event(tree, i, j, node, tostring(evts[j]) .. ": " .. tostring(element_tree:get_type_definition():get_full_name()), element_tree) -- TODO, DO THAT ONE!
                                else
                                    imgui.text(tostring(evts[j]) .. ": [ NULL ] (WILL CRASH, REMOVE THIS EVENT)")
                                end
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
local action_add_class_name = "via.behaviortree.Action"

local function cache_tree(core, tree)
    if first_times[tree] == nil then
        cached_node_indices = {}
        cached_node_names = {}
        sort_dict = {}
    end

    local sorted_nodes = get_sorted_nodes(tree)

    cache_node_indices(sorted_nodes, tree)

    local now = os.clock()

    --if now - last_action_update_time > 0.5 then
    if first_times[tree] == nil then
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

            if not sdk.is_managed_object(condition) then
                log.debug("Condition " .. tostring(i) .. " in " .. string.format("%x", tree:as_memoryview():get_address()) .. " is not a managed object (" .. tostring(condition) .. ")")
            end
    
            if condition ~= nil then
                table.insert(condition_map[tree], {index=i, ["condition"]=condition})
                table.insert(condition_name_map[tree], tostring(i) .. ": " .. condition:get_type_definition():get_full_name())
            end
        end

        last_action_update_time = os.clock()
        first_times[tree] = true
    end
end

local function display_tree(core, tree)
    local sorted_nodes = get_sorted_nodes(tree)
    local made = false

    local now = os.clock()

    cache_tree(core, tree)

    local changed = false

    changed, action_add_class_name = imgui.input_text("Create Action by class name", action_add_class_name, 1 << 5)

    if changed then
        local new_action = sdk.create_instance(action_add_class_name)

        if new_action then
            new_action = new_action:add_ref()
            tree:get_actions():push_back(new_action:add_ref_permanent())
            tree:get_data():get_action_methods():push_back(1|2|4|8|16|32)

            first_times = {}
        end
    end

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

    --------------------------------------------------
    ---------- EXPRESSION TREE CONDITIONS ------------
    --------------------------------------------------
    made = imgui.tree_node("Expression Tree Conditions")
    imgui.same_line()
    imgui.text(" [" .. tostring(tree:get_data():get_expression_tree_conditions():size()) .. "] ")

    if made then
        display_bhvt_array(tree, node, tree:get_data():get_expression_tree_conditions(), 
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
        local node = active_tree:get_node(i)
        if node == nil then
            return
        end

        custom_id = node:get_id()
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

local field_write_handlers = {
    ["via.vec3"] = function(field)
        return { field.x, field.y, field.z }
    end,
    ["via.vec2"] = function(field)
        return { field.x, field.y }
    end,
    ["via.vec4"] = function(field)
        return { field.x, field.y, field.z, field.w }
    end,
    ["System.Guid"] = function(field)
        local out_bytes = {}

        for i=1, 4 do
            table.insert(out_bytes, field:read_dword((i - 1) * 4))
        end

        return out_bytes
    end
}

local function get_field_write_handler(field)
    local handler = field_write_handlers[field]

    if handler ~= nil then
        return handler
    end

    return function(field)
        return field
    end
end

local field_read_handlers = {
    ["via.vec3"] = function(json_field)
        return Vector3f.new(json_field[1], json_field[2], json_field[3])
    end,
    ["via.vec2"] = function(json_field)
        return Vector2f.new(json_field[1], json_field[2])
    end,
    ["via.vec4"] = function(json_field)
        return Vector4f.new(json_field[1], json_field[2], json_field[3], json_field[4])
    end,
    ["System.Guid"] = function(json_field)
        local guid = ValueType.new(sdk.find_type_definition("System.Guid"))
        guid:write_dword(0, json_field[1])
        guid:write_dword(4, json_field[2])
        guid:write_dword(8, json_field[3])
        guid:write_dword(12, json_field[4])

        return guid
    end
}

local function get_field_read_handler(field)
    local handler = field_read_handlers[field]

    if handler ~= nil then
        return handler
    end

    local decimal_types = {
        f64 = true,
        f32 = true,
        ["System.Single"] = true,
        ["System.Double"] = true,
    }

    if not decimal_types[field] then
        return function(json_field)
            if type(json_field) == "string" or type(json_field) == "boolean" then
                return json_field 
            else
                return math.floor(json_field) 
            end
        end
    end

    return function(json_field) 
        return json_field 
    end
end

local function save_tree(tree, filename)
    if not filename then filename = "bhvteditor/saved_tree.json" end

    local out = {
        tree_data = {
            action_methods = {},
            static_action_methods = {},
            static_actions = {},
            static_conditions = {},
        },
        actions = {},
        conditions = {},
        nodes = {},
        transition_events = {}
    }

    local make_node = function(node)
        local tbl = {}

        local node_actions = node:get_data():get_actions()
        local node_transition_conditions = node:get_data():get_transition_conditions()
        local node_states = node:get_data():get_states()
        local node_states_2 = node:get_data():get_states_2()
        local node_start_states = node:get_data():get_start_states()
        local node_transition_ids = node:get_data():get_transition_ids()
        local node_transition_attributes = node:get_data():get_transition_attributes()
        local node_transition_events = node:get_data():get_transition_events()

        tbl.actions = {}
        tbl.transition_conditions = {}
        tbl.states = {}
        tbl.states_2 = {}
        tbl.start_states = {}
        tbl.transition_ids = {}
        tbl.transition_attributes = {}
        tbl.transition_events = {}
        tbl.name = get_node_full_name(node)

        for i=0, node_actions:size()-1 do
            table.insert(tbl.actions, node_actions[i])
        end

        for i=0, node_transition_conditions:size()-1 do
            table.insert(tbl.transition_conditions, node_transition_conditions[i])
        end

        for i=0, node_states:size()-1 do
            table.insert(tbl.states, node_states[i])
        end

        for i=0, node_states_2:size()-1 do
            table.insert(tbl.states_2, node_states_2[i])
        end

        for i=0, node_start_states:size()-1 do
            table.insert(tbl.start_states, node_start_states[i])
        end

        for i=0, node_transition_ids:size()-1 do
            table.insert(tbl.transition_ids, node_transition_ids[i])
        end

        for i=0, node_transition_attributes:size() - 1 do
            table.insert(tbl.transition_attributes, node_transition_attributes[i])
        end

        for i=0, node_transition_events:size() - 1 do
            local evts = node_transition_events[i]
            local new_tbl = {}

            for j=0, evts:size()-1 do
                table.insert(new_tbl, evts[j])
            end

            if #new_tbl == 0 then
                table.insert(tbl.transition_events, "NULL")
            else
                table.insert(tbl.transition_events, new_tbl)
            end
        end

        return tbl
    end

    for i=0, tree:get_node_count()-1 do
        local node = tree:get_node(i)

        table.insert(out.nodes, make_node(node))
    end

    for i, v in pairs(tree:get_data():get_action_methods()) do
        table.insert(out.tree_data.action_methods, v)
    end

    for i, v in pairs(tree:get_data():get_static_action_methods()) do
        table.insert(out.tree_data.static_action_methods, v)
    end

    local make_fields = function(obj, t, out)
        local fields = t:get_fields()

        for i, field_desc in ipairs(fields) do
            local field_t = field_desc:get_type()

            if field_t:is_value_type() then
                local field_name = field_desc:get_name()
                local field_value = field_desc:get_data(obj)

                out[field_name] = get_field_write_handler(field_t:get_full_name())(field_value)
            end
        end
    end

    local bad_props = {}

    local make_properties = function(obj, t, out) 
        local methods = t:get_methods()

        for i, method in ipairs(methods) do
            local name_start = 5
            local is_potential_getter = method:get_num_params() == 0 and method:get_name():find("get") == 1

            if is_potential_getter and not method:get_name():find("get_") and method:get_name():find("get") == 1 then
                name_start = 4
            end

            if is_potential_getter then -- start of string
                local method_t = method:get_return_type()
                local isolated_name = method:get_name():sub(name_start)

                local setter = t:get_method("set_" .. isolated_name) or t:get_method("set" .. isolated_name)

                -- Don't output meaningless properties
                if setter ~= nil then
                    local value = method:call(obj)
                    out[isolated_name] = get_field_write_handler(method_t:get_full_name())(value)
                else
                    if not bad_props[isolated_name] then
                        log.debug("Skipping property " .. isolated_name .. " because it has no setter")
                    end

                    bad_props[isolated_name] = true
                end
            end
        end
    end

    for i=0, tree:get_action_count()-1 do
        local action = tree:get_action(i)

        if action ~= nil then
            local action_tbl = {}

            action_tbl.type = action:get_type_definition():get_full_name()
            action_tbl.fields = {}
            action_tbl.properties = {}

            if action_hooks.start[action] ~= nil then
                action_tbl.start = {
                    payload = action_hooks.start[action].payload
                }
            else
                action_tbl.start = nil
            end

            if action_hooks.update[action] ~= nil then
                action_tbl.update = {
                    payload = action_hooks.update[action].payload
                }
            else
                action_tbl.update = nil
            end

            if action_hooks["end"][action] ~= nil then
                action_tbl["end"] = {
                    payload = action_hooks["end"][action].payload
                }
            else
                action_tbl["end"] = nil
            end
            
            local t = action:get_type_definition()

            while t ~= nil do
                make_fields(action, t, action_tbl.fields)
                make_properties(action, t, action_tbl.properties)

                t = t:get_parent_type()
            end

            table.insert(out.actions, action_tbl)
        else
            table.insert(out.actions, "NULL")
        end
    end

    for i=0, tree:get_static_action_count()-1 do
        local action = tree:get_action(i | (1 << 30))

        if action ~= nil then
            local action_tbl = {}

            action_tbl.type = action:get_type_definition():get_full_name()
            action_tbl.fields = {}
            action_tbl.properties = {}

            if action_hooks.start[action] ~= nil then
                action_tbl.start = {
                    payload = action_hooks.start[action].payload
                }
            else
                action_tbl.start = nil
            end

            if action_hooks.update[action] ~= nil then
                action_tbl.update = {
                    payload = action_hooks.update[action].payload
                }
            else
                action_tbl.update = nil
            end

            if action_hooks["end"][action] ~= nil then
                action_tbl["end"] = {
                    payload = action_hooks["end"][action].payload
                }
            else
                action_tbl["end"] = nil
            end

            local t = action:get_type_definition()

            while t ~= nil do
                make_fields(action, t, action_tbl.fields)
                make_properties(action, t, action_tbl.properties)

                t = t:get_parent_type()
            end

            table.insert(out.tree_data.static_actions, action_tbl)
        else
            table.insert(out.tree_data.static_actions, "NULL")
        end
    end

    for i=0, tree:get_condition_count()-1 do
        local condition = tree:get_condition(i)

        if condition ~= nil then
            local condition_tbl = {}

            condition_tbl.type = condition:get_type_definition():get_full_name()
            condition_tbl.fields = {}
            condition_tbl.properties = {}

            if custom_condition_evaluators[condition] ~= nil then
                condition_tbl.evaluator = {
                    payload = custom_condition_evaluators[condition].eval_str
                }
            else
                condition_tbl.evaluator = nil
            end
            
            local t = condition:get_type_definition()

            while t ~= nil do
                make_fields(condition, t, condition_tbl.fields)
                make_properties(condition, t, condition_tbl.properties)

                t = t:get_parent_type()
            end

            table.insert(out.conditions, condition_tbl)
        else
            table.insert(out.conditions, "NULL")
        end
    end

    for i=0, tree:get_static_condition_count()-1 do
        local static_condition = tree:get_condition(i | (1 << 30))

        if static_condition ~= nil then
            local static_condition_tbl = {}

            static_condition_tbl.type = static_condition:get_type_definition():get_full_name()
            static_condition_tbl.fields = {}
            static_condition_tbl.properties = {}

            if custom_condition_evaluators[static_condition] ~= nil then
                static_condition_tbl.evaluator = {
                    payload = custom_condition_evaluators[static_condition].eval_str
                }
            else
                static_condition_tbl.evaluator = nil
            end
            
            local t = static_condition:get_type_definition()

            while t ~= nil do
                make_fields(static_condition, t, static_condition_tbl.fields)
                make_properties(static_condition, t, static_condition_tbl.properties)

                t = t:get_parent_type()
            end

            table.insert(out.tree_data.static_conditions, static_condition_tbl)
        else
            table.insert(out.tree_data.static_conditions, "NULL")
        end
    end

    for i=0, tree:get_transition_count()-1 do
        local transition_event = tree:get_transition(i)

        if transition_event ~= nil then
            local transition_event_tbl = {}

            transition_event_tbl.type = transition_event:get_type_definition():get_full_name()
            transition_event_tbl.fields = {}
            transition_event_tbl.properties = {}
            
            local t = transition_event:get_type_definition()

            while t ~= nil do
                make_fields(transition_event, t, transition_event_tbl.fields)
                make_properties(transition_event, t, transition_event_tbl.properties)

                t = t:get_parent_type()
            end

            table.insert(out.transition_events, transition_event_tbl)
        else
            table.insert(out.transition_events, "NULL")
        end
    end

    json.dump_file(filename, out)
end

local function load_tree(tree, filename) -- tree is being written to in this instance.
    if not filename then filename = "bhvteditor/saved_tree.json" end
    first_times = {}

    local loaded_tree = json.load_file(filename)

    if loaded_tree == nil then
        log.error("Could not load saved tree")
        return
    end

    if #loaded_tree.nodes ~= tree:get_node_count() then
        re.msg("Saved tree has different number of nodes than current tree.\nResizing of nodes is not yet supported.\nBugs may occur")
    end

    local assign_fields = function(obj, t, fields)
        if fields == nil then return end

        for field_name, data in pairs(fields) do
            local field_t = t:get_field(field_name):get_type()

            local new_field = get_field_read_handler(field_t:get_full_name())(data)

            if type(new_field) == "boolean" or type(new_field) == "number" or type(new_field) == "string" then
                if obj[field_name] ~= new_field then
                    log.debug("Field " .. field_name .. " does not match, assigning new value")
                end
            end

            obj[field_name] = new_field
        end
    end

    local assign_properties = function(obj, t, properties)
        if properties == nil then return end

        for property_name, data in pairs(properties) do
            local getter = t:get_method("get_" .. property_name) or t:get_method("get" .. property_name)
            local setter = t:get_method("set_" .. property_name) or t:get_method("set" .. property_name)

            if setter ~= nil then
                local current_value = getter:call(obj)
                local new_value = get_field_read_handler(getter:get_return_type():get_full_name())(data)

                if type(current_value) == "boolean" or type(current_value) == "number" or type(current_value) == "string" then
                    if current_value ~= new_value then
                        log.debug("Property " .. property_name .. " does not match, assigning new value")
                    end
                end

                setter:call(obj, get_field_read_handler(getter:get_return_type():get_full_name())(data))
            else
                if t:get_namespace() == "via." then -- native type, all C# types have fields so don't log anything.
                    log.debug("Could not find setter for property " .. property_name)
                else
                    log.debug("Stinky property " .. property_name .. " in " .. t:get_full_name())
                end
            end
        end
    end

    local increase_array_size = function(metaname, json_objects, tree_objects)
        if json_objects == nil then
            log.debug("Saved tree has no " .. metaname .. " objects")

            --[[if tree_objects ~= nil and tree_objects:size() > 0 then
                log.debug("Current tree has " .. metaname .. " object array that is not empty like the JSON file. Emptying array...")

                while tree_objects:size() ~= 0 do
                    tree_objects:pop_back()
                end
            end]]

            return false
        end
    
        log.debug("File has " .. tostring(#json_objects) .. " " .. metaname .. " objects")
    
        -- Resize the objects array (actions, conditions, etc) to match the loaded tree.
        if tree_objects:size() < #json_objects then
            log.debug("Saved tree has more " .. metaname .. " objects than the current tree. Expanding tree...")
    
            for i=tree_objects:size(), #json_objects-1 do
                tree_objects:emplace()
            end
        elseif #json_objects < tree_objects:size() then
            log.debug("Saved tree has less " .. metaname .. " objects than the current tree. Shrinking tree...")
    
            for i=#json_objects+1, tree_objects:size() do
                tree_objects:pop_back()
            end
        end

        return true
    end

    local load_objects = function(metaname, json_objects, tree_objects, on_add_predicate)
        -- Resize the objects array (actions, conditions, etc) to match the loaded tree.
        if not increase_array_size(metaname, json_objects, tree_objects) then
            return
        end

        local num_matching = 0
        
        for i, object_tbl in ipairs(json_objects) do
            --log.debug(tostring(i) .. ": " .. tostring(object_tbl.type))

            local current_object = tree_objects[i-1]
            local new_object = nil
            
            if current_object == nil then
                new_object = sdk.create_instance(object_tbl.type):add_ref_permanent()
            else
                if current_object:get_type_definition():get_full_name() == object_tbl.type then
                    -- Not necessary to create a new object, so we just re-use the old one.
                    new_object = current_object
                    num_matching = num_matching + 1
                    --log.debug("Re-using existing object " .. tostring(i) .. ": " .. tostring(object_tbl.type))
                else
                    new_object = sdk.create_instance(object_tbl.type):add_ref_permanent()
                end
            end

            if new_object ~= current_object then
                log.debug("Creating new object " .. tostring(i) .. ": " .. tostring(object_tbl.type))
            end

            local t = new_object:get_type_definition()
    
            assign_fields(new_object, t, object_tbl.fields)
            assign_properties(new_object, t, object_tbl.properties)
    
            if new_object ~= current_object then
                tree_objects[i-1] = new_object
            end

            if on_add_predicate then
                on_add_predicate(object_tbl, new_object)
            end
        end

        log.debug("File has " .. tostring(num_matching) .. " " .. metaname .. " objects that already match the current tree")
    end

    local load_integers = function(metaname, json_integers, tree_integers)
        -- Resize the integers array (actions, conditions, etc) to match the loaded tree.
        if not increase_array_size(metaname, json_integers, tree_integers) then
            return
        end
    
        for i, integer in ipairs(json_integers) do
            tree_integers[i-1] = integer
        end
    end

    local on_add_condition = function(json_object, condition)
        if json_object.evaluator ~= nil then
            if json_object.evaluator.payload ~= nil then
                log.debug("Loading condition evaluator payload for condition " .. condition:get_type_definition():get_full_name() .. "...")
                log.debug("Payload: " .. tostring(json_object.evaluator.payload))
                add_condition_hook(condition, json_object.evaluator.payload)
            end
        end
    end

    local on_add_action = function(json_object, action)
        if json_object.start ~= nil then
            if json_object.start.payload ~= nil then
                log.debug("Loading action start payload for action " .. action:get_type_definition():get_full_name() .. "...")
                log.debug("Payload: " .. tostring(json_object.start.payload))
                add_action_start_hook(action, json_object.start.payload)
            end
        end

        if json_object.update ~= nil then
            if json_object.update.payload ~= nil then
                log.debug("Loading action update payload for action " .. action:get_type_definition():get_full_name() .. "...")
                log.debug("Payload: " .. tostring(json_object.update.payload))
                add_action_update_hook(action, json_object.update.payload)
            end
        end

        if json_object["end"] ~= nil then
            if json_object["end"].payload ~= nil then
                log.debug("Loading action end payload for action " .. action:get_type_definition():get_full_name() .. "...")
                log.debug("Payload: " .. tostring(json_object["end"].payload))
                add_action_end_hook(action, json_object["end"].payload)
            end
        end
    end

    load_objects("action", loaded_tree.actions, tree:get_actions(), on_add_action)
    load_objects("condition", loaded_tree.conditions, tree:get_conditions(), on_add_condition)
    load_objects("static action", loaded_tree.tree_data.static_actions, tree:get_data():get_static_actions(), on_add_action)
    load_objects("static condition", loaded_tree.tree_data.static_conditions, tree:get_data():get_static_conditions(), on_add_condition)
    load_objects("transition event", loaded_tree.transition_events, tree:get_transitions())

    load_integers("action method", loaded_tree.tree_data.action_methods, tree:get_data():get_action_methods())
    load_integers("static action method", loaded_tree.tree_data.static_action_methods, tree:get_data():get_static_action_methods())

    local increase_node_array_size = function(node_name, metaname, json_objects, tree_objects)
        if json_objects == nil or json_objects == "NULL" then
            if tree_objects ~= nil and tree_objects:size() > 0 then
                log.debug("Current node "  .. node_name .. " has " .. metaname .. " object array that should be empty. Emptying array...")

                while tree_objects:size() ~= 0 do
                    tree_objects:pop_back()
                end
            end

            return false
        end
    

        -- Resize the objects array (actions, conditions, etc) to match the loaded tree.
        if tree_objects:size() < #json_objects then
            log.debug("Saved Node " .. node_name .. " has more " .. metaname .. " objects than the current node. Expanding node...")
    
            for i=tree_objects:size(), #json_objects-1 do
                tree_objects:emplace()
            end
        elseif #json_objects < tree_objects:size() then
            log.debug("Saved Node " .. node_name .. " has fewer " .. metaname .. " objects than the current node. Shrinking node...")
    
            for i=#json_objects+1, tree_objects:size() do
                tree_objects:pop_back()
            end
        end

        return true
    end

    local load_node_integers = function(node_name, metaname, json_integers, node_integers)
        -- Resize the integers array (actions, conditions, etc) to match the loaded tree.
        if not increase_node_array_size(node_name, metaname, json_integers, node_integers) then
            return
        end
    
        for i, integer in ipairs(json_integers) do
            node_integers[i-1] = integer
        end
    end

    --[[tbl.actions = {}
    tbl.transition_conditions = {}
    tbl.states = {}
    tbl.states_2 = {}
    tbl.start_states = {}
    tbl.transition_ids = {}
    tbl.transition_attributes = {}
    tbl.transition_events = {}]]
    
    if #loaded_tree.nodes ~= tree:get_node_count() then
        log.debug("Saved tree has " .. tostring(#loaded_tree.nodes) .. " nodes, but the current tree has " .. tostring(tree:get_node_count()) .. " nodes. Node resizing is not yet supported.")
    end

    for i, node_json in ipairs(loaded_tree.nodes) do
        local tree_node = tree:get_node(i-1)
        local node_name = tostring(i-1) .. ": " .. node_json.name
        load_node_integers(node_name, "action", node_json.actions, tree_node:get_data():get_actions())
        load_node_integers(node_name, "transition condition", node_json.transition_conditions, tree_node:get_data():get_transition_conditions())
        load_node_integers(node_name, "state", node_json.states, tree_node:get_data():get_states())
        load_node_integers(node_name, "state 2", node_json.states_2, tree_node:get_data():get_states_2())
        load_node_integers(node_name, "start state", node_json.start_states, tree_node:get_data():get_start_states())
        load_node_integers(node_name, "transition id", node_json.transition_ids, tree_node:get_data():get_transition_ids())
        load_node_integers(node_name, "transition attribute", node_json.transition_attributes, tree_node:get_data():get_transition_attributes())

        if increase_node_array_size(node_name, "transition event", node_json.transition_events, tree_node:get_data():get_transition_events()) then
            for j, json_evts in ipairs(node_json.transition_events) do
                if increase_node_array_size(node_name, "transition event element", json_evts, tree_node:get_data():get_transition_events()[j-1]) and type(json_evts) == "table" then
                    for k, evt in ipairs(json_evts) do
                        if evt >= tree:get_transitions():size() then
                            log.debug("Saved transition event element " .. tostring(k-1) .. " for node " .. node_name .. " references a transition (" .. tostring(evt) .. ") that does not exist. A crash may occur.")
                        end

                        tree_node:get_data():get_transition_events()[j-1][k-1] = evt
                    end
                end
            end     
        end
        
        -- Fix nonexistent transition events.
        if tree_node:get_data():get_transition_events():size() > 0 then
            for k=0, tree_node:get_data():get_transition_events():size()-1 do
                local events = tree_node:get_data():get_transition_events()[k]
                local j = 0
                while true do
                    if events:size() == 0 then
                        break
                    end

                    if j >= events:size() then
                        break
                    end

                    if events[j] >= tree:get_transitions():size() then
                        log.debug("Erasing nonexistent transition event element " .. tostring(j) .. "(" .. tostring(events[j]) .. ") for node " .. node_name .. ".")
                        events:erase(j)
                        j = 0
                    else
                        j = j + 1
                    end
                end
            end
        end
    end
end

local popup_ask_filename = "my_cool_tree"
local ask_overwrite_filename = ""
local chosen_layer = 0
local quick_run = 0
local prev_active_node = 0

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
    local motion_fsm2 = player and player:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2")) or nil

    if player ~= nil then
        if motion_fsm2 ~= nil then
            layer = motion_fsm2:call("getLayer", chosen_layer)

            if layer ~= nil then
                tree = layer:get_tree_object()

                if tree ~= nil then
                    last_layer = layer
                    cache_tree(layer, tree)
                end
            end
        end
    end

    local changed = false
    local now = os.clock()

    if imgui.begin_menu_bar() then
        if imgui.begin_menu("File") then
            if imgui.begin_menu("Save                        ") then
                if imgui.button("New File") then
                    imgui.open_popup("NewFile_AskName")
                end

                if imgui.begin_popup("NewFile_AskName") then
                    imgui.text("Files get saved to bhvteditor/{your_name}_saved_tree.json")
                    changed, popup_ask_filename = imgui.input_text("Name", popup_ask_filename)
                    if imgui.button("Save") then
                        save_tree(tree, "bhvteditor/" .. popup_ask_filename .. "_saved_tree.json")
                        imgui.close_current_popup()
                    end
                    imgui.end_popup()
                end

                -- Glob the files in the current directory.
                local files = fs.glob("bhvteditor.*saved_tree.*json")

                for k, file in pairs(files) do
                    imgui.text("Overwrite")
                    imgui.same_line()
                    if imgui.button(file) then
                        imgui.open_popup("Overwrite_Ask")
                        ask_overwrite_filename = file
                    end
                end

                if imgui.begin_popup("Overwrite_Ask") then
                    imgui.text("Are you sure you want to overwrite " .. ask_overwrite_filename .. "?")
                    if imgui.button("Yes") then
                        save_tree(tree, ask_overwrite_filename)
                        imgui.close_current_popup()
                    end
                    if imgui.button("No") then
                        imgui.close_current_popup()
                    end
                    imgui.end_popup()
                end

                imgui.end_menu()
            end

            if imgui.begin_menu("Load                        ") then
                -- Glob the files in the current directory.
                local files = fs.glob("bhvteditor.*saved_tree.*json")

                for k, file in pairs(files) do
                    imgui.text("Load")
                    imgui.same_line()
                    if imgui.button(file) then
                        load_tree(tree, file)
                    end
                end

                imgui.end_menu()
            end

            --imgui.text("This literally does nothing.")

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

                        --[[if not already_set then
                            queued_editor_id_move = {["i"] = i, ["id"] = id}
                            already_set = true
                        end]]

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

        -- Active node
        imgui.separator()
        imgui.text("ActiveNode: " .. tostring(prev_active_node))

        -- Display node
        imgui.separator()
        imgui.push_item_width(100)
        changed, cfg.default_node = imgui.drag_int("Display Node", cfg.default_node, 0, #custom_tree)
        if changed and tree ~= nil and cfg.default_node < tree:get_node_count() then
            queued_editor_id_move = {["i"] = cfg.default_node, ["id"] = tree:get_node(cfg.default_node):get_id()}
        end

        -- Selected layer
        if motion_fsm2 ~= nil then
            imgui.separator()

            changed, chosen_layer = imgui.slider_int("Selected layer", chosen_layer, 0, motion_fsm2:call("getLayerCount")-1)

            if changed then
                first_times = {}
            end
        end

        imgui.separator()

        if tree ~= nil then
            changed, quick_run = imgui.input_text("Run node", quick_run, 1 << 5)

            if changed or imgui.button("Run") then
                local node = tree:get_node(tonumber(quick_run))

                layer:call("setCurrentNode(System.UInt64, via.behaviortree.SetNodeInfo, via.motion.SetMotionTransitionInfo)", node:get_id(), nil, nil)
                --queued_editor_id_move = {["i"] = quick_run, ["id"] = node:get_id()}
            end
        end

        -- Selected node
        imgui.separator()
        imgui.text(tostring(#imnodes.get_selected_nodes()) .. " selected nodes")

        imgui.pop_item_width()

        imgui.end_menu_bar()
    end

    if (tree ~= nil and (active_tree == nil or tree ~= active_tree)) then
        log.debug("Recreating active tree")

        recreate_globals()

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
        
        local already_has_good_active = false

        if prev_active_node ~= 0 then
            local node = prev_active_node < tree:get_node_count() and tree:get_node(prev_active_node)

            if node then
                already_has_good_active = (node:get_status1() == 2 or node:get_status2() == 2) and #tree:get_node(prev_active_node):get_children() == 0
            end
        end

        if not already_has_good_active then
            for i=0, tree:get_node_count()-1 do
                local node = tree:get_node(i)

                if (node:get_status1() == 2 or node:get_status2() == 2) and #node:get_children() == 0 then
                    prev_active_node = i

                    if cfg.follow_active_nodes then
                        set_base_node_to_parent(tree, i)

                        queued_editor_id_move_step2 = node:get_id()
                        queued_editor_id_start_time = os.clock()
                    end

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