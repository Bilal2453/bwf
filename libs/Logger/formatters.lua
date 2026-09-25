local http_status = require('http_status')
local json_encode = require('json').encode

--- Extract and sort the keys of the given table while at the same time scanning
--- the structure for duplicated table references to be deduplicated recursively.
---
--- This is mainly intended for the pretty formatter, to make sure entries are
--- always displayed in order, and that already printed tables aren't printed again.
---@param tbl table # the table value to scan and sort
---@param depth integer # how deep to scan the table
---@param state { keys: { [table]: string[] }, counts: { [table]: integer } } # The results of all calls
---@param skip {[string]: true}? # Keys to skip at the first level of `tbl`
local function scanAndSort(tbl, depth, state, skip)
  if depth <= 0 then
    return
  end
  state.counts[tbl] = (state.counts[tbl] or 0) + 1
  if state.counts[tbl] > 1 then
    return
  end

  local keys = {}
  for k, v in pairs(tbl) do
    if not (skip and skip[k]) then
      table.insert(keys, k)
      if type(v) == 'table' then
        scanAndSort(v, depth - 1, state, nil)
      end
    end
  end

  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
      return ta < tb
    end
    return a < b
  end)

  state.keys[tbl] = keys
end

local wrapped_types = { ['function'] = true, userdata = true, thread = true }

--- Given a table key, serialize it to a string representation while respecting
--- how arrays are represented when no holes are present.
---@param k any # The key to serialize
---@param hole_index integer | boolean # Used for detecting array holes using last index
---@return string?
---@return integer | boolean
local function encodeKey(k, hole_index)
  local kt, kv = type(k), tostring(k)
  if kt == 'number' then
    if hole_index == true or k ~= (hole_index + 1) then
      hole_index = true
      return '[' .. k .. ']', hole_index
    else
      hole_index = k
      return nil, hole_index -- no key
    end
  elseif wrapped_types[kt] or kt == 'table' then
    return '<' .. kv .. '>', hole_index
  end
  -- TODO: should it wrap strings in brackets if they contain illegal names?
  return kv, hole_index
end

--- Given a table value, serialize it to a string representation.
--- This offers printing a reference to already printed tables,
--- sorting, skipping specific keys, proper arrays in mixed tables, etc.
---@param value any # The value to serialize
---@param options { seen: {keys: table, refs: table, counts: table, id: integer}, depth: integer, level: integer } # states and options required for recursion
---@return string
local function encodeValue(value, options)
  local vt = type(value)
  local ref = options.seen.refs[value]

  -- early return for non-table values (they are simple enough)
  if vt == 'string' then
    return string.format('%q', value)
  elseif vt ~= 'table' then
    return wrapped_types[vt] and ('<' .. tostring(value) .. '>') or tostring(value)
  end
  -- early return for already references and serialized tables
  if ref then
    return '<table ' .. ref .. '>'
  end

  -- at this point the value is a table seen for the first time during all passes
  -- so we need serialize it and properly set it up

  -- if the table is seen more than once assign a unique reference for it
  if options.seen.counts[value] and options.seen.counts[value] > 1 then
    options.seen.id = options.seen.id + 1
    ref = options.seen.id
    options.seen.refs[value] = ref
  end

  -- if we've nested into the structure too deep return a simple truncated representation and skip the serialization
  if options.level > options.depth then
    return '{ ... }'
  end

  local buf = {}
  local keys = options.seen.keys[value] or {}
  -- hole_index ensures proper detection of array holes
  -- by remembering the last index the encodeValue was called with
  ---@type integer | boolean
  local hole_index = 0

  -- we are entering a new level of recursion, increase the level
  options.level = options.level + 1
  -- encode the table keys/values
  for _, k in ipairs(keys) do
    local kv, vs
    kv, hole_index = encodeKey(k, hole_index)
    vs = encodeValue(value[k], options)

    if not kv then
      -- this is an array, so no key
      table.insert(buf, vs)
    else
      table.insert(buf, kv .. ' = ' .. vs)
    end
  end

  options.level = options.level - 1

  local res = #buf == 0 and '{}' or '{ ' .. table.concat(buf, ', ') .. ' }'
  -- if this table has been assigned a reference, prepend it
  if ref then
    res = '<' .. ref .. '>' .. res
  end
  return res
