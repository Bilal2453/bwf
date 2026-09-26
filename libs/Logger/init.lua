local core = require('core')
local formats = require('./formatters')
local path = require('path') --[[@as bwf.path]]

local _, luv = pcall(require, 'uv')
if not luv then
  luv = require('luv')
end

---@alias bwf.Logger.formats 'pretty' | 'json' | string
---@alias bwf.Logger.level 'trace' | 'debug' | 'info' | 'warn' | 'error' | 'fatal' | integer
---@alias bwf.Logger.color_mode 0 | 16 | 24

---@class bwf.Logger.options: table
---@field format bwf.Logger.formats?
---@field level integer?
---@field context table?
---@field max_level integer?
---@field color_mode bwf.Logger.color_mode?

---@alias bwf.logger.sink.type 'stream' | 'file'

---@class bwf.Logger.sink: table
---@field type bwf.logger.sink.type
---@field close boolean
---@field level integer
---@field format bwf.Logger.formats
---@field handle table | file*
---@field max_level integer
---@field color_mode bwf.Logger.color_mode

---@class bwf.Logger: luvit.core.Object
---@field protected _min_used_level integer
---@field protected _handles table
---@field protected _closed boolean
---@field protected _formatters { general: { [string]: function }, [string]: any }
---@field parent bwf.Logger?
---@field context table
---@field options bwf.Logger.options
---@field sinks bwf.Logger.sink[]
---@field new fun(self: self, options?: bwf.Logger.options): bwf.Logger
local Logger = core.Object:extend()

---@enum (key) bwf.Logger.level_names
Logger.level_values = {
  trace = 1,
  debug = 2,
  info = 3,
  warn = 4,
  error = 5,
  fatal = 6,
}
---@enum (key) bwf.Logger.level_values
Logger.level_names = {
  [1] = 'trace',
  [2] = 'debug',
  [3] = 'info',
  [4] = 'warn',
  [5] = 'error',
  [6] = 'fatal',
}

Logger._resolvers = {
  level = function(level, default)
    local t = type(level)
    if t == 'string' and Logger.level_values[level] then
      return Logger.level_values[level]
    elseif t == 'number' and Logger.level_names[level] then
      return level
    elseif level == nil then
      return default
    else
      error('bad options.level (expected a valid level name or value)')
    end
  end,
  format = function(self, format, default)
    if format then
      if not self._formatters.general[format] then
        error('bad options.format (expected a valid format string)')
      end
      return format
    else
      return default
    end
  end,
  context = function(context, default)
    if context then
      if type(context) ~= 'table' then
        error('bad options.context (expected a table)')
      end
      return context
    else
      return default
    end
  end,
  color_mode = function(mode, default)
    if mode == false then
      return 0
    elseif mode == nil then
      return default
    end
    mode = tonumber(mode)
    if mode ~= 0 and mode ~= 16 and mode ~= 24 then
      error('bad options.color_mode (expected one of 0, 16 or 24)')
    end
    return mode
  end,
}

---@param options bwf.Logger.options?
---@return bwf.Logger.options
function Logger:_resolveOptions(options)
  options = options or {}
  assert(type(options) == 'table', 'bad argument #2 to Logger.new (expected table or nil)')
  local resolved_options = {
    level = self._resolvers.level(options.level, 3),
    format = self._resolvers.format(self, options.format, 'pretty'),
    context = self._resolvers.context(options.context, {}),
    max_level = self._resolvers.level(options.max_level),
    color_mode = self._resolvers.color_mode(options.color_mode, 24), -- TODO: auto-detect color mode
  }
  return resolved_options
end

function Logger:initialize(options)
  self._formatters = {}
  for k, v in pairs(formats) do
    self._formatters[k] = v
  end
  self.sinks = {}
  self._handles = {}
  self._closed = false
  self.options = self:_resolveOptions(options)
  self._min_used_level = self.options.level
end

--- Performs level comparison between a target level and a sink's level
--- to decide whether a log entry should be dispatched or not.
function Logger:_compareLevel(level, sink)
  if sink.max_level and level > sink.max_level then
    return false
  end
  return level >= sink.level
end

--- Adds a stream object as a sink downstream, where stream is a file-like interface.
--- A stream interface must implement `Stream:write(string_data)`, and optionally `stream:close()`.
---@param stream { write: fun(data: string), close?: function } | file*
---@param options? bwf.Logger.options | { close: boolean? }
---@return self
function Logger:addStream(stream, options)
  if not stream.write then
    error('bad argument #2 to Logger.addStream (expected a valid file* interface)')
  end
  if self._handles[stream] then
    error('provided stream is already added')
  end

  options = options or {}
  local level = self._resolvers.level(options.level, self.options.level)

  table.insert(self.sinks, {
    handle = stream,
    type = 'stream',
    close = options.close and true or false,
    level = level,
    format = self._resolvers.format(self, options.format, self.options.format),
    max_level = self._resolvers.level(options.max_level, self.options.max_level),
    color_mode = self._resolvers.color_mode(options.color_mode, self.options.color_mode),
  })
  self._handles[stream] = true
  if level < self._min_used_level then
    self._min_used_level = level
  end

  return self
end

--- Provides a pseudo file interface for luv file handles.
--- While at it, also ensures a file is only opened once.
function Logger:_openLog(file_path)
  local full_path = path.resolve(file_path)
  if self._handles[full_path] then
    error('provided file path is already added')
  end

  local handle, err_name, err_msg = luv.fs_open(full_path, 'a', 438)
  if not handle then
    error(err_name .. ': ' .. err_msg)
  end
  self._handles[full_path] = true

  return {
    fd = handle,
    write = function(struct, data)
      return luv.fs_write(struct.fd, data, -1)
    end,
    close = function(struct)
      return luv.fs_close(struct.fd)
    end,
  }
