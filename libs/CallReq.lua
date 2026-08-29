local core = require('core')
local mimetype = require('mimetype')
local querystring = require('queryparse')
local uri = require('uri')

---@class bwf.CallReq: luvit.core.Object
---@field new fun(self: self, call: bwf.Call, adapter: bwf.Adapter)
---@field method string
---@field headers { [string]: string|string[] }
---@field path { raw: string, pathname: string, querystring: string?, query: table? }
---@field address { ip: string, port: integer, family: string }
---@field version string
---@field type { type: string, parameters: {[string]: string} }?
---@field protocol 'http' | 'https'
local CallReq = core.Object:extend()

local function parsePath(path)
  local parsed = assert(uri.decode(path))

  local query
  if parsed.query then
    query = querystring.decode(parsed.query)
  end

  return {
    raw = path,
    pathname = parsed.path,
    querystring = parsed.query,
    query = query,
  }
end

---@param adapter bwf.Adapter
function CallReq:initialize(call, adapter)
  self.method = adapter:getMethod(call)
  self.headers = adapter:getHeaders(call) -- TODO: make headers table read-only?
  self.path = parsePath(adapter:getPath(call))
  self.address = adapter:getRemoteAddress(call)
  self.version = adapter:getVersion(call)

  -- TODO: support for X-Forward-For / X-Forward-Proto / X-Forward-Host
  -- and/or the modern Forwarded header defined in rfc7239
  self.type = mimetype:match(self:getHeader('content-type', '') --[[@as string]])
  self.protocol = adapter:isSecure(call) and 'https' or 'http'
  -- TODO: maybe add .host too?
end

--- Return a request header, if set.
--- If the requested header is not set, `default_value` is returned instead, which defaults to `nil`.
---@param name string
---@param default_value any
---@return string|string[]|nil
---@nodiscard
function CallReq:getHeader(name, default_value)
  return self.headers[name] or default_value
end

--- Returns whether a header is set or not in the response.
---@param name string
---@return boolean
---@nodiscard
function CallReq:hasHeader(name)
  return not not self.headers[name]
end

--- Return a request query, if provided.
--- If the requested query has not been provided `default_value` is returned instead, which defaults to `nil`.
--- If multiple values were provided an array of all values will be returned.
---@param name string
---@param default_value any
---@return string|string[]|nil
---@nodiscard
function CallReq:getQuery(name, default_value)
  return self.path.query[name] or default_value
end

--- Returns whether a query has been provided in the request or not.
---@param name string
---@return boolean
---@nodiscard
function CallReq:hasQuery(name)
  return not not self.path.query[name]
end

return CallReq
