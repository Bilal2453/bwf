local module = require('../init')

-- define the server app
local app = module.App:new({
  host = '127.0.0.1',
  port = 8080,
})
app:hookRequest({
  id = 'ding',
  call = function(call)
    call:setHeader('X-Ding', '1')
  end
})

-- define the endpoint
local ping_endpoint = module.Endpoint:new({
  description = 'A ping endpoint that pongs back.',
  summary = 'Ping-pong',
})

ping_endpoint:get(function(call)
  if call:getHeader('X-Ding') == '1' then
    call:html('<h1>Dong!</h1>', 200)
  else
    call:html('<h1>Pong!</h1>', 200)
  end
end)

ping_endpoint:hookResponse({
  id = 'remove_ding',
  call = function(call)
    call:setHeader('X-Ding', nil)
  end
})

-- register endpoint and start the server
app:registerEndpoint('/ping', ping_endpoint)
app:start()
