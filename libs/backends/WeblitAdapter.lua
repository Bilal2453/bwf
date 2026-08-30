local Adapter = require('./Adapter')
local Call = require('Call')
local core = require('core')
local resolve = require('./resolve')

local weblit_server = require('weblit-server')

---@class bwf.WeblitAdapter: bwf.Adapter
---@field server uv_tcp_t?
local WeblitAdapter = Adapter:extend()

function WeblitAdapter:start()
  if self.server then
    return nil, 'Server is already started'
  end

  ---@type weblit.server
  local server = weblit_server.newServer(function(...)
    return self:handler(...)
  end)
  server.bind(self.app.interface)
  server.start()

  return true
end

function WeblitAdapter:stop()
  if not self.server then
    return nil, 'Server is already closed'
  end
  self.server:close(function()
    self.server = nil
  end)
  return true
end

function WeblitAdapter:adapt(req, res)
  return {
    name = 'weblit',
    req = req,
    res = res,
  }
end

function WeblitAdapter:handler(req, res)
  local backend_state = self:adapt(req, res)
  local call = Call:new(self.app, self, backend_state)
  self.app:_dispatch(call)
end

---@param call bwf.Call
function WeblitAdapter:flush(call)
  -- the code might look slightly weird, because I can't flush the socket directly
  -- instead I use the weblit server flushing mechanism which starts working once control is returned
  -- here I prepare the response structure returning control

  -- sanity check: make sure the call object is in the right context
  if not core.instanceof(call, Call) or call.state._backend.name ~= 'weblit' then
    return nil, 'Invalid Call object'
  end
  local res = call.state._backend.res --[[@as weblit.res]]
  -- write the response code and headers
  res.code = call.code
  res.headers = resolve.headersToPairs(call.headers)
  -- serialize the body if needed
  local mode, serialize = call:_finalize()
  if not mode then
    error('Failed to serialize the body: ' .. tostring(serialize))
  end
  -- flush the body
  if mode == 'app' then
    -- write the serialized body
    res.body = serialize --[[@as string]]
  else
    -- let the adapter serializer flush the body
    serialize(call)
  end
  return true
end

--- The start of request related methods

--- The HTTP method as provided by the user agent.
--- No pre-processing is allowed to take effect on this string (e.x. lowercasing/stripping).
---@param call bwf.Call
---@return string
---@nodiscard
function WeblitAdapter:getMethod(call)
  return call.state._backend.req.method
end
--- The full unparsed untread HTTP path as provided by the user agent.
---@param call bwf.Call
---@return string
---@nodiscard
function WeblitAdapter:getPath(call)
  return call.state._backend.req.path
end
--- The HTTP protocol version used for this request.
---@param call bwf.Call
---@return string
---@nodiscard
function WeblitAdapter:getVersion(call)
  return call.state._backend.req.version
end
--- The remote IP address as resolved by the backend. This is the raw remote socket IP, not necessarily the same as the real remote IP.
---@param call bwf.Call
---@return { ip: string, port: integer, family: string }
---@nodiscard
function WeblitAdapter:getRemoteAddress(call)
  return call.state._backend.req.socket:getpeername()
end
--- The request headers as a map of the header name to the value, if the header is provided multiple times
--- the value must be an array of the provided values. The header name is always lower-case. All values must be strings.
---@param call bwf.Call
---@return {[string]: string | string[]}
---@nodiscard
function WeblitAdapter:getHeaders(call)
  local headers = {}
  for _, header in ipairs(call.state._backend.req.headers) do
    ---@cast header {[1]: string, [2]: string}
    local name, value = string.lower(header[1]), header[2]
    if headers[name] then
      if type(headers[name]) == 'table' then
        table.insert(headers[name], value)
      else
        headers[name] = { headers[name], value }
      end
    else
      headers[name] = value
    end
  end
  return headers
end
--- Return whether this Call was sent over a secure network (TLS encrypted socket) or not.
---@param call bwf.Call
---@return boolean
---@nodiscard
function WeblitAdapter:isSecure(call)
  return call.state._backend.req.socket.tls or false
end
--- Return the full request payload as a Lua string.
---@param call bwf.Call
---@return string
---@nodiscard
function WeblitAdapter:readBodyAsString(call)
  return call.state._backend.req.body
end

return WeblitAdapter
