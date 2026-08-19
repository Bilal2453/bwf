local config = require('config')
local core = require('core')
local json = require('json')
local utils = require('util')
local weblit = {
  server = require('weblit-server'),
  router = require('weblit-router'),
  auth = require('weblit-auth'),
  autoHeaders = require('weblit-auto-headers'),
  etlua = require('weblit-etlua'),
  etagCache = require('weblit-etag-cache'),
  static = require('weblit-static'),
}

---@class Bwf.res: weblit.res
---@field respond function
---@field success function
---@field error function

---@alias Bwf.handler fun(req: auth.weblit.req, res: Bwf.res, go: function)
---@alias Bwf.route {method?: weblit.httpmethods, path?: string, errors?: string[], cb: auth.weblit.handler}
---@alias Bwf.routes {[string]: Bwf.route}

---@class app: luvit.core.Object
---@field new fun(self: self, interface: {host: string, port: integer} | nil): app
---@field main_router weblit.router
---@field server weblit.server
---@field routers weblit.router[]
---@field interface {host: string, port: integer, tls: boolean} | nil
local app = core.Object:extend()
function app:initialize(interface)
  self.routers = {}
  self.interface = interface or {}
  self.main_router = weblit.router.newRouter()
  self.server = weblit.server.newServer(self.main_router.run)

  -- stop server.start from being able to print things
  -- TODO: inject our own logger?
  local env = getfenv()
  env.print = function() end
  setfenv(self.server.start, env)

  self._loaded_endpoints = {}
end

---@param route Bwf.route
function app:loadRoute(route, prefix)
  if type(route) ~= 'table' then
    error('Expected a table, got ' .. type(route))
  end
  if prefix and route.path then
    route.path = utils.joinUrlPath(prefix, route.path)
  end
  if route.errors then
    route.errors = self.prepareError(route.path, route.errors)
  end
  self.main_router.route(route --[[@as weblit.req]], route.cb)
  utils.log('debug', 'Loaded route %s - %s', route.method, route.path)
end

function app:loadRoutes(name, routes)
  local prefix = utils.joinUrlPath(API_PREFIX, 'v' .. endpoints._latest_version)
  local t = type(routes)
  if t == 'table' then
    for route_name, route in pairs(routes) do
      route_name = utils.joinUrlPath(name, route_name)
      if not route.cb then
        self:loadRoutes(route_name, route)
      elseif not self._loaded_endpoints[route_name] then
        self:loadRoute(route, prefix)
        self._loaded_endpoints[route_name] = true
      end
    end
  elseif t == 'function' and not self._loaded_endpoints[name] then
    assert(routes(self, prefix))
    self._loaded_endpoints[name] = true
  end
end

function app:loadEndpoints(endpoint_list)
  for name, routes in pairs(endpoint_list) do
    if not self._loaded_endpoints[name] then
      self:loadRoutes(name, routes)
    end
  end
end

--- Server

function app:bind(interface)
  self.server.bind(interface or self.interface)
end

function app:start()
  self.server.start()
end

--- Router

---@param options {no_logger?: boolean, no_assign?: boolean}?
---@return weblit.router
---@nodiscard
function app:newRouter(options)
  options = options or {}
  ---@type weblit.router
  local r = weblit.router.newRouter()
  if not options.no_assign then
    table.insert(self.routers, r)
  end
  if not options.no_logger then
    r.use(self.logger)
  end
  return r
end

--- Static

function app.logger(req, res, go)
  if not req.headers['user-agent'] then
    return go()
  end
  go()
  utils.log('debug', '%s - %s - %s', req.method, req.path, res.code)
end

function app.helpers(req, res, go)
  res.respond = app.respond
  res.success = app.success
  res.error = app.error

  local content_type = (req.headers['Content-Type'] or ''):lower()
  if req.body and content_type == 'application/json' then
    local decoded, pos, msg = json.decode(req.body)
    if not decoded then
      return res:respond(400, 'Bad JSON request: at position %s: %s', pos, msg)
    end
    req.json = decoded
  end
  go()
end

function app.setLang(_, res, go)
  res.locale = 'en'
  go()
end

--- Common

function app.respond(res, code, reason_or_body, ...)
  if reason_or_body and select('#', ...) > 0 then
    reason_or_body = reason_or_body:format(...)
  end

  res.code = code
  if type(reason_or_body) == 'table' then
    res.body = assert(json.encode(reason_or_body))
    res.headers['Content-Type'] = 'application/json'
  else
    res.body = reason_or_body
    res.headers['Content-Type'] = 'text/plain'
  end
end
function app.success(res, data, code)
  code = code and tonumber(code) or 200
  app.respond(res, code, data)
end
function app.error(res, code, details, status)
  local message
  if locale.errors[code] then
    message = locale.errors[code][config.WEB_UI.DEFAULT_LOCALE]
  else
    utils.log('warning', 'Error code "%s" has no %s locale defined', code, config.WEB_UI.DEFAULT_LOCALE)
    message = locale.errors.UNKNOWN_ERROR[config.WEB_UI.DEFAULT_LOCALE]
  end
  status = status and tonumber(status) or 400
  res.headers['Content-Type'] = 'application/json'
  res.code = status
  res.body = json.encode({
    status = status,
    error_code = code,
    message = message,
    details = details,
  })
end

function app.prepareError(endpoint_path, errors)
  local map = utils.tblToMap(errors)
  return setmetatable(map, {
    __index = function(_, k)
      local v = rawget(map, k)
      if not v then
        utils.log('error', 'API handler "%s" is using an unregistered error "%s"', endpoint_path, k)
      end
      return v or 'UNKNOWN_ERROR'
    end,
  })
end

return app
