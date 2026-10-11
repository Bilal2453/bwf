local core = require('core')

---@class bwf.Hook.scope
---@field preroute bwf.Hook[]
---@field request bwf.Hook[]
---@field response bwf.Hook[]
---@field error bwf.Hook[]
---@class bwf.Hook.struct: table
---@field id string
---@field call fun(call: bwf.Call)
---@field capability string?
---@field override boolean?
---@alias bwf.Hook.resolvable bwf.Hook | bwf.Hook.struct
---@alias bwf.Hook.phase 'preroute' | 'request' | 'response' | 'error'

--- a pattern used to validate id/capability names
local legal_name_patt = '^[%w_%.%:%-]+$'

---@class bwf.Hook: luvit.core.Object
---@field new fun(self: self, hook: bwf.Hook.struct): bwf.Hook
---@field id string
---@field call fun(call: bwf.Call)
---@field capability string?
---@field override boolean
local Hook = core.Object:extend()

--- A list of standard capabilities hooks might implement.
---@enum bwf.Hook.capabilities
Hook.capabilities = {}

---@param hook bwf.Hook.struct
function Hook:initialize(hook)
  -- load "id" and ensure it's a valid string
  local id = hook.id
  if not id or type(id) ~= 'string' then
    return error('bad hook option "id" (expected a string value)')
  end
  if not id:match(legal_name_patt) then
    return error('bad hook option "id" (value must follow the pattern "' .. legal_name_patt .. '")')
  end
  self.id = id

  -- load "call"/"override"
  if not hook.call or type(hook.call) ~= 'function' then
    return error('bad hook option "call" (expected a function value)')
  end
  self.call = hook.call
  self.override = not not hook.override

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
    preroute = { _ids = {}, _caps = {} },
    request = { _ids = {}, _caps = {} },
    response = { _ids = {}, _caps = {} },
    error = { _ids = {}, _caps = {} },
  }
end

---@param phase bwf.Hook.phase
---@param scopes bwf.Hook.scope[]
---@return bwf.Hook[]
function Hook._compile_scopes(phase, scopes)
  local compiled = {}
  ---@type {[string]: number}, {[string]: number}
  local hook_index, cap_index = {}, {}
  for _, stage in ipairs(scopes) do
    for _, hook in ipairs(stage[phase]) do
      ---@cast hook bwf.Hook
      local index = (#compiled + 1)
      local old_id_slot = hook_index[hook.id]
      local old_cap_slot = hook.capability and cap_index[hook.capability]

      -- is there collision?
      if old_id_slot and old_cap_slot and old_id_slot ~= old_cap_slot then
        error(
          string.format(
            'ambiguous hook override in phase "%s": hook "%s" collides by ID with hook "%s" and by capability "%s" with hook "%s"',
            phase,
            hook.id,
            compiled[old_id_slot].id,
            hook.capability,
            compiled[old_cap_slot].id
          )
        )
      elseif old_id_slot and not hook.override then
        error(string.format('hook "%s" collides with an ancestor hook\'s id in phase "%s"', hook.id, phase))
      elseif hook.capability and old_cap_slot and not hook.override then
        error(
          string.format(
            'hook "%s" collides with an ancestor hook\'s capability "%s" in phase "%s"',
            hook.id,
            hook.capability,
            phase
          )
        )
      end

      -- clear previous states if hook will be overwritten
      if old_id_slot or old_cap_slot then
        index = old_id_slot or old_cap_slot
        local old_hook = compiled[index]
        hook_index[old_hook.id] = nil
        if old_hook.capability then
          cap_index[old_hook.capability] = nil
        end
      end

      -- register the hook
      compiled[index] = hook
      hook_index[hook.id] = index
      if hook.capability then
        cap_index[hook.capability] = index
      end

    end
  end
  return compiled
end

---@param scope bwf.Hook.scope
---@param phase bwf.Hook.phase
---@param hook bwf.Hook.resolvable
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
    return error(
      string.format(
        'capability "%s" on phase "%s" is already claimed by hook "%s"',
        hook.capability,
        phase,
        stage._caps[hook.capability]
      )
    )
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