end

--- Adds a file as a sink downstream.
--- The file path must be a valid relative/absolute destination the data will be appended to without truncation.
---@param file string
---@param options? bwf.Logger.options
function Logger:addFile(file, options)
  assert(type(file) == 'string', 'bad argument #2 to Logger.addFile (expected string)')
  options = options or {}
  local handle = self:_openLog(file)
  local level = self._resolvers.level(options.level, self.options.level)
  local max_level = self._resolvers.level(options.max_level, self.options.max_level)
  if max_level and level > max_level then
    error('bad options.max_level (max_level cannot be lower than level)')
  end

  table.insert(self.sinks, {
    type = 'file',
    handle = handle,
    close = true,
    level = level,
    max_level = max_level,
    format = self._resolvers.format(self, options.format, self.options.format),
    color_mode = self._resolvers.color_mode(options.color_mode, 0),
  })
  if level < self._min_used_level then
    self._min_used_level = level --[[@as integer]]
  end

  return self
end

--- Writes a log payload to the specified sink.
---@param sink bwf.Logger.sink
---@param payload string
---@return boolean success, string? err_msg
function Logger:_dispatch(sink, payload)
  local success, err = pcall(sink.handle.write, sink.handle, payload)
  if not success then
    -- don't eat logs on write errors
    local msg =
      string.format('[Logger Error]: A write operation on a sink failed: "%s" when trying to log "%s"\n', err, payload)
    pcall(io.stderr.write, io.stderr, msg)
  end
  return success, err --[[@as string?]]
end

--- Dispatches a log entry to all configured outputs if the level passes the threshold.
---@param level bwf.Logger.level
---@param message string
---@param ... any # Format arguments
function Logger:log(level, message, ...)
  if self._closed then
    return
  end
  level = self._resolvers.level(level)
  if level < self._min_used_level then
    return
  end

  local time_sec, time_usec = luv.gettimeofday()
  message = tostring(assert(message, 'bad argument #3 to Logger.log (expected string)'))
  if select('#', ...) > 0 then
    message = string.format(message, ...)
  end

  for _, sink in ipairs(self.sinks) do
    if not self:_compareLevel(level, sink) then
      goto continue
    end

    local formatter = assert(
      self._formatters.general[sink.format],
      'bug (unreachable code): no formatter for the specified sink format was found'
    )
    local payload = formatter(self, sink, level, message, time_sec, math.floor(time_usec / 1000))
    self:_dispatch(sink, payload)

    ::continue::
  end
end

---@param message string
---@param ... any
function Logger:trace(message, ...)
  return self:log('trace', message, ...)
end

---@param message string
---@param ... any
function Logger:debug(message, ...)
  return self:log('debug', message, ...)
end

---@param message string
---@param ... any
function Logger:info(message, ...)
  return self:log('info', message, ...)
end

---@param message string
---@param ... any
function Logger:warn(message, ...)
  return self:log('warn', message, ...)
end

---@param message string
---@param ... any
function Logger:error(message, ...)
  return self:log('error', message, ...)
end

---@param message string
---@param ... any
function Logger:fatal(message, ...)
  return self:log('fatal', message, ...)
end

---@param call bwf.Call
function Logger:http(call)
  if self._closed then
    return
  end

  local level = 5
  if call.code >= 500 then
    level = 5
  elseif call.code >= 400 then
    level = 4
  elseif call.code >= 300 then
    level = 3
  elseif call.code >= 200 then
    level = 3
  elseif call.code >= 100 then
    level = 2
  end

  if level < self._min_used_level then
    return
  end

  local duration = luv.hrtime() - call.req._spawn_time
  local time_sec, time_usec = luv.gettimeofday()
  local time_ms = math.floor(time_usec / 1000)

  for _, sink in ipairs(self.sinks) do
    if not self:_compareLevel(level, sink) then
      goto continue
    end

    local payload
    if self._formatters.http[sink.format] then
      payload = self._formatters.http[sink.format](self, sink, level, call, duration, time_sec, time_ms)
    elseif self._formatters.general[sink.format] then
      local msg = call.req.method .. ' ' .. call.req.path.raw .. ' ' .. call.code .. ' ' .. self._formatters.readableDuration(duration)
      payload = self._formatters.general[sink.format](self, sink, level, msg, time_sec, time_ms)
    else
      error('bug (unreachable code): no formatter for the specified sink format was found')
    end
    self:_dispatch(sink, payload)

    ::continue::
  end
end

--- Creates a child logger bound to persistent context.
--- All logs emitted through the child inherit parent metadata and sinks.
---@param child_context table
---@return bwf.Logger
function Logger:child(child_context)
  local context = {}
  for k, v in pairs(self.options.context) do
    context[k] = v
  end
  if child_context then
    for k, v in pairs(child_context) do
      context[k] = v
    end
  end
  return setmetatable({
    options = setmetatable({ context = context }, { __index = self.options }),
    parent = self,
  }, { __index = self })
end

--- Flushes all pending write buffers and closes open file descriptors.
function Logger:close()
  if self._closed then
    return
  end
  self._closed = true
  for _, sink in ipairs(self.sinks) do
    if sink.close and sink.handle.close then
      pcall(sink.handle.close, sink.handle)
    end
  end
end

return Logger
