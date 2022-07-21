local BaseHook = require("bhvteditor/BaseHook")

local ActionHook = {
    name="action",
}

ActionHook.__index = ActionHook
setmetatable(ActionHook, BaseHook)

function ActionHook:setup_descriptors()
    self.hook_descriptors = {
        start = {
            order = 1,
            default_payload = "return function(storage, obj, arg)\nend",
            postfunc = function(prev_args, retval)
                return { 
                        sdk.to_managed_object(prev_args[2]), 
                        sdk.to_managed_object(prev_args[3])
                    }
            end
        },
        update = {
            order = 2,
            default_payload = "return function(storage, obj, arg)\nend",
            postfunc = function(prev_args, retval)
                return { 
                        sdk.to_managed_object(prev_args[2]), 
                        sdk.to_managed_object(prev_args[3])
                    }
            end
        },
        ["end"] = {
            order = 3,
            default_payload = "return function(storage, obj, arg)\nend",
            postfunc = function(prev_args, retval)
                return { 
                        sdk.to_managed_object(prev_args[2]), 
                        sdk.to_managed_object(prev_args[3])
                    }
            end
        },
    }
end

function ActionHook:constructor(obj, storage)
    BaseHook.constructor(self, obj, storage)
    
    return self
end

function ActionHook:new(obj, storage)
    local instance = setmetatable({}, ActionHook)

    return instance:constructor(obj, storage)
end

ActionHook:setup_descriptors() -- the default actionhook sets up the descriptors so we can have a "static" function grab the hook names.

return ActionHook