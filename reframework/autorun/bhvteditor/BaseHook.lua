local BaseHook = {
    storage = {},
    name = "none",
    -- e.g.
    --[[
        start = {
            default_payload = "return function(storage, obj, arg)\nend",
            postfunc,
            order = 1,
        },
        update = {
            default_payload = "return function(storage, obj, arg)\nend",
            postfunc,
            order = 2,
        },
        ["end"] = {
            default_payload = "return function(storage, obj, arg)\nend",
            postfunc,
            order = 3,
        },
    ]]
    hook_descriptors = {},
}

BaseHook.__index = BaseHook

function BaseHook:add(hook_name, payload, postfunc)
    if not self.hook_descriptors[hook_name] then
        error("Unknown hook " .. hook_name)
        return
    end

    local hook_descriptor = self.hook_descriptors[hook_name]

    postfunc = postfunc or hook_descriptor.postfunc
    payload = payload or hook_descriptor.default_payload

    local hook = hook_descriptor.active

    if hook == nil then
        hook_descriptor.active = {}
        hook = hook_descriptor.active

        -- Only hook function once if it didn't exist before.
        local add_hook = function()
            local prev_args = nil
    
            sdk.hook_vtable(
                self.obj, 
                self.obj:get_type_definition():get_method(hook_name), 
                function(args)
                    prev_args = args
                end,
                function(retval)
                    local hook = hook_descriptor.active
                    if not hook then
                        return retval
                    end

                    local owner = sdk.to_managed_object(prev_args[3]):get_OwnerGameObject()

                    if not self.storage[owner] then
                        self.storage[owner] = {}
                    end

                    local succ, result = pcall(hook.func, self.storage[owner], table.unpack(hook.postfunc(prev_args, retval)))

                    if succ ~= nil and succ == false then
                        hook.err = result
                        log.debug("Hook error: " .. tostring(result))
                        return retval
                    end

                    return sdk.to_ptr(result)
                end
            )
        end
    
        add_hook()
    end

    hook.payload = payload
    hook.postfunc = postfunc
    hook.init, hook.err = load(hook.payload)

    if not hook.err then
        hook.err, hook.func = pcall(hook.init)

        if hook.err ~= nil and hook.err == false then
            log.debug("Error in " .. hook_name .. " hook: " .. tostring(hook.err) .. " " .. tostring(hook.func))
            log.error("Error in " .. hook_name .. " hook: " .. tostring(hook.err) .. " " .. tostring(hook.func))
            hook.err = hook.func
            hook.func = nil
        end
    else
        hook.func = nil
    end
end

function BaseHook:add_all_default_hooks()
    for hook_name, hook_info in pairs(self.hook_descriptors) do
        if hook_info.default_payload then
            self:add(hook_name)
        end
    end
end

function BaseHook:display(name)
    local hook_tbl = self.hook_descriptors[name]

    if not hook_tbl then
        error("Unknown hook " .. name)
        return
    end

    local hook = hook_tbl.active
    local metaname = name:sub(1, 1):upper() .. name:sub(2)

    if not hook then
        if imgui.button("Add Lua Driven " .. metaname) then
            self:add(name)
        end
    else
        imgui.text("Press CTRL+Enter for the changes to take effect.")

        local changed = false

        local cursor_screen_pos = imgui.get_cursor_screen_pos()
        changed, hook.payload = imgui.input_text_multiline(metaname, hook.payload)

        if imgui.begin_popup_context_item(metaname .. "_popup") then
            if imgui.button("Remove " .. metaname) then
                hook_tbl.active = nil
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
                    
                    if hook.err ~= nil and hook.err == false then
                        hook.err = hook.func
                    end
                end
            end

            if imgui.begin_popup_context_item(metaname .. "_popup2") then
                if imgui.button("Remove " .. metaname) then
                    hook_tbl.active = nil
                end

                imgui.end_popup()
            end
    
            imgui.end_popup()
        end

        if hook.err then
            imgui.text(hook.err)
        end
    end
end

function BaseHook:display_hooks()
    local sorted_hooks = {}

    for hook_name, hook_info in pairs(self.hook_descriptors) do
        table.insert(sorted_hooks, hook_name)
    end

    table.sort(sorted_hooks, function(a, b)
        return self.hook_descriptors[a].order < self.hook_descriptors[b].order
    end)

    for i, hook_name in ipairs(sorted_hooks) do
        self:display(hook_name)
    end
end

function BaseHook:get_name()
    return self.name
end

function BaseHook:has_hook(hook_name)
    local desc = self.hook_descriptors[hook_name]
    return desc and desc.active ~= nil
end

function BaseHook:get_hook(hook_name)
    local desc = self.hook_descriptors[hook_name]
    return desc and desc.active or nil
end

function BaseHook:get_hook_names()
    local out = {}

    for hook_name, _ in pairs(self.hook_descriptors) do
        table.insert(out, hook_name)
    end

    return out
end

function BaseHook:serialize(j)
    for i, name in ipairs(self:get_hook_names()) do
        if self:has_hook(name) then
            j[name] = {
                payload = self:get_hook(name).payload
            }
        else
            j[name] = nil
        end
    end
end

function BaseHook:deserialize(j)
    local any = false

    for i, name in ipairs(self:get_hook_names()) do
        if j[name] and j[name].payload then
            log.debug("Loading " .. self.name .. " " .. name .. " payload for " .. self.name .. " " .. self.obj:get_type_definition():get_full_name() .. "...")
            log.debug("Payload: " .. tostring(j[name].payload))
            self:add(name, j[name].payload)
            any = true
        end
    end

    return any
end

function BaseHook:invalidate()
    for k, v in pairs(self:get_hook_names()) do
        local hook = self.hook_descriptors[v].active
        
        if hook then
            self.hook_descriptors[v].active = nil
        end
    end
end

function BaseHook:setup_descriptors()
    self.hook_descriptors = {}
end

function BaseHook:constructor(obj, storage)
    if not storage then
        error("[BaseHook] storage is required")
    end

    if not obj then
        error("[BaseHook] obj is required")
    end

    self.obj = obj
    self.storage = storage
    self:setup_descriptors()
    return self
end

function BaseHook:new(obj, storage)
    local instance = setmetatable({}, BaseHook)
    return instance:constructor(obj, storage)
end

return BaseHook