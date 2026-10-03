local Hook = require('Hook')
local core = require('core')

local methods = { 'get', 'post', 'put', 'delete', 'head', 'query', 'options', 'trace', 'patch' }
for _, v in ipairs(methods) do
  methods[v] = true
end

---@alias bwf.alias.endpoint_options {summary?: string, description?: string}

---@class bwf.Endpoint: luvit.core.Object
---@field new fun(self: self, options: bwf.alias.endpoint_options?): bwf.Endpoint
---@field hooks bwf.Hook.scope
---@field summary string
---@field description string
---@field operations {[bwf.alias.http_method]: bwf.alias.operation_struct}
---@field additional_operations {[bwf.alias.http_method]: bwf.alias.operation_struct}
---@field parameters bwf.Parameter[]
---@field responses {[string]: bwf.Response}
local Endpoint = core.Object:extend()

function Endpoint:initialize(options)
  self.hooks = Hook._create_scope()
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
    return nil, 'no such operation was found in this endpoint'
  end
  return operation
end

--- Defines an action for an endpoint path.
--- The callback is called when the specified HTTP method is sent to this endpoint.
---
--- Overrides any previously defined operation.
--- If the specified `method` is not a formal method, it will be treated as `Endpoints.additional_operations`.
---@param method bwf.alias.http_method
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, method: bwf.alias.http_method, callback: bwf.alias.endpoint_callback): self
---@return self
function Endpoint:define(method, operation, callback)
  if not callback then
    operation, callback = nil, operation --[[@as bwf.alias.endpoint_callback]]
  end
  method = string.lower(assert(method))
  local map = methods[method] and self.operations or self.additional_operations
  map[method] = { operation = operation, callback = callback }
  return self
end

---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, callback: bwf.alias.endpoint_callback): self
---@return self
function Endpoint:get(operation, callback)
  return self:define('get', operation, callback)
end

---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, callback: bwf.alias.endpoint_callback): self
---@return self
function Endpoint:put(operation, callback)
  return self:define('put', operation, callback)
end

---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, callback: bwf.alias.endpoint_callback): self
---@return self
function Endpoint:post(operation, callback)
  return self:define('post', operation, callback)
end

---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, callback: bwf.alias.endpoint_callback): self
---@return self
function Endpoint:delete(operation, callback)
  return self:define('delete', operation, callback)
end

---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, callback: bwf.alias.endpoint_callback): self
---@return self
function Endpoint:options(operation, callback)
  return self:define('options', operation, callback)
end

---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, callback: bwf.alias.endpoint_callback): self
---@return self
function Endpoint:head(operation, callback)
  return self:define('head', operation, callback)
end

---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, callback: bwf.alias.endpoint_callback): self
---@return self
function Endpoint:patch(operation, callback)
  return self:define('patch', operation, callback)
end

---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, callback: bwf.alias.endpoint_callback): self
---@return self
function Endpoint:trace(operation, callback)
  return self:define('trace', operation, callback)
end

---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, callback: bwf.alias.endpoint_callback): self
---@return self
function Endpoint:query(operation, callback)
  return self:define('query', operation, callback)
end

--- Appends a request hook scoped only to this Endpoint.
--- Runs after App-level and Route-level request hooks.
---@param hook bwd.Hook.resolvable
---@return self
function Endpoint:hookRequest(hook)
  Hook._register_hook(self.hooks, 'request', hook)
  return self
end
--- Run a response hook scoped only to this Endpoint.
--- Runs before Route-level and App-level response hooks.
---@param hook bwd.Hook.resolvable
---@return self
function Endpoint:hookResponse(hook)
  Hook._register_hook(self.hooks, 'response', hook)
  return self
end
--- Appends an error hook scoped only to this Endpoint.
---@param hook bwd.Hook.resolvable
---@return self
function Endpoint:hookError(hook)
  Hook._register_hook(self.hooks, 'error', hook)
  return self
end

return Endpoint
