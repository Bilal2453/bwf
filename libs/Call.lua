local CallReq = require('CallReq')
local core = require('core')
local json = require('json')

---@class bwf.Call: luvit.core.Object
---@field new fun(self: self, app: bwf.App, adapter: bwf.Adapter, backend_stat: table)
---@field app bwf.App
---@field adapter bwf.Adapter
---@field req table
---@field headers {[string]: string | string[] | nil}
---@field body string
---@field state {sent: boolean, aborted: boolean, _backend: table} | table
---@field storage table # A plain Lua table used to store various data related to the Call, useful for interceptors.
local Call = core.Object:extend()

-- TODO: redesign Call.body to be a buffer instead of a string

-- TODO: (important) add a way to access parameters

-- TODO: investigate adding a Call._interceptors_stack for logging every interceptor that
-- this Call object has gone through

-- TODO: might want a Call.store or similar data structure for holding data between hooks

-- TODO: a way to "abort" a call, whatever abort should mean

---@param adapter bwf.Adapter
function Call:initialize(app, adapter, backend_state)
  self.app = app
  self.adapter = adapter
  -- TODO: make sure states are properly updated
  self.state = {
    sent = false,
    aborted = false,
    _backend = backend_state,
  }
  self.storage = {} -- TODO: maybe add more restrictions or abstractions?

  self.req = CallReq:new(self, adapter)

  self.headers = {}
  self.code = 404
  self.body = 'Not found'
end

--- Set a response header. The name is case-insensitive. If the value is an array the header will be set multiple times for each value.
--- If the value is `nil` the header will be removed, similar to calling `Call:removeHeader(name)`.
---@param name string
---@param value string | string[]
---@return boolean success
function Call:setHeader(name, value)
  name = string.lower(name)
  if value == nil then
    self.headers[name] = nil
  elseif type(value) == 'table' then
    -- TODO: handle exceptions like Set-Cookies when serializing
    self.headers[name] = value
  else
    self.headers[name] = tostring(value)
  end
  return true
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
---@return string|string[]|nil
function Call:removeHeader(name)
  self.headers[name] = nil
end

--- Similar to `Call:setHeader` but if a header is already set it will add an additional field instead of overriding the old one.
---@param name string
---@param value string | string[]
function Call:appendHeader(name, value)
  if not value then
    return
  end
  name = string.lower(name)

  -- if no old value then we can just use setHeader
  local old_value = self.headers[name]
  if not old_value then
    return self:setHeader(name, value)
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
end

---@param status integer
---@return boolean? success, string? error_message
function Call:setStatus(status)
  self.code = tonumber(status)
  return true
end

---@param data table
---@param status integer?
---@return boolean? success, string? error_message
function Call:json(data, status)
  if type(data) ~= 'table' then
    return error('bad argument #2 to Call.json (expected table, got ' .. type(data) .. ')')
  end
  local enc, err = json.encode(data)
  if not enc then
    return nil, err
  end
  self.body = enc --[[@as string]]
  self:setHeader('Content-Type', 'application/json')
  self:setStatus(status or 200)
  return true
end

---@param text string
---@param status integer?
---@return boolean? success, string? error_message
function Call:text(text, status, ...)
  if select('#', ...) > 0 then
    text = string.format(text, ...)
  end
  self.body = text
  self:setHeader('Content-Type', 'text/plain')
  self:setStatus(status or 200)
  return true
end

---@param html string
---@param status integer?
---@return boolean? success, string? error_message
function Call:html(html, status)
  self.body = html
  self:setHeader('Content-Type', 'text/html')
  self:setStatus(status or 200)
  return true
end

---@param status integer? # Default: `301`.
---@return boolean? success, string? error_message
function Call:redirect(location, status)
  self:setHeader('Location', url.percentEncode(location))
  self:setStatus(status or 301)
  return true
end

-- TODO: investigate the API design of the following ideas
function Call:file() end
function Call:render(template, data, status) end
function Call:setCookie(name, value, options) end
function Call:removeCookie(name) end

---@param error luvit.core.Error
---@param status integer?
function Call:abort(error, status)
  self.state.aborted = true -- TODO: we might want to set this to the error object instead
  self:setStatus(status or 400)
  return error(error)
end

return Call
