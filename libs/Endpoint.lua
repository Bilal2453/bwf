local core = require('core')
local Hook = require('Hook')

local methods = { 'get', 'post', 'put', 'delete', 'head', 'query', 'options', 'trace', 'patch' }
for _, v in ipairs(methods) do
  methods[v] = true
end

---@alias bwf.alias.endpoint_options {summary?: string, description?: string}

---@class bwf.Endpoint: luvit.core.Object
---@field new fun(self: self, options: bwf.alias.endpoint_options?): bwf.Endpoint
---@field summary string
---@field description string
---@field operations {[bwf.alias.http_method]: bwf.alias.operation_struct}
---@field additional_operations {[bwf.alias.http_method]: bwf.alias.operation_struct}
---@field parameters bwf.Parameter[]
---@field responses {[string]: bwf.Response}
local Endpoint = core.Object:extend()

function Endpoint:initialize(options)
  self.hooks = {
    request = {},
    response = {},
    error = {},
  }
  options = options or {}
  self.summary = options.summary or ''
  self.description = options.description or ''

  self.operations = {}
  self.additional_operations = {} -- TODO: verify this is working correctly and has no weird side effects
  self.parameters = {}
  self.responses = {}
end

---@return bwf.alias.operation_struct?, string? error
---@nodiscard
function Endpoint:findOperation(call)
  local method = call.req.method:lower()
  local operation = self.operations[method] or self.additional_operations[method] --[[@as bwf.alias.operation_struct|nil]]
  if not operation then
    -- TODO: might want to use the future HttpError here instead
    return nil, 'no such operation was found in this endpoint'
  end
  return operation
end

-- TODO: do we need this method at all?
--- Executed when the server has received a request, handle a Call object
--- by figuring out which Operation is exactly supposed to be called, then execute it.
-- -@param call bwf.Call
-- -@return boolean? success, string? error_message
-- function Endpoint:execute(call)
--   local operation = self:findOperation(call)
--   operation.callback(call)
--   return true
-- end

--- Defines an action for an endpoint path.
--- The callback is called when the specified HTTP method is sent to this endpoint.
---
--- Overrides any previously defined operation.
--- If the specified `method` is not a formal method, it will be treated as `Endpoints.additional_operations`.
---@param method bwf.alias.http_method
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
function Endpoint:define(method, callback, operation)
  method = string.lower(assert(method))
  local map = methods[method] and self.operations or self.additional_operations
  map[method] = { operation = operation, callback = callback }
  return self
end

---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Endpoint:get(callback, operation)
  return self:define('get', callback, operation)
end

---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Endpoint:put(callback, operation)
  return self:define('put', callback, operation)
end

---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Endpoint:post(callback, operation)
  return self:define('post', callback, operation)
end

---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Endpoint:delete(callback, operation)
  return self:define('delete', callback, operation)
end

---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Endpoint:options(callback, operation)
  return self:define('options', callback, operation)
end

---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Endpoint:head(callback, operation)
  return self:define('head', callback, operation)
end

---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Endpoint:patch(callback, operation)
  return self:define('patch', callback, operation)
end

---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Endpoint:trace(callback, operation)
  return self:define('trace', callback, operation)
end

---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Endpoint:query(callback, operation)
  return self:define('query', callback, operation)
end

--- pends a request hook scoped only to this Routes.
--- ns after App-level and Route-level request hooks.
---@param hook bwd.Hook.resolvable
---@return self
function Endpoint:hookRequest(hook)
  hook = Hook.resolve(hook)
  table.insert(self.hooks.request, hook)
  return self
end
--- ds a response hook scoped only to this Endpoint.
--- before Route-level and App-level response hooks.
---@param hook bwd.Hook.resolvable
---@return self
function Endpoint:hookResponse(hook)
  hook = Hook.resolve(hook)
  table.insert(self.hooks.response, hook)
  return self
end
--- Appends an error hook scoped only to this Endpoint.
---@param hook bwd.Hook.resolvable
---@return self
function Endpoint:hookError(hook)
  hook = Hook.resolve(hook)
  table.insert(self.hooks.error, hook)
  return self
end

return Endpoint
