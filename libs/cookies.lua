local uri = require('uri')
local percentDecode, percentEncode = uri.percentDecode, uri.percentEncode

local function parseCookies(header)
  local result = {}
  if not header then
    return result
  end
  -- TODO: fix parsing empty values (e.x. "session=;") and quoted values (e.x. 'session="...";')
  for name, value in header:gmatch('%s*([^=;]+)=([^;]+);?%s*') do
    result[name] = percentDecode(value)
  end
  return result
end

local set_cookie_attrs = {
  domain = 'Domain',
  expires = 'Expires',
  httpOnly = 'HttpOnly',
  maxAge = 'Max-Age',
  partitioned = 'Partitioned',
  path = 'Path',
  secure = 'Secure',
  sameSite = 'SameSite',
}

---@alias bwf.Cookies.attributes {
---   domain?: string,
---   expires?: string,
---   httpOnly?: boolean,
---   maxAge?: number,
---   partitioned?: boolean,
---   path?: string,
---   secure?: boolean,
---   sameSite?: bwf.Cookies.attributes.sameSite,
--- }
---@alias bwf.Cookies.attributes.sameSite 'Strict' | 'Lax' | 'None'

---@param name string
---@param value string | number
---@param attributes? bwf.Cookies.attributes
---@return string
---@nodiscard
local function formatCookie(name, value, attributes)
  value = percentEncode(tostring(value))
  local encoded_params = {}
  if attributes then
    for k, v in pairs(attributes) do
      local attr_name = assert(set_cookie_attrs[k], 'Invalid cookie attribute ' .. tostring(k))
      if type(v) ~= 'boolean' then
        table.insert(encoded_params, '; ')
        table.insert(encoded_params, attr_name .. '=' .. tostring(v))
      elseif v then
        table.insert(encoded_params, '; ')
        table.insert(encoded_params, attr_name)
      end
    end
  end
  return name .. '=' .. value .. table.concat(encoded_params)
end

return {
  parseCookies = parseCookies,
  formatCookie = formatCookie,
}
