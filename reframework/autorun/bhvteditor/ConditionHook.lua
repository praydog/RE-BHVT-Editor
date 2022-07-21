local BaseHook = require("bhvteditor/BaseHook")

local ConditionHook = {
    name="condition"
}

ConditionHook.__index = ConditionHook
setmetatable(ConditionHook, BaseHook)

function ConditionHook:setup_descriptors()
    self.hook_descriptors = {
        evaluate = {
            order = 1,
            default_payload = "return function(storage, cond, arg, retval)\n\treturn retval\nend",
            postfunc = function(prev_args, retval)
                return { 
                        sdk.to_managed_object(prev_args[2]), 
                        sdk.to_managed_object(prev_args[3]),
                        (sdk.to_int64(retval) & 1) == 1
                    }
            end
        },
    }
end

function ConditionHook:constructor(obj, storage)
    BaseHook.constructor(self, obj, storage)
    
    return self
end

function ConditionHook:new(obj, storage)
    local instance = setmetatable({}, ConditionHook)

    return instance:constructor(obj, storage)
end

ConditionHook:setup_descriptors() -- the default actionhook sets up the descriptors so we can have a "static" function grab the hook names.

return ConditionHook