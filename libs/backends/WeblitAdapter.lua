local Adapter = require('./Adapter')
local Call = require('Call')
local weblit_server = require('weblit-server')

---@class WeblitAdapter: Adapter
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

function WeblitAdapter:handler(req, res)
  -- TODO: standarize req/res into a structure that's backend agnostic
  local adapted = {
    req = req,
    res = res,
  }
  local call = Call:new(self.app, adapted)
  call.state._backend = adapted
  self.app:_dispatch(call)
end

---@param call bwf.Call
function WeblitAdapter:flush(call)
  if not (call.state._backend and call.state._backend.res) then
    return nil, 'Invalid Call object'
  end
  local res = call.state._backend.res --[[@as weblit.res]]

  res.body = call.body
  res.code = call.code
  res.headers = call.headers
  res.keepAlive = call.keepAlive
  return true
end

return WeblitAdapter
