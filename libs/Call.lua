local core = require('core')
local json = require('json')

---@class bwf.Call: luvit.core.Object
---@field new fun(self: self, app: bwf.App, adapter: bwf.Adapter, backend_stat: table)
---@field app bwf.App
---@field adapter bwf.Adapter
---@field req table
---@field headers table
---@field body string
---@field keepAlive boolean
---@field state {sent: boolean, aborted: boolean, _backend: table} | table
---@field storage table # A plain Lua table used to store various data related to the Call, useful for interceptors.
local Call = core.Object:extend()

-- TODO: redesign Call.body to be a buffer instead of a string

-- TODO: (important) add a way to access parameters, queries and other parts of the request

-- TODO: nice URL parsing

-- TODO: investigate adding a Call._interceptors_stack for logging every interceptor that
-- this Call object has gone through

-- TODO: might want a Call.store or similar data structure for holding data between hooks

-- TODO: a way to "abort" a call, whatever abort should mean

function Call:initialize(app, adapter, backend_state)
  self.app = app
  self.adapter = adapter
  -- TODO: make sure states are properly updated
  self.state = {
    sent = false,
    aborted = false,
    _backend = backend_state,
  }

  -- TODO MAIN 3: use the Adapter methods to build up the states instead of depending on backend_state

  -- TODO: abstract this properly
  self.req = setmetatable({}, {
    __index = backend_state.req,
    __newindex = function()
      return error('Illegal operation: Call.req is read-only')
    end,
  })
  self.headers = backend_state.res.headers
  self.keepAlive = backend_state.res.keepAlive
  self.code = 404
  self.body = 'Not found'
end

---@param name string
---@param value any
---@return boolean? success, string? error_message
function Call:setHeader(name, value)
  -- TODO: when abstraction is done, make sure case-sensitivity is dealt with here
  if value == nil then
    self.headers[name] = nil
  else
    self.headers[name] = tostring(value)
  end
  return true
end

---@param name string
---@return string?
---@nodiscard
function Call:getHeader(name)
  return self.headers[name]
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
function Call:redirect(url, status)
  self:setHeader('Location', url)
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
