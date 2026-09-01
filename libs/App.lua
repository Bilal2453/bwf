local Hook = require('Hook')
local Routes = require('Routes')
local WeblitAdapter = require('backends/WeblitAdapter')
local core = require('core')
local default_decoders = require('decoders')
local default_encoders = require('encoders')
local template = require('uri-template')

-- TODO: update's App.port after :listen if it initially is 0 (random)
-- TODO: document App class fields

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

  self._encoders = { app = {}, adapter = {} }
  self:_applyDefaultEncoders()
  self._decoders = { app = {}, adapter = {} }
  self:_applyDefaultDecoders()
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

---@alias bwf.App.encoder { phase: 'app' | 'adapter', encode: (fun(call: bwf.Call): (string?, string?)), content_type?: string }

--- Assign a new body type encoder, this allows one to do custom `Call.body = { type = 'my_type', data = my_data }`.
---@param type_name string
---@param data function | bwf.App.encoder
function App:registerBodyEncoder(type_name, data)
  assert(type(type_name) == 'string', 'bad argument #2 to registerBodyEncoder (expected a string)')
  local t = type(data)
  if t == 'function' then
    data = {
      encode = data,
    }
  elseif t ~= 'table' then
    error('bad argument #3 to registerBodyEncoder (expected a table or a function)')
  end
  assert(type(data.encode) == 'function', 'bad property value for data.encode (expected a function)')

  data.phase = data.phase or 'app'
  if not self._encoders[data.phase] then
    error('bad property value for data.phase (expected one of "app" or "adapter")')
  end
  if self._encoders[data.phase][type_name] then
    error('"' .. type_name .. '" is already a registered body type name')
  end
  self._encoders[data.phase][type_name] = data
end

--- Retrieve an assigned body encoder.
---@param type_name string
---@param phase 'app' | 'adapter' | nil # default: `"app"`.
---@return bwf.App.encoder?
function App:getBodyEncoder(type_name, phase)
  phase = phase or 'app'
  return self._encoders[phase][type_name]
end

function App:_applyDefaultEncoders()
  for t, s in pairs(default_encoders) do
    self:registerBodyEncoder(t, s)
  end
end

---@alias bwf.App.decoder { phase?: 'app' | 'adapter', decode: (fun(raw_body: string, call: bwf.Call): any) | (fun(call: bwf.Call): any) }

--- Assign a new request body decoder for a specific MIME type.
---@param mime_type string
---@param data function | bwf.App.decoder
function App:registerBodyDecoder(mime_type, data)
  assert(type(mime_type) == 'string', 'bad argument #2 to registerBodyDecoder (expected a string)')
  local t = type(data)
  if t == 'function' then
    data = {
      decode = data,
    }
  elseif t ~= 'table' then
    error('bad argument #3 to registerBodyDecoder (expected a table or a function)')
  end
  assert(type(data.decode) == 'function', 'bad property value for data.decode (expected a function)')

  data.phase = data.phase or 'app'
  if not self._decoders[data.phase] then
    error('bad property value for data.phase (expected one of "app" or "adapter")')
  end

  if self._decoders[data.phase][mime_type] then
    error('"' .. mime_type .. '" is already a registered body decoder MIME type')
  end
  self._decoders[data.phase][mime_type] = data
end

--- Retrieve an assigned body decoder for a MIME type.
---@param mime_type string
---@param phase 'adapter' | 'app' | nil # default: `"app"`.
---@return bwf.App.decoder?
function App:getBodyDecoder(mime_type, phase)
  phase = phase or 'app'
  return self._decoders[phase][mime_type]
end

function App:_applyDefaultDecoders()
  for mime, d in pairs(default_decoders) do
    self:registerBodyDecoder(mime, d)
  end
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
  local path = template.normalize(call.req.path.pathname)
  if self.static_paths[path] then
    return self.static_paths[path]
  end
  for _, v in ipairs(self.compiled_paths) do
    local matches = { string.match(path, v.pattern) }
    if #matches > 0 then
      return v, matches
    end
  end
