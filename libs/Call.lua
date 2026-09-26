local CallReq = require('CallReq')
local cookies = require('cookies')
local core = require('core')
local http_status = require('http_status')
local url = require('uri')

---@class bwf.Call: luvit.core.Object
---@field new fun(self: self, app: bwf.App, adapter: bwf.Adapter, backend_stat: table)
---@field app bwf.App
---@field adapter bwf.Adapter
---@field req bwf.CallReq
---@field headers { [string]: string | string[] | nil }
---@field body { type: string, data: any } | table
---@field state { sent: boolean, matched: boolean, aborted: boolean, errored: false | bwf.Call.problem, _backend: table } | table
---@field storage table # A plain Lua table used to store various data related to the Call, useful for interceptors.
---@field protected _compiled_path bwf.App.compiled_path?
---@field protected _parameters {[string]: string?}?
local Call = core.Object:extend()

-- TODO: a generic Call:respond(table[, response]) that uses the client Accept header for picking an encoder
-- TODO: investigate adding a Call._interceptors_stack for logging every interceptor that
-- this Call object has gone through

---@param adapter bwf.Adapter
function Call:initialize(app, adapter, backend_state)
  self.app = app
  self.adapter = adapter
  self.state = {
    sent = false,
    matched = false,
    aborted = false,
    errored = false,
    _backend = backend_state,
  }
  self.storage = {} -- TODO: maybe add more restrictions or abstractions?

  self.req = CallReq:new(self, adapter)

  self._compiled_path = nil
  self._parameters = nil
  self.headers = {}
  self.code = 404
  self.body = { type = 'raw', data = 'Not found' }
end

---@protected
---@return 'app' | 'adapter' | nil, fun(call: bwf.Call) | string
function Call:_finalize()
  -- handle basic body types
  if self.body.type == 'raw' then
    if not self:hasHeader('Content-Type') then
      self:setHeader('Content-Type', 'text/plain')
    end
    return 'app', self.body.data == nil and '' or tostring(self.body.data)
  elseif self.body.type == 'empty' then
    return 'app', ''
  end
  -- retrieve the encoder for this body type
  local encoder = self.app:getBodyEncoder(self.body.type, 'adapter') or self.app:getBodyEncoder(self.body.type, 'app')
  if not encoder then
    error('Unsupported body type ' .. tostring(self.body.type))
  end
  -- if the content type hasn't been set, try to guess it from encoder
  if not self:hasHeader('Content-Type') and encoder.content_type then
    self:setHeader('Content-Type', encoder.content_type)
  end
  -- encode and return the results
  if encoder.phase == 'app' then
    local result, err = encoder.encode(self)
    if result and type(result) ~= 'string' then
      error('Body encoder returned a non-string value: ' .. self.body.type)
    elseif not result then
      return nil, err --[[@as string]]
    else
      return 'app', result
    end
  else
    return 'adapter', encoder.encode
  end
end

--- A private method called by the App instance when a matching route is found.
--- We can only map out the parameters after we know what route to match, hence this method.
---@param compiled_path bwf.App.compiled_path
---@param matches string[]?
function Call:_setParams(compiled_path, matches)
  if self.state.matched then
    -- this code path should be unreachable
    error('This Call has already been matched')
  end
  self.state.matched = true
  self._compiled_path = compiled_path
  if matches then
    local params = {}
    for pos, name in ipairs(compiled_path.params) do
      params[name] = matches[pos]
    end
    self._parameters = params
  end
end

--- Retrieve a named path parameter.
--- If this is executed before the routing phase (e.x. app-scope request hooks) there will be no parameters to return,
--- therefore this method will raise an error, instead of just returning an ambiguous `nil` value.
---@param name string
---@param default_value any?
---@return string?
---@nodiscard
function Call:getParam(name, default_value)
  if not self.state.matched then
    error('Cannot read the parameters before the routing phase has completed.')
  end
  if not self._parameters then
    return
  end
  -- TODO: type coercion
  return self._parameters[name] ~= nil and self._parameters[name] or default_value
end

--- Set a response header. The name is case-insensitive. If the value is an array the header will be set multiple times for each value.
--- If the value is `nil` the header will be removed, similar to calling `Call:removeHeader(name)`.
---@param name string
---@param value string | string[]
---@return self
function Call:setHeader(name, value)
  name = string.lower(name)
  if value == nil then
    self.headers[name] = nil
  elseif type(value) == 'table' then
    self.headers[name] = value
  else
    self.headers[name] = tostring(value)
  end
  return self
end

--- Return a response header, if set.
--- If the requested header is not set `default_value` is returned, which is `nil` by default.
---@param name string
---@param default_value any
---@return string|string[]|nil
---@nodiscard
function Call:getHeader(name, default_value)
  return self.headers[name] or default_value
end

--- Returns whether a header is set or not in the response.
---@param name string
---@return boolean
---@nodiscard
function Call:hasHeader(name)
  return not not self.headers[name]
end

--- Removes and unset a response header. Does nothing if the header does not exists.
---@param name string
---@return self
function Call:removeHeader(name)
  self.headers[name] = nil
  return self
end

