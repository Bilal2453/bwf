local core = require('core')

---@class bwf.Hook: luvit.core.Object
---@field new fun(self: self, hook: bwf.Hook.struct): bwf.Hook
---@field id string
---@field call fun(call: bwf.Call)
local Hook = core.Object:extend()

---@param hook bwf.Hook.struct
function Hook:initialize(hook)
  self.id = assert(hook.id, 'expected a hook id')
  self.call = assert(hook.call, 'expected a hook call')
end

---@param call bwf.Call
---@return boolean? success, string? error
function Hook:eval(call)
  local success, err = pcall(self.call, call, self)
  -- TODO: error handling
  if not success then
    return nil, err
  end
  return true
end

function Hook.resolve(hook)
  assert(type(hook) == 'table', 'bad argument #2 (expected a hook)')
  local hook_obj
  if not hook.meta then
    hook_obj = Hook:new(hook)
  elseif core.instanceof(hook, Hook) then
    hook_obj = hook
  else
    error('bad argument #2 (expected a valid hook)')
  end
  return hook_obj
end

---@param call bwf.Call
---@param hooks bwf.Hook[]
function Hook.iter(call, hooks)
  for _, v in ipairs(hooks) do
    local success, err = v:eval(call)
    if not success then
      return call.app:error(err)
    end
  end
end

return Hook