end

--- Handle request body decoding on _handleCall.
--- A false return signals the handling should be aborted. true signals it should continue.
---@param call bwf.Call
---@param operation bwf.Operation?
---@return boolean
---@nodiscard
function App:_handleDecoding(call, operation)
  if not (operation and operation.body and operation.body.content and next(operation.body.content)) then
    return true
  end
  local body, content = operation.body, operation.body.content --[[@cast body -nil]] --[[@cast content -nil]]
  local req_type = call.req.type and call.req.type.name
  if not req_type then
    if body.required then
      call:empty(400)
      return false
    end
    return true
  end
  local mimetype_content = content[req_type]
  if not mimetype_content then
    call:empty(415)
    return false
  end
  -- TODO: schema validation support.
  -- Would be nice for the schema to be generic so users can register their own validators
  -- maybe also invent a Lua table over the wire format?

  local decoder = self:getBodyDecoder(req_type, 'adapter') or self:getBodyDecoder(req_type, 'app')
  if not decoder then
    return true
  end
  local success, result
  if decoder.phase == 'adapter' then
    success, result = pcall(decoder.decode, call)
  else
    success, result = pcall(decoder.decode, call.req:readBody(), call)
  end
  if not success or not result then
    call:empty(400)
    return false
  end
  call.req.body = result
  return true
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
  local operation_struct, err = endpoint:findOperation(call)
  if not operation_struct then
    return self:error(err)
  end

  -- handle request body decoding if configured on the operation
  local operation = operation_struct.operation
  local continue = self:_handleDecoding(call, operation)
  if continue then
    -- execute the operation handler
    local success, err = pcall(operation_struct.callback, call)
    if not success then
      -- TODO: do we want to give hooks a chance to run as well?
      return self:error(err)
    end
  end

  -- run response hooks: endpoint -> routes -> app
  Hook.iter(call, endpoint.hooks.response)
  Hook.iter(call, routes.hooks.response)
  Hook.iter(call, self.hooks.response)

  -- send the response
  local success, err = self._backend:flush(call)
  if not success then
    -- TODO: check if this is the right way to do error here, likely coming from encoder
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
function App:define(method, path, operation, callback)
  if not callback then
    operation, callback = nil, operation --[[@as bwf.alias.endpoint_callback]]
  end
  self.main_route:define(method, path, operation, callback)
  return self
end

--- Equivalent to `App.main_route:get()`.
---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function App:get(path, operation, callback)
  return self:define('get', path, operation, callback)
end

--- Equivalent to `App.main_route:post()`.
---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function App:post(path, operation, callback)
  return self:define('post', path, operation, callback)
end

--- Equivalent to `App.main_route:put()`.
---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function App:put(path, operation, callback)
  return self:define('put', path, operation, callback)
end

--- Equivalent to `App.main_route:delete()`.
---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function App:delete(path, operation, callback)
  return self:define('delete', path, operation, callback)
end

--- Equivalent to `App.main_route:patch()`.
---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function App:patch(path, operation, callback)
  return self:define('patch', path, operation, callback)
end

--- Equivalent to `App.main_route:options()`.
---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function App:options(path, operation, callback)
  return self:define('options', path, operation, callback)
end

--- Equivalent to `App.main_route:head()`.
---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function App:head(path, operation, callback)
  return self:define('head', path, operation, callback)
end

--- Equivalent to `App.main_route:trace()`.
---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function App:trace(path, operation, callback)
  return self:define('trace', path, operation, callback)
end

--- Equivalent to `App.main_route:query()`.
---@param path string
---@param operation bwf.Operation?
---@param callback bwf.alias.endpoint_callback
---@overload fun(self: self, path: string, callback: bwf.alias.endpoint_callback): self
---@return self
function App:query(path, operation, callback)
  return self:define('query', path, operation, callback)
end

return App
