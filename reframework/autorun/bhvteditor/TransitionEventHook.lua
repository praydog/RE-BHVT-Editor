local BaseHook = require("bhvteditor/BaseHook")

local TransitionEventHook = {
    name="TransitionEvent",
}

TransitionEventHook.__index = TransitionEventHook
setmetatable(TransitionEventHook, BaseHook)

function TransitionEventHook:setup_descriptors()
    self.hook_descriptors = {
        execute = {
            order = 1,
            default_payload = "return function(storage, obj, arg)\nend",
            postfunc = function(prev_args, retval)
                return { 
                        sdk.to_managed_object(prev_args[2]), 
                        sdk.to_managed_object(prev_args[3])
                    }
            end
        }
    }
end

function TransitionEventHook:constructor(obj, storage)
    BaseHook.constructor(self, obj, storage)
    
    return self
end

function TransitionEventHook:new(obj, storage)
    local instance = setmetatable({}, TransitionEventHook)

    return instance:constructor(obj, storage)
end

TransitionEventHook:setup_descriptors() -- the default TransitionEventhook sets up the descriptors so we can have a "static" function grab the hook names.

return TransitionEventHook