end

local formats = {
  --- general formatters accepting a message
  general = {},
  --- specific formatters for logger.http
  http = {},

  --- Short 3-letter labels for error levels
  labels = {
    trace = 'TRC',
    debug = 'DBG',
    info = 'INF',
    warn = 'WRN',
    error = 'ERR',
    fatal = 'FTL',
  },

  --- The styles used throughout the formatters
  --- note that we only use 16-bit ANSI colors to stay compatible with custom terminal pallets, 24-bit RGB values break that
  theme = {
    trace = '90',
    debug = '36',
    info = '34',
    warn = '33;1',
    error = '31;1',
    fatal = '35;1',

    time = '90', -- dim gray for timestamp
    scope = '37', -- gray for [scope]
    message = '0', -- normal
    context = '90', -- dim gray for { key = "val" }

    path = '0',
    method = '1', -- bold for GET/POST
    status_1xx = '90', -- green
    status_2xx = '32', -- green
    status_3xx = '36', -- cyan
    status_4xx = '33', -- yellow
    status_5xx = '31', -- red

    duration_ok = '90', -- dim gray
    duration_warn = '33', -- yellow
    duration_slow = '31;1', -- bold red
  },
}

--- Wrap `text` with an ANSI style code.
---@param text string
---@param style string?
---@return string
function formats.colorize(text, style)
  if not style or style == '0' then
    return text
  end
  return '\27[' .. style .. 'm' .. text .. '\27[0m'
end

local t = formats.theme
local c = formats.colorize

--- Returns a readable string of the current date and time with millisecond precision.
--- Example format output: `"2026-09-21 22:39:04.520"`.
---@param sec number
---@param ms number
---@return string
function formats.readableDate(sec, ms)
  return string.format('%s.%03d', os.date('%Y-%m-%d %H:%M:%S', sec), ms)
end

--- Return a ISO-8601 formatted datetime.
--- Example format output: `"2026-09-21T11:50:16.123Z"`.
---@param sec number
---@param ms number
function formats.isoDate(sec, ms)
  return string.format('%s.%03dZ', os.date('!%Y-%m-%dT%H:%M:%S', sec), ms)
end

--- Given a duration number (in nanoseconds!) return a human readable string
--- with properly scaled time units
---@param duration number
---@return string
function formats.readableDuration(duration)
  local duration_fmt
  if duration < 1e6 then
    duration_fmt = string.format('%.2fµs', duration / 1e3)
  elseif duration < 1e9 then
    duration_fmt = string.format('%.2fms', duration / 1e6)
  else
    duration_fmt = string.format('%.2fs', duration / 1e9)
  end
  return duration_fmt
end

-- A 3-phase simple table serializer
function formats.serializeTable(tbl, options)
  options = options or {}
  options.skip = options.skip or {} -- a list of keys to ignore
  options.level = options.level or 1 -- the current tail call level
  options.depth = options.depth or 3 -- how deep to recurse into tables
  options.seen = { counts = {}, refs = {}, keys = {}, id = 0 } -- saves already seen tables and their states

  scanAndSort(tbl, options.depth, options.seen, options.skip)
  local res = encodeValue(tbl, options)
  if res == '{}' then
    return ''
  end
  return res
end

---@param logger bwf.Logger # the logger instance initiating the formatting
---@param sink bwf.Logger.sink # the target sink (for color mode detection)
---@param level bwf.Logger.level_values | number # the logging level
---@param message string # the logging message
---@param time_sec integer # unix timestamp for the logging time
---@param time_ms number # an added millisecond precision for the timestamp
---@return string
function formats.general.pretty(logger, sink, level, message, time_sec, time_ms)
  local level_name = assert(logger.level_names[level], 'bad argument #3 to pretty (expected a valid level value)')
  local context = logger.options.context --[[@as table]]
  local scope = context.scope

  local date = formats.readableDate(time_sec, time_ms)
  local scope_str = (scope and ' [' .. scope .. '] ' or ' ')
  local context_str = formats.serializeTable(context, { skip = { scope = true } })
  context_str = context_str ~= '' and (' ' .. context_str) or context_str

  if sink.color_mode ~= 0 then
    return c(date, t.time)
      .. ' '
      .. c(formats.labels[level_name], t[level_name])
      .. c(scope_str, t.scope)
      .. c(message, t.message)
      .. c(context_str, t.context)
      .. '\n'
  else
    return date .. ' ' .. formats.labels[level_name] .. scope_str .. message .. context_str .. '\n'
  end