--- Similar to `Call:setHeader` but if a header is already set it will add an additional field instead of overriding the old one.
---@param name string
---@param value string | string[]
---@return self
function Call:appendHeader(name, value)
  if not value then
    return self
  end
  name = string.lower(name)

  -- if no old value then we can just use setHeader
  local old_value = self.headers[name]
  if not old_value then
    self:setHeader(name, value)
    return self
  end

  -- combine old values with the new ones
  if type(old_value) ~= 'table' then
    old_value = { old_value }
  end
  if type(value) == 'table' then
    for _, v in ipairs(value) do
      old_value[#old_value + 1] = tostring(v)
    end
  else
    old_value[#old_value + 1] = tostring(value)
  end

  self.headers[name] = old_value
  return self
end

---@protected
---@param status integer
---@return self
function Call:_setStatus(status)
  self.code = tonumber(status)
  return self
end

---@param data table
---@param status integer? # Default: `200`.
---@return self
function Call:json(data, status)
  if type(data) ~= 'table' then
    error('bad argument #2 to Call.json (expected table, got ' .. type(data) .. ')')
  end
  self:_setStatus(status or 200)
  self:setHeader('Content-Type', 'application/json')
  self.body = { type = 'json', data = data }
  return self
end

---@param text string
---@param status integer? # Default: `200`.
---@return self
function Call:text(text, status, ...)
  if select('#', ...) > 0 then
    text = string.format(text, ...)
  end
  self:_setStatus(status or 200)
  self:setHeader('Content-Type', 'text/plain')
  self.body = { type = 'raw', data = text }
  return self
end

---@param html string
---@param status integer? # Default: `200`.
---@return self
function Call:html(html, status)
  self:_setStatus(status or 200)
  self:setHeader('Content-Type', 'text/html')
  self.body = { type = 'raw', data = html }
  return self
end

---@param status integer? # Default: `301`.
---@return self
function Call:redirect(location, status)
  self:_setStatus(status or 301)
  self:setHeader('Location', url.percentEncode(location))
  self.body = { type = 'empty' }
  return self
end

---@param status integer
---@return self
function Call:empty(status)
  self:_setStatus(status or 204)
  self.body = { type = 'empty' }
  return self
end

---@class bwf.Call.problem: table
---@field type string?
---@field status integer?
---@field title string?
---@field detail string?
---@field instance string?

--- RFC 9457
---@param problem bwf.Call.problem | string | nil
---@param status integer? # Default: `400`.
function Call:problem(problem, status)
  -- evaluate the problem structure
  local t = type(problem)
  local data = {}
  if t == 'table' then
    for k, v in pairs(problem) do
      data[k] = v
    end
  elseif t == 'string' then
    data.detail = problem
  elseif problem ~= nil then
    error('bad argument #2 to Call.problem (expected table or string)')
  end
  if status ~= nil and data.status ~= nil and data.status ~= status then
    error(
      'Contradicting HTTP status code detected: A Problem Detail structure must match the set response code per RFC 9457'
    )
  end
  -- set missing fields
  status = status or data.status or 400
  data.type = data.type or 'about:blank'
  data.title = data.title or http_status[status]
  data.status = status
  data.instance = data.instance or self.req.path.pathname
  -- set response
  self:_setStatus(status)
  self.body = { type = 'problem', data = data }
  return self
end

--- Sets a cookie on the User Agent client by sending a `Set-Cookie` header.
---@param name string
---@param value string | number
---@param attributes? bwf.Cookies.attributes
function Call:setCookie(name, value, attributes)
  return self:appendHeader('Set-Cookie', cookies.formatCookie(name, value, attributes))
end

--- Instructs the User Agent client to unset and remove a previously set cookie.
--- Note that if the targeted cookie has a Path/Domain set then you must match them here as well.
---@param name string
---@param attributes? bwf.Cookies.attributes
function Call:removeCookie(name, attributes)
  attributes = attributes or {}
  attributes.maxAge = 0
  return self:appendHeader('Set-Cookie', cookies.formatCookie(name, '', attributes))
end

-- TODO: investigate the API design of the following ideas
function Call:file() end
function Call:render(template, data, status) end

--- Forcibly terminates network connections related to this Call.
--- Only invoke this method when you *explicitly* want to drop the connection, otherwise you can send empty responses with `Call:empty()`.
---
--- By default, the connection will be hard terminated, but it's possible to terminate the connection more gracefully by setting `send_body` to `true`,
--- which will send the Call.body with a `Connection: close` header then terminate the connection, this is the recommended behavior.
--- The default is `false` only to prevent accidental leaks.
---
--- Example:
--- ```lua
--- call:problem('Maximum upload limit (10MiB) exceeded', 413)
--- call:abort(true)
--- ```
---@param send_body boolean # Default: `false`.
---@return self
function Call:abort(send_body)
  if self.state.aborted then
    return self
  end
  self.state.aborted = true

  if send_body and not self.state.sent then
    self:setHeader('Connection', 'close')
    self.adapter:flush(self)
    self.state.sent = true
  end
  self.adapter:abort(self, send_body and true)
  return self
end

return Call
