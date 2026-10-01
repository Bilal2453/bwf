local core = require('core')

---@class bwf.Hook.scope
---@field request bwf.Hook[]
---@field response bwf.Hook[]
---@field error bwf.Hook[]

---@class bwf.Hook.struct: table
---@field id string
---@field call fun(call: bwf.Call)
---@field capability string?

---@alias bwd.Hook.resolvable bwf.Hook | bwf.Hook.struct


---@class bwf.Hook: luvit.core.Object
---@field new fun(self: self, hook: bwf.Hook.struct): bwf.Hook
---@field id string
---@field call fun(call: bwf.Call)
---@field capability string?
local Hook = core.Object:extend()

--- a pattern used to validate id/capability names
local legal_name_patt = '^[%w_%.%:%-]+$'

---@param hook bwf.Hook.struct
function Hook:initialize(hook)
    -- load "id"
  local id = hook.id
  -- ensure id is a valid non-empty string
  if not id or type(id) ~= 'string' then
    return error('bad hook option "id" (expected a string value)')
  end
  -- ensure it follows the format
  if not id:match(legal_name_patt) then
    return error('bad hook option "id" (value must follow the pattern "' .. legal_name_patt .. '")')
  end
  self.id = id

  -- load call
  if not hook.call or type(hook.call) ~= 'function' then
    return error('bad hook option "call" (expected a function value)')
  end
  self.call = hook.call

  -- load "capability"
  local cap = hook.capability
  if cap then
    if type(cap) ~= 'string' then
      return error('bad hook option "capability" (expected a string or nil value)')
    end
    if not cap:match(legal_name_patt) then
      return error('bad hook option "capability" (value must follow the pattern "' .. legal_name_patt .. '")')
    end
    self.capability = cap
  end
end
--[[
  Hook.capabilities = {
    CORS             = 'cors',
    AUTH             = 'auth',
    SESSION          = 'session',
    RATE_LIMIT       = 'ratelimit',
    SECURITY_HEADERS = 'security_headers',
    COMPRESSION      = 'compression',
    BODY_LIMIT       = 'body_limit',
  }
]]

---@return bwf.Hook
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

---@return bwf.Hook.scope
function Hook._create_scope()
  return {
    request = { _ids = {}, _caps = {} },
    response = { _ids = {}, _caps = {} },
    error = { _ids = {}, _caps = {} },
  }
end

---@param scope bwf.Hook.scope
---@param phase 'request' | 'response' | 'error'
---@param hook bwd.Hook.resolvable
---@param is_internal boolean?
function Hook._register_hook(scope, phase, hook, is_internal)
  -- sanity check: make sure the scope/phase align
  local stage = scope[phase]
  if not stage then
    return error('invalid phase name "' .. tostring(phase) .. '"')
  end
  hook = Hook.resolve(hook)
  -- reserve the "bwf:" namespace for internal use
  if not is_internal and hook.id:match('^bwf:') then
    return error('cannot assign hooks to reserved scope "bwf"')
  end
  -- ensure the hook ID is unique to this scope
  if stage._ids[hook.id] then
    return error('hook "' .. hook.id .. '" is already registered to this scope for phase "' .. phase .. '"')
  end
  -- ensure a capability isn't already taken by another hook
  if hook.capability and stage._caps[hook.capability] then
    return error(string.format('capability "%s" on phase "%s" is already claimed by hook "%s"', hook.capability, phase, stage._caps[hook.capability]))
  end
  -- finally register it
  table.insert(stage, hook)
  stage._ids[hook.id] = true
  if hook.capability then
    stage._caps[hook.capability] = hook.id
  end
end

---@param call bwf.Call
---@return boolean? success, string? error
function Hook:eval(call)
  local success, err = pcall(self.call, call, self)
  if not success then
    return nil, err
  end
  return true
end

return Hook
