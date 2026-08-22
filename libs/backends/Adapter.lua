local core = require('core')

--- An abstract class representing a backend server in an agnostic way.
--- 
--- Flow:
---   Adapter:start()
---   -> (on request)
---   -> Adapter:handler(...)
---   -> (Call instance is created)
--- 
--- General notes:
---   - Any async operation must be done in blocking style using coroutines.
---   - To offer maximum flexibility, request body is never directly exposed.
---   - Read operations return full results unless indicated otherwise for chunked data.
--- 
--- This is an abstract class, a direct instance of this class must not exist.
---@class bwf.Adapter: luvit.core.Object
---@field app bwf.App
local Adapter = core.Object:extend()

function Adapter:initialize(app)
  self.app = assert(app)
end

--- Start up the backend server, this is supposed to start listening on the assigned port
--- and accept incoming requests.
function Adapter:start()
  return nil, 'NYI'
end

--- Stops the backend server, this is supposed to stop listening on the assigned port
--- and stop accepting any new requests. Write stream must not be shutdown until all requests are done and responses has been flushed.
function Adapter:stop()
  return nil, 'NYI'
end

--- Handle an incoming request and tell the App instance about it after it has been adapted to the standard structures.
function Adapter:handler(...)
  return nil, 'NYI'
end

--- Flush a call object, sending any unset responses and preparing for the write stream to be shutdown (if required).
---@param call bwf.Call
---@return boolean? success, string? error_message
function Adapter:flush(call)
  return nil, 'NYI'
end

--- Given the backend states build up the adapter's states preparing for Call creation.
--- The exact structure returned is private to the adapter class and is free to store whatever it needs to.
function Adapter:adapt(...)
  return nil, 'NYI'
end

--- The start of request related methods

--- The HTTP method as provided by the user agent.
--- No pre-processing is allowed to take effect on this string (e.x. lowercasing/stripping).
---@param call bwf.Call
---@return string
---@nodiscard
function Adapter:getMethod(call)
  error('NYI')
end
--- The full unparsed untread HTTP path as provided by the user agent.
---@param call bwf.Call
---@return string
---@nodiscard
function Adapter:getPath(call)
  error('NYI')
end
--- The HTTP protocol version used for this request.
---@param call bwf.Call
---@return string
---@nodiscard
function Adapter:getVersion(call)
  error('NYI')
end
--- The remote IP address as resolved by the backend. This is the raw remote socket IP, not necessarily the same as the real remote IP.
---@param call bwf.Call
---@return { ip: string, port: integer, family: string }
---@nodiscard
function Adapter:getRemoteAddress(call)
  error('NYI')
end
--- The request headers as a map of the header name to the value, if the header is provided multiple times
--- the value must be an array of the provided values. All values must be strings.
---@param call bwf.Call
---@return {[string]: string | string[]}
---@nodiscard
function Adapter:getHeaders(call)
  error('NYI')
end
--- Return the full request payload as a Lua string.
---@param call bwf.Call
---@return string
---@nodiscard
function Adapter:readBodyAsString(call)
  error('NYI')
end
-- TODO other types of readBody methods

--- Represents an HTTP request, while abstracting backend details.
---@class bwf.Adapter.Adapted: table
--- The HTTP method as provided by the user agent.
--- No pre-processing is allowed to take effect on this string (e.x. lowercasing/stripping).
---@field method bwf.alias.http_method
--- The full unparsed untread URL as provided by the user agent.
---@field url string
--- The HTTP protocol version used for this request.
---@field version string
--- Whether this is an HTTP or an HTTPS request.
---@field protocol 'http' | 'https'
--- The remote IP address as resolved by the backend. This is the raw remote socket IP, not necessarily the same as the real remote IP.
---@field remote_ip string
--- The request headers as a map of the header name to the value, if the header is provided multiple times
--- the value must be an array of the provided values. All values must be strings.
---@field headers {[string]: string | string[]}
--- The payload of the HTTP request. 


return Adapter