end

---@param logger bwf.Logger
---@param sink bwf.Logger.sink
---@param level bwf.Logger.level_values | number
---@param message string
---@param time_sec integer
---@param time_ms number
---@return string
function formats.general.json(logger, sink, level, message, time_sec, time_ms)
  local entry = {}
  local context = logger.options.context --[[@as table]]

  for k, v in pairs(context) do
    entry[k] = v
  end

  entry.time = formats.isoDate(time_sec, time_ms)
  entry.level = assert(logger.level_names[level], 'bad argument #3 to json (expected a valid level value)')
  entry.scope = context.scope
  entry.message = message

  local encoded, err = json_encode(entry)
  if not encoded then
    error(err)
  end
  return encoded .. '\n' --[[@as string]]
end

--- <date> <label> [http] <http method> <path> <response code and description> (<duration>)
---@param sink bwf.Logger.sink
---@param level integer
---@param call bwf.Call
---@param duration number
---@param time_sec integer
---@param time_ms number
function formats.http.pretty(logger, sink, level, call, duration, time_sec, time_ms)
  local date = formats.readableDate(time_sec, time_ms)
  local level_name = assert(logger.level_names[level], 'bad argument #3 to pretty (expected a valid level value)')
  local method_detail = http_status[call.code] or 'Unknown'
  local duration_fmt = '(' .. formats.readableDuration(duration) .. ')'

  if sink.color_mode ~= 0 then
    local level_color
    if call.code >= 500 then
      level_color = t.status_5xx
    elseif call.code >= 400 then
      level_color = t.status_4xx
    elseif call.code >= 300 then
      level_color = t.status_3xx
    elseif call.code >= 200 then
      level_color = t.status_2xx
    elseif call.code >= 100 then
      level_color = t.status_1xx
    end
    local duration_color = t.duration_warn
    if duration >= 500e6 then
      duration_color = t.duration_slow
    elseif duration >= 100e6 then
      duration_color = t.duration_warn
    else
      duration_color = t.duration_ok
    end

    return c(date, t.time) -- <date>
      .. ' '
      .. c(formats.labels[level_name], t[level_name]) -- <label>
      .. ' '
      .. c('[http]', t.scope) -- <scope>
      .. ' '
      .. c(call.req.method, t.method) -- <http method>
      .. ' '
      .. c(call.req.path.raw, t.path) -- <path>
      .. ' '
      .. c(call.code .. ' ' .. method_detail, level_color) -- <response code and description>
      .. ' '
      .. c(duration_fmt, duration_color) -- <duration>
      .. '\n'
  else
    return date
      .. ' '
      .. formats.labels[level_name]
      .. ' '
      .. '[http]'
      .. ' '
      .. call.req.method
      .. ' '
      .. call.req.path.raw
      .. ' '
      .. (call.code .. ' ' .. method_detail)
      .. ' '
      .. duration_fmt
      .. '\n'
  end
end

---@param logger bwf.Logger
---@param sink bwf.Logger.sink
---@param level bwf.Logger.level_values | number
---@param call bwf.Call
---@param duration number
---@param time_sec integer
---@param time_ms number
---@return string
function formats.http.json(logger, sink, level, call, duration, time_sec, time_ms)
  local entry = {}
  local context = logger.options.context --[[@as table]]

  for k, v in pairs(context) do
    entry[k] = v
  end

  entry.time = formats.isoDate(time_sec, time_ms)
  entry.level = assert(logger.level_names[level], 'bad argument #3 to json (expected a valid level value)')
  entry.scope = 'http'
  entry.http = {
    method = call.req.method,
    path = call.req.path.raw,
    status = call.code,
    duration = duration / 1e6,
    ip = call.req.address.ip,
  }

  local encoded, err = json_encode(entry)
  if not encoded then
    error(err)
  end
  return encoded .. '\n' --[[@as string]]
end

return formats
