local core = require('core')

---@class Adapter: luvit.core.Object
---@field app bwf.App
--- This is an abstract class, a direct instance of this class must not exist.
local Adapter = core.Object:extend()

function Adapter:initialize(app)
  self.app = assert(app)
end

function Adapter:start()
  return nil, 'NYI'
end

function Adapter:stop()
  return nil, 'NYI'
end

function Adapter:handler()
  return nil, 'NYI'
end

---@param call bwf.Call
---@return boolean? success, string? error_message
function Adapter:flush(call)
  return nil, 'NYI'
end

return Adapter
