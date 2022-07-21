local ActionHook = require("bhvteditor/ActionHook")
local ConditionHook = require("bhvteditor/ConditionHook")
local TransitionEventHook = require("bhvteditor/TransitionEventHook")

local HookManager = {
    hooks = {},
    hook_name_map = {
        ["via.behaviortree.Action"] = ActionHook,
        ["via.behaviortree.Condition"] = ConditionHook,
        ["via.behaviortree.TransitionEvent"] = TransitionEventHook,
        -- todo: add more hook types 
    },
    storage = {},
}

function HookManager:exists(obj)
    return self.hooks[obj] ~= nil
end

function HookManager:get(obj)
    local hook = self.hooks[obj]

    if hook then
        return hook
    end
    
    if not sdk.is_managed_object(obj) then
        error("[HookManager] Object is not a managed object")
    end

    for type_name, hook_type in pairs(self.hook_name_map) do
        if obj:get_type_definition():is_a(type_name) then
            self.hooks[obj] = hook_type:new(obj, self.storage)
            return self.hooks[obj]
        end
    end

    error("[HookManager] Unable to find appropriate hook type for object " .. obj:get_type_definition():get_full_name())

    return nil
end

function HookManager:remove(obj)
    -- Invalidating everything will stop the hook from proceeding and return early.
    if self.hooks[obj] ~= nil then
        self.hooks[obj]:invalidate()
    end

    self.hooks[obj] = nil -- as simple as that (well, hopefully, at the moment actually unhooking the vtable is not implemented)
end

function HookManager:get_all(name)
    local out = {}

    for k, v in pairs(hooks) do
        if v:get_name() == name then
            table.insert(out, v)
        end
    end

    return out
end

return HookManager -- don't need a new function, there should only be one instance of this class