local Endpoint = require('Endpoint')
local Hook = require('Hook')
local core = require('core')
local template = require('uri-template')

--- Represents a logical grouping of API endpoints sharing a common URI prefix and metadata.
---
--- Properties defined in the Endpoint take precedence over ones defined in the Routes instance according to the following rules:
---   - Parameters of the same name are replaced by their Endpoint counterpart, the rest is inherited.
---   - Responses that has the same code are replaced by their Endpoint counterpart, the rest is inherited.
---   - Security, tags, servers, callbacks and docs are replaced entirely by their Endpoint counterparts.
---@class bwf.Routes: luvit.core.Object
---@field new fun(self: self, options: bwf.Routes.options?): bwf.Routes
---@field hooks bwf.Hook.scope
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

  self.hooks = Hook._create_scope()

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

--- Merge options with their defaults from Routes instance.
---@param options bwf.Routes.options?
---@param routes bwf.Routes
---@return bwf.Endpoint.options
---@nodiscard
local function resolveOptions(options, routes)
  local resolved = {
    parameters = routes.parameters,
    response = routes.responses,
    tags = routes.tags,
    docs = routes.docs,
    security = routes.security,
    servers = routes.servers,
    callbacks = routes.callbacks,
  }
  if not options then
    return resolved
  end

  if options.tags then
    resolved.tags = options.tags
  end
  if options.docs then
    resolved.docs = options.docs
  end
  if options.security then
    resolved.security = options.security
  end
  if options.servers then
    resolved.servers = options.servers
  end
  if options.callbacks then
    resolved.callbacks = options.callbacks
  end

  if options.parameters then
    local parameters, overridden = {}, {}
    for _, param in ipairs(options.parameters) do
      table.insert(parameters, param)
      overridden[param.name] = true
    end
    for _, param in ipairs(routes.parameters) do
      if not overridden[param.name] then
        table.insert(parameters, param)
      end
    end
    resolved.parameters = parameters
  end

  if options.responses then
    local responses = {}
    for code, res in pairs(routes.responses) do
      responses[code] = res
    end
    for code, res in pairs(options.responses) do
      responses[code] = res
    end
    resolved.response = responses
  end

  return resolved
end

--- Register an Endpoint object with the given path.
--- `options` override the defaults specified in this Routes instance.
---@param path string
---@param options bwf.Endpoint.options?
---@param endpoint bwf.Endpoint
---@overload fun(self: self, path: string, endpoint: bwf.Endpoint): self
---@return self
function Routes:register(path, options, endpoint)
  if not endpoint then
    options, endpoint = nil, options --[[@as bwf.Endpoint]]
  end
  path = template.normalize(path)
  options = resolveOptions(options, self)
  local struct = {
    endpoint = endpoint,
    options = options,
    path = path,
  }
  self.registered_paths[path] = struct
  table.insert(self.endpoints, struct)
  return self
end

--- Create and register a new Endpoint and operation.
---
--- This is a shortcut to the following pattern:
--- ```lua
---   local endpoint = Endpoint:new()
---   endpoint:define(method, operation, callback)
---   app:register(path, endpoint)
--- ```
---@param method bwf.alias.http_method
---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, method: bwf.alias.http_method, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function Routes:define(method, path, operation, callback)
  if not callback then
    operation, callback = nil, operation --[[@as bwf.alias.endpoint_callback]]
  end
  local old_endpoint = self:getEndpoint(path)
  local endpoint = old_endpoint and old_endpoint.endpoint or Endpoint:new()
  endpoint:define(method, operation, callback)
  return self:register(path, endpoint)
end

--- Create and register a new Endpoint with the given path as a GET operation.
---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function Routes:get(path, operation, callback)
  return self:define('get', path, operation, callback)
end

--- Create and register a new Endpoint with the given path as a POST operation.
---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function Routes:post(path, operation, callback)
  return self:define('post', path, operation, callback)
end

---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function Routes:put(path, operation, callback)
  return self:define('put', path, operation, callback)
end

---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function Routes:delete(path, operation, callback)
  return self:define('delete', path, operation, callback)
end

---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function Routes:patch(path, operation, callback)
  return self:define('patch', path, operation, callback)
end

---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function Routes:options(path, operation, callback)
  return self:define('options', path, operation, callback)
end

---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function Routes:head(path, operation, callback)
  return self:define('head', path, operation, callback)
end

---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function Routes:trace(path, operation, callback)
  return self:define('trace', path, operation, callback)
end

---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function Routes:query(path, operation, callback)
  return self:define('query', path, operation, callback)
end

---Appends a request hook scoped only to this Routes.
---Runs after App-level and Route-level request hooks.
---@param hook bwd.Hook.resolvable
---@return self
function Routes:hookRequest(hook)
  Hook._register_hook(self.hooks, 'request', hook)
  return self
end
---Appends a response hook scoped only to this Routes.
---Runs before Route-level and App-level response hooks.
---@param hook bwd.Hook.resolvable
---@return self
function Routes:hookResponse(hook)
  Hook._register_hook(self.hooks, 'response', hook)
  return self
end
---Appends an error hook scoped only to this Routes.
---@param hook bwd.Hook.resolvable
---@return self
function Routes:hookError(hook)
  Hook._register_hook(self.hooks, 'error', hook)
  return self
end

return Routes
