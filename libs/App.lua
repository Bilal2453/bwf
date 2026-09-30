local Hook = require('Hook')
local Logger = require('Logger')
local Routes = require('Routes')
local WeblitAdapter = require('backends/WeblitAdapter')

local core = require('core')
local default_decoders = require('decoders')
local default_encoders = require('encoders')
local helpers = require('helpers')
local template = require('uri-template')
local termcolor = require('termcolor')

-- TODO: update's App.port after :listen if it initially is 0 (random)

---@class bwf.App.compiled_path: bwf.uri-template
---@field routes bwf.Routes
---@field endpoint bwf.Endpoint

---@class bwf.App.options: table
---@field host string
---@field port integer
---@field tls boolean?
---@field logger bwf.Logger?

local function defaultLogger()
  local logger = Logger:new()
  logger:addStream(io.stdout, {
    level = Logger.level_values.info,
    format = 'pretty',
    color_mode = termcolor.preferredMode(),
  })
  return logger
end

---@return bwf.App.options
local function resolveOptions(options)
  local resolved = {
    host = options.host,
    port = tonumber(options.port),
    tls = options.tls or false,
    logger = options.logger or defaultLogger(),
  }
  if type(resolved.host) ~= 'string' then
    error('Invalid App option "host" (expected a string value)')
  end
  if not resolved.port then
    error('Invalid App option "port" (expected a number value)')
  end
  return resolved
end

--- ### Events emitted:
--- - `server_aborted` – the server aborted its execution abnormally.
--- - `server_stopped` – the server has exited it normally.
--- - `_request_incoming` – the backend received an incoming request.
---@class bwf.App: luvit.core.Emitter
---@field new fun(self: self, options: bwf.App.options): bwf.App
---@field _options bwf.App.options
---@field _backend bwf.Adapter
---@field _encoders { app: { [string]: bwf.App.encoder }, adapter: { [string]: bwf.App.encoder } }
---@field _decoders { app: { [string]: bwf.App.decoder }, adapter: { [string]: bwf.App.decoder } }
---@field interface { host: string, port: integer, tls: boolean? }
---@field logger bwf.Logger
---@field state { is_running: boolean, is_compiled: boolean }
---@field hooks { request: table, response: table, error: table }
---@field main_route bwf.Routes
---@field routes { [bwf.Routes]: true }
---@field static_paths { [string]: bwf.App.compiled_path }
---@field compiled_paths bwf.App.compiled_path[]
local App = core.Emitter:extend()

function App:initialize(options)
  self._options = resolveOptions(options)
  self.interface = {
    host = self._options.host,
    port = self._options.port,
    tls = self._options.tls,
  }
  self.logger = self._options.logger
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

--- Handle an incoming request
---@param call bwf.Call
function App:_dispatch(call)
  self:emit('_request_incoming', call)
end

--- Handle request body decoding on _handleCall.
--- A false return signals the handling should be aborted. true signals it should continue.
---@param call bwf.Call
---@param operation bwf.Operation?
---@return boolean
---@nodiscard
function App:_handleDecoding(call, operation)
  -- is there any defined content to decode?
  if not operation or not operation.body then
    return true
  end
  local body, content = operation.body, operation.body.content --[[@cast body -nil]] --[[@cast content -nil]]
  if not content or not next(content) then
    return true
  end
  -- if Content-Type was not provided behave as if no body was supplied
  local req_type = call.req.type and call.req.type.name
  if not req_type then
    if body.required then
      call:problem('A request body is required', 400)
      return false
    end
    return true
  end
  -- figure out the mime type
  local mimetype_content = content[req_type]
  if not mimetype_content then
    call:problem(string.format('Unsupported Media Type: %s', req_type), 415)
    return false
  end
  -- TODO: schema validation support.
  -- Would be nice for the schema to be generic so users can register their own validators
  -- maybe also invent a Lua table over the wire format?

  -- pick a decoder for the specified content type
  local decoder = self:getBodyDecoder(req_type, 'adapter') or self:getBodyDecoder(req_type, 'app')
  if not decoder then
    return true
  end
  -- do the decoding depending on the decoder mode
  local success, result
  if decoder.phase == 'adapter' then
    success, result = pcall(decoder.decode, call)
  else
    success, result = pcall(decoder.decode, call.req:readBody(), call)
  end
  if not success or not result then
    call:problem('Malformed request payload', 400)
    return false
  end
  call.req.body = result
  return true
end

--- Iterate and execute the hooks, and handle any errors or state changes.
---@param hooks bwf.Hook[]
---@param call bwf.Call
---@param endpoint bwf.Endpoint?
---@param routes bwf.Routes?
---@return boolean continue # Whether the caller should abort or not
---@nodiscard
function App:_handleHooks(hooks, call, endpoint, routes)
  for _, v in ipairs(hooks) do
    local success, err = v:eval(call)
    if not success then
      self:_error({ status = 500, detail = err }, call, endpoint, routes)
      return false
    end
    if call.state.sent or call.state.aborted then
      return false
    end
  end
  return true
end

--- Iterate and execute error hooks, similar to how _handleHooks works, but panics on errors.
---@param hooks bwf.Hook[]
---@param call bwf.Call
---@return boolean
---@nodiscard
function App:_handleErrorHooks(hooks, call)
  for _, v in ipairs(hooks) do
    local success, err = v:eval(call)
    if not success then
      self:_panic(call, err)
      return false
    end
    if call.state.sent or call.state.aborted then
      return false
    end
  end
  return true
end

