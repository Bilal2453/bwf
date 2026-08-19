local core = require('core')
local template = require('template')
local Hook = require('Hook')
local Endpoint = require('Endpoint')

--- Represents a logical grouping of API endpoints sharing a common URI prefix and metadata.
--- It manages route hierarchy and endpoint registration prior to any compilation.
---@class bwf.Routes: luvit.core.Object
---@field new fun(self: self, options: bwf.Routes.options?): bwf.Routes
---@field endpoints bwf.Endpoint.struct[].
---@field registered_paths {[string]: bwf.Endpoint.struct}
---@field prefix string
---@field parameters bwf.Parameter[]
---@field responses {[string]: bwf.Response}
---@field tags string[]
---@field docs bwf.Doc[]
---@field security table
---@field callbacks table
---@field servers table
local Routes = core.Object:extend()

function Routes:initialize(options)
  options = options or {}
  self.endpoints = {}
  self.registered_paths = {}
  self.prefix = options.prefix or ''

  self.hooks = {
    request = {},
    response = {},
    error = {}
  }

  self.responses = options.responses or {}
  self.parameters = self.parameters or {}
  self.tags = options.tags or {}
  self.security = options.security or {}
  self.servers = options.servers or {}
  self.docs = options.docs or {}
  self.callbacks = options.callbacks or {}
end

--- Retrieve a registered Endpoint object by its assigned path.
---@param path string
---@return bwf.Endpoint.struct?
function Routes:getEndpoint(path)
  path = template.normalize(path)
  return self.registered_paths[path]
end

--- Register an Endpoint object with the given path.
--- `options` override the defaults specified in this Routes instance.
---@param path string
---@param endpoint bwf.Endpoint
---@param options bwf.Endpoint.options?
---@return self
function Routes:register(path, endpoint, options)
  path = template.normalize(path)
  local struct = {
    endpoint = endpoint,
    options = options or {},
    path = path,
  }
  self.registered_paths[path] = struct
  table.insert(self.endpoints, struct)
  return self
end

--- Create and register a new Endpoint and operation.
--- 
--- Note that every call creates an entirely new Endpoint object,
--- if you want to share multiple operations under the same Endpoint, create it manually instead.
--- 
--- This is a shortcut to the following pattern:
--- ```lua
---   local endpoint = Endpoint:new()
---   endpoint:define(method, callback, operation)
---   app:register(path, endpoint)
--- ```
---@param method bwf.alias.http_method
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Routes:define(method, path, callback, operation)
  local endpoint = Endpoint:new()
  endpoint:define(method, callback, operation)
  return self:register(path, endpoint)
end

--- Create and register a new Endpoint with the given path as a GET operation.
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Routes:get(path, callback, operation)
  return self:define('get', path, callback, operation)
end

--- Create and register a new Endpoint with the given path as a POST operation.
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Routes:post(path, callback, operation)
  return self:define('post', path, callback, operation)
end

---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Routes:put(path, callback, operation)
  return self:define('put', path, callback, operation)
end

---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Routes:delete(path, callback, operation)
  return self:define('delete', path, callback, operation)
end

---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Routes:patch(path, callback, operation)
  return self:define('patch', path, callback, operation)
end

---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Routes:options(path, callback, operation)
  return self:define('options', path, callback, operation)
end

---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Routes:head(path, callback, operation)
  return self:define('head', path, callback, operation)
end

---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Routes:trace(path, callback, operation)
  return self:define('trace', path, callback, operation)
end

---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function Routes:query(path, callback, operation)
  return self:define('query', path, callback, operation)
end


---Appends a request hook scoped only to this Routes.
---Runs after App-level and Route-level request hooks.
---@param hook bwd.Hook.resolvable
---@return self
function Routes:hookRequest(hook)
  hook = Hook.resolve(hook)
  table.insert(self.hooks.request, hook)
  return self
end
---Appends a response hook scoped only to this Routes.
---Runs before Route-level and App-level response hooks.
---@param hook bwd.Hook.resolvable
---@return self
function Routes:hookResponse(hook)
  hook = Hook.resolve(hook)
  table.insert(self.hooks.response, hook)
  return self
end
---Appends an error hook scoped only to this Routes.
---@param hook bwd.Hook.resolvable
---@return self
function Routes:hookError(hook)
  hook = Hook.resolve(hook)
  table.insert(self.hooks.error, hook)
  return self
end

return Routes
