---@class bwf.uri-template: table
---@field is_static boolean
---@field pattern string
---@field path string
---@field params string[]

local template = {}

template.template_pattern = '([^/#?]+)'
template.param_pattern = '%b{}'

--- Normalize a URI string by applying a list of structural rules.
---  - Remove redundant slashes.
---  - Strip redundant whitespaces.
---  - Ensure a leading slash, and remove trailing slash.
---@param uri string
---@return string
---@nodiscard
function template.normalize(uri)
  assert(type(uri) == 'string', 'bad argument #1 to normalize (expected string)')
  local normalized = uri
  normalized = normalized:gsub('^%s+', ''):gsub('%s+$', '')
  normalized = ('/' .. normalized):gsub('[/]+', '/')
  if #normalized > 1 and normalized:sub(-1) == '/' then
    normalized = normalized:sub(1, -2)
  end
  return normalized
end
--[[
assert(template.normalize('') == '/')
assert(template.normalize('/  ') == '/')
assert(template.normalize('/  ') == '/')
assert(template.normalize(' //  ') == '/')
assert(template.normalize('///') == '/')
assert(template.normalize('/foo/bar/') == '/foo/bar')
assert(template.normalize('foo/bar') == '/foo/bar')
assert(template.normalize('foo//bar') == '/foo/bar')
assert(template.normalize('foo///bar//') == '/foo/bar')
assert(template.normalize('/foo/bar') == '/foo/bar')
]]

--- A simple URI join.
---@param ... string
---@return string
---@nodiscard
function template.join(...)
  local parts = { ... } --[[@as string[] ]]
  local segments = {}
  for _, part in ipairs(parts) do
    part = template.normalize(part)
    table.insert(segments, part)
  end
  return template.normalize(table.concat(segments, '/'))
end
--[[
assert(template.join('') == '/')
assert(template.join('/') == '/')
assert(template.join('/', '/', '//') == '/')
assert(template.join('//', '///', '//') == '/')
assert(template.join('a/b', 'c') == '/a/b/c')
assert(template.join('a', 'b/', '/c') == '/a/b/c')
assert(template.join('a', ' /b/', '/c/') == '/a/b/c')
assert(template.join('//a/', '/b/', '/c//') == '/a/b/c')
assert(template.join('a/', '', ' b ', 'c') == '/a/b/c')
--]]

--- Returns whether a template string does not define a parameter.
---
--- E.x.
--- ```lua
--- template.isStatic("/foo/bar/") --> true.
--- template.isStatic("/foo/{bar}/") --> false.
--- ````
---@param str string
---@return boolean
---@nodiscard
function template.isStatic(str)
  return str:match('%p{}') ~= nil
end

--- Taken from Penlight; escapes a string to be string.match-safe
local function escape(s)
  return (s:gsub('[%-%.%+%[%]%(%)%$%^%%%?%*]', '%%%1'))
end

--- Given a dynamic template string, return a Lua pattern able to match this template.
--- Note that the given string must not contain more than the path, so no query, hash, etc.
---@param str string
---@return string
---@nodiscard
function template.compileTemplate(str)
  local pattern = escape(str):gsub(template.param_pattern, template.template_pattern)
  return '^' .. pattern .. '$'
end
--[[
assert(template.compileTemplate('/foo/{bar}') == '^/foo/([^/#?]+)$')
assert(template.compileTemplate('/foo/{bar}/{a}') == '^/foo/([^/#?]+)/([^/#?]+)$')
assert(template.compileTemplate('/foo/{bar}/{a}/b') == '^/foo/([^/#?]+)/([^/#?]+)/b$')
assert(template.compileTemplate('/foo/{bar}/a-{b}') == '^/foo/([^/#?]+)/a%-([^/#?]+)$')
]]

--- Given a template path string, return an array of the parameters in the order they show in.
---
--- E.x.
--- ```lua
--- template.parseParams("/foo/{bar}/{id}") --> { "bar", "id" }
--- ```
---@param str string
---@return string[]
---@nodiscard
function template.parseParams(str)
  local params = {}
  for name in string.gmatch(str, template.param_pattern) do
    table.insert(params, name:sub(2, -2))
  end
  return params
end
-- p(template.parseParams("/foo/{bar}/{id}"))
-- p(template.parseParams("/foo/{bar}/prefix-{id}"))

---@param str string
---@return bwf.uri-template
---@nodiscard
function template.parseTemplate(str)
  if template.isStatic(str) then
    return {
      is_static = true,
      pattern = '^' .. str .. '$',
      path = str, -- TODO: might want to do template.sanitize to remove query/hash
      params = {},
    }
  end
  return {
    is_static = false,
    pattern = template.compileTemplate(str),
    path = str,
    params = template.parseParams(str),
  }
end

return template
