-- Copyright 2026 Truemedian
-- See https://github.com/truemedian/gud/blob/something-new/deps/querystring.lua
-- modified: flattened extension dependency

local uri = require('uri')

local querystring = {}

--- Returns a new sequence containing the keys of `tbl`.
--- @generic K, V
--- @param tbl table<K, V>
--- @return K[]
local function keys(tbl)
  local rtn, n = {}, 0

  for k in pairs(tbl) do
    n = n + 1
    rtn[n] = k
  end

  return rtn
end

local function spairs(tbl, cmp)
  local keys = keys(tbl)
  table.sort(keys, cmp)

  local i = 0
  return function()
    i = i + 1
    local key = keys[i]
    if key ~= nil then
      return key, tbl[key]
    end
  end
end

--- Returns an iterator that splits `str` by `delim`. If `plain` is true, `delim` is interpreted as a plain string
--- instead of a pattern.
--- @param str string
--- @param delim string
--- @param plain? boolean
--- @return fun(): string|nil, integer|nil, integer|nil iterator
local function split(str, delim, plain)
  local i = 1
  return function()
    local j, k = string.find(str, delim, i, plain)
    if j then
      local start, finish = i, j - 1

      local part = str:sub(start, finish)
      i = k + 1

      return part, start, i
    elseif i <= #str then
      local start = i

      local part = str:sub(start)
      i = #str + 1

      return part, start, i
    end
  end
end

--- @param str string
--- @param space string|nil
--- @return table
function querystring.decode(str, space)
  local result = {}
  for pair in split(str, '&', true) do
    local key, value = pair:match('([^=]*)=?(.*)')
    if key then
      key = uri.percentDecode(key, space)
      value = uri.percentDecode(value, space)

      if result[key] then
        if type(result[key]) == 'table' then
          table.insert(result[key], value)
        else
          result[key] = { result[key], value }
        end
      else
        result[key] = value
      end
    end
  end

  return result
end

--- @param tbl table
--- @param space string|nil
--- @return string
function querystring.encode(tbl, space)
  local parts, n = {}, 0
  for key, value in spairs(tbl) do
    key = uri.percentEncode(tostring(key), space)

    if type(value) == 'table' then
      for _, v in ipairs(value) do
        n = n + 1
        parts[n] = key .. '=' .. uri.percentEncode(tostring(v), space)
      end
    else
      n = n + 1
      parts[n] = key .. '=' .. uri.percentEncode(tostring(value), space)
    end
  end

  return table.concat(parts, '&', 1, n)
end

return querystring
