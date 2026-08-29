local Hook = require('Hook')
local Routes = require('Routes')
local WeblitAdapter = require('backends/WeblitAdapter')
local core = require('core')
local template = require('uri-template')

-- TODO: update's App.port after :listen if it initially is 0 (random)

---@class bwf.App.compiled_path: bwf.uri-template
---@field routes bwf.Routes
---@field endpoint bwf.Endpoint

--- ### Events emitted:
--- - `server_aborted` – the server aborted its execution abnormally.
--- - `server_stopped` – the server has exited it normally.
--- - `_request_incoming` – the backend received an incoming request.
---@class bwf.App: luvit.core.Emitter
---@field new fun(self: self, interface: {host: string, port: integer, tls?: boolean}): bwf.App
---@field interface {host: string, port: integer, tls?: boolean}
---@field _backend bwf.Adapter
---@field state {is_running: boolean, is_compiled: boolean}
---@field hooks {request: table, response: table, error: table}
---@field main_route bwf.Routes
---@field routes {[bwf.Routes]: true}
---@field static_paths {}
---@field compiled_paths {}
local App = core.Emitter:extend()

function App:initialize(interface)
  self.interface = interface or {
    host = '127.0.0.1',
    port = 8080,
    tls = false,
  }
  self.state = {
    is_running = false,
    is_compiled = false,
  }
  self.hooks = {
    request = {},
    response = {},
    error = {},
  }
  self.main_route = Routes:new()
  self.routes = {
    [self.main_route] = true,
  }
  self.static_paths = {}
  self.compiled_paths = {}
  self._backend = WeblitAdapter:new(self)
end

function App:start()
  if self.state.is_running then
    return nil, 'Server is already running'
  end
  self.state.is_running = true

  self:compile()

  self:on('_request_incoming', function(call)
    self:_handleCall(call)
  end)

  local success, err = self._backend:start()
  if not success then
    self.state.is_running = false
    self:emit('server_aborted', err)
    return nil, err
  end
  return true
end

function App:stop()
  if not self.state.is_running then
    return
  end
  local success, err = self._backend:stop()
  if not success then
    return nil, err
  end
  self:emit('server_stopped')
  return true
end

-- investigate whether we need the following
-- TODO MAIN 1.4: error handling and HttpError
function App:error(err) end
function App:panic(err) end

--- Registers a Routes object to be routable by this App's server.
---@param routes bwf.Routes
---@return self
function App:registerRoutes(routes)
  if self.routes[routes] then
    error('Routes object is already registered')
  end
  self.routes[routes] = true
  return self
end

--- Registers an Endpoint with the given path under the main App's Routes.
---@param path string
---@param endpoint bwf.Endpoint
---@return self
function App:registerEndpoint(path, endpoint)
  self.main_route:register(path, endpoint)
  return self
end

function App:compile()
  for routes in pairs(self.routes) do
    for _, endpoint_struct in ipairs(routes.endpoints) do
      -- TODO: make sure full_path is path only and contains no query/hash portions
      local full_path = template.join(routes.prefix, endpoint_struct.path)
      local temp = template.parseTemplate(full_path) --[[@as bwf.App.compiled_path]]
      temp.routes = routes
      temp.endpoint = endpoint_struct.endpoint
      if temp.is_static then
        self.static_paths[temp.path] = temp
      else
        table.insert(self.compiled_paths, temp)
      end
    end
  end
end

---@param hook bwd.Hook.resolvable
---@return self
function App:hookRequest(hook)
  hook = Hook.resolve(hook)
  table.insert(self.hooks.request, hook)
  return self
end

---@param hook bwd.Hook.resolvable
---@return self
function App:hookResponse(hook)
  hook = Hook.resolve(hook)
  table.insert(self.hooks.response, hook)
  return self
end

---@param hook bwd.Hook.resolvable
---@return self
function App:hookError(hook)
  hook = Hook.resolve(hook)
  table.insert(self.hooks.error, hook)
  return self
end

function App:generateOpenAPI()
  -- TODO
end

--- Searches currently registered routes for the path of `call.path`.
---@param call bwf.Call
---@return bwf.App.compiled_path?, string[]?
---@nodiscard
function App:matchPath(call)
  local path = call.req.path
  if self.static_paths[path] then
    return self.static_paths[path]
  end
  for _, v in ipairs(self.compiled_paths) do
    local matches = { string.match(path.pathname, v.pattern) }
    if #matches > 0 then
      return v, matches
    end
  end
end

---@param call bwf.Call
function App:_handleCall(call)
  -- run the app-scope request hooks
  Hook.iter(call, self.hooks.request)

  -- find the Routes responsible for handling this call
  local path, matches = self:matchPath(call)
  if not path then
    -- TODO: we still need to flush the response in this case
    return self:error('Route handler was not found')
  end
  local routes = path.routes
  local endpoint = path.endpoint
  call:_setParams(path, matches)

  -- run the remaining request hooks: routes -> endpoint
  Hook.iter(call, routes.hooks.request)
  Hook.iter(call, endpoint.hooks.request)

  -- find the operation handler
  local operation, err = endpoint:findOperation(call)
  if not operation then
    return self:error(err)
  end
  -- execute the operation handler
  local success, err = pcall(operation.callback, call)
  if not success then
    return self:error(err)
  end

  -- run response hooks: endpoint -> routes -> app
  Hook.iter(call, endpoint.hooks.response)
  Hook.iter(call, routes.hooks.response)
  Hook.iter(call, self.hooks.response)

  -- send the response
  local success, err = self._backend:flush(call)
  if not success then
    -- TODO: this error should probably be a panic because a flush shouldn't fail
    return self:error(err)
  end
  call.state.sent = true
end

--- Handle an incoming request
---@param call bwf.Call
function App:_dispatch(call)
  self:emit('_request_incoming', call)
end

--- Registers a new Endpoint using the `App.main_route`.
---
--- Equivalent to `App.main_route:define()`.
---@param method bwf.alias.http_method
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function App:define(method, path, callback, operation)
  self.main_route:define(method, path, callback, operation)
  return self
end

--- Equivalent to `App.main_route:get()`.
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function App:get(path, callback, operation)
  return self:define('get', path, callback, operation)
end

--- Equivalent to `App.main_route:post()`.
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function App:post(path, callback, operation)
  return self:define('post', path, callback, operation)
end

--- Equivalent to `App.main_route:put()`.
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function App:put(path, callback, operation)
  return self:define('put', path, callback, operation)
end

--- Equivalent to `App.main_route:delete()`.
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function App:delete(path, callback, operation)
  return self:define('delete', path, callback, operation)
end

--- Equivalent to `App.main_route:patch()`.
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function App:patch(path, callback, operation)
  return self:define('patch', path, callback, operation)
end

--- Equivalent to `App.main_route:options()`.
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function App:options(path, callback, operation)
  return self:define('options', path, callback, operation)
end

--- Equivalent to `App.main_route:head()`.
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function App:head(path, callback, operation)
  return self:define('head', path, callback, operation)
end

--- Equivalent to `App.main_route:trace()`.
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function App:trace(path, callback, operation)
  return self:define('trace', path, callback, operation)
end

--- Equivalent to `App.main_route:query()`.
---@param path string
---@param callback bwf.alias.endpoint_callback
---@param operation bwf.Operation?
---@return self
function App:query(path, callback, operation)
  return self:define('query', path, callback, operation)
end

return App