--- Gracefully raise an internal error and abort the current Call.
--- Problem detail is used as a response to the user agent.
---@param problem bwf.Call.problem
---@param call bwf.Call
---@param endpoint bwf.Endpoint?
---@param routes bwf.Routes?
function App:_error(problem, call, endpoint, routes)
  -- sanity check: make sure the connection is valid
  if call.state.sent or call.state.aborted then
    return
  end
  problem.status = problem.status or 500
  call.state.errored = problem

  -- sanitize the 5xx errors to prevent error leaks
  if problem.status >= 500 then
    self.logger:error(
      'Internal server error while handling "%s %s": %s',
      call.req.method,
      call.req.path.pathname,
      problem.detail or 'unknown error'
    )
    problem = {
      status = problem.status or 500,
    }
  end
  call:problem(problem)

  -- run endpoint error hooks
  if endpoint then
    if not self:_handleErrorHooks(endpoint.hooks.error, call) then
      return
    end
  end
  -- run routes error hooks
  if routes then
    if not self:_handleErrorHooks(routes.hooks.error, call) then
      return
    end
  end
  -- run app error hooks
  if not self:_handleErrorHooks(self.hooks.error, call) then
    return
  end

  -- flush everything
  local success, err = self._backend:flush(call)
  if not success then
    return self:_panic(call, err)
  end
  call.state.sent = true
  self.logger:http(call)
end

--- Handles a hard crash gracefully and abort the call.
---@param call bwf.Call
function App:_panic(call, err)
  self.logger:fatal(
    'A panic occurred while trying to handle "%s": %s\n%s\n',
    call.req.path.pathname,
    err,
    debug.traceback()
  )
  if call.state.sent then
    return
  end
  call.code = 500
  call.headers = {
    ['Content-Type'] = 'text/plain',
    ['Connection'] = 'close',
  }
  call.body = { type = 'raw', data = 'Internal Server Error' }
  pcall(self._backend.flush, self._backend, call)
  call.state.sent = true
  self.logger:http(call)
end

--- Handle an incoming Call request going through its entire lifecycle here.
---@param call bwf.Call
function App:_handleCall(call)
  -- sanity check: ensure we are in the right state
  if call.state.sent or call.state.aborted then
    return
  end

  -- run the app-scope request hooks
  if not self:_handleHooks(self.hooks.request, call) then
    return
  end
  -- find the Routes responsible for handling this call
  local path, matches = self:matchPath(call)
  if not path then
    return self:_error({ status = 404, detail = 'Requested path was not found' }, call)
  end
  local routes = path.routes
  local endpoint = path.endpoint
  -- tell the call about this route's params
  call:_setParams(path, matches)

  -- run the remaining request hooks: routes -> endpoint
  if not self:_handleHooks(routes.hooks.request, call, endpoint, routes) then
    return
  end
  if not self:_handleHooks(endpoint.hooks.request, call, endpoint, routes) then
    return
  end

  -- find the operation handler
  local operation_struct = endpoint:findOperation(call)
  if not operation_struct then
    return self:_error({ status = 405, detail = 'Unsupported HTTP method for this path' }, call, endpoint, routes)
  end

  -- handle request body decoding if configured on the operation
  local operation = operation_struct.operation
  local continue = self:_handleDecoding(call, operation)
  if continue then
    -- execute the operation handler
    local success, err = xpcall(operation_struct.callback, debug.traceback, call)
    if not success then
      return self:_error({ status = 500, detail = err }, call, endpoint, routes)
    end
  end

  -- run response hooks: endpoint -> routes -> app
  if not self:_handleHooks(endpoint.hooks.response, call, endpoint, routes) then
    return
  end
  if not self:_handleHooks(routes.hooks.response, call, endpoint, routes) then
    return
  end
  if not self:_handleHooks(self.hooks.response, call, endpoint, routes) then
    return
  end

  -- send the response
  local success, err = self._backend:flush(call)
  if not success then
    return self:_error({ status = 500, detail = err }, call, endpoint, routes)
  end
  call.state.sent = true
  self.logger:http(call)
end

---@return boolean? success, string? err_msg
function App:start()
  if self.state.is_running then
    return nil, 'Server is already running'
  end
  self.state.is_running = true

  self:compile()

  self:on('_request_incoming', function(call)
    self:_handleCall(call)
  end)

  local success, err = pcall(self._backend.start, self._backend)
  if not success then
    self.state.is_running = false
    self:emit('server_aborted', err)
    return nil, err
  end
  return true
end

---@return boolean? success, string? err_msg
function App:run()
  local co, is_main = coroutine.running()
  if not co or is_main then
    return error('Cannot yield the main thread')
  end
  local success, err = self:start()
  if not success then
    return nil, err
  end
  self:on('server_stopped', function()
    coroutine.resume(co, true)
  end)
  return coroutine.yield()
end

---@return boolean? success, string? err_msg
function App:stop()
  if not self.state.is_running then
    return true
  end
  local success, err = self._backend:stop()
  if not success then
    return nil, err
  end
  self.state.is_running = false
  self:emit('server_stopped')
  return true
end

---@alias bwf.App.encoder { phase: 'app' | 'adapter', encode: (fun(call: bwf.Call): (string?, string?)), content_type?: string }

--- Assign a new body type encoder, this allows one to do custom `Call.body = { type = 'my_type', data = my_data }`.
---@param type_name string
---@param data function | bwf.App.encoder
---@return self
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

  return self
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
---@return self
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

  return self
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

local _match_buf = { n = 0 }
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
    -- using fill to avoid allocating useless empty tables
    local matches = helpers.fill(_match_buf, string.match(path, v.pattern))
    if matches[1] then
      return v, matches
    end
  end
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
