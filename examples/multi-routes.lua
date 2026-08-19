local module = require('../init')

local app = module.App:new({
  host = '127.0.0.1',
  port = 8080,
})

local prod = module.Routes:new({
  prefix = '/api/prod/',
})
prod:get('/ping', function(call)
  call:html('<h1>Pong!</h1>', 200)
end)

local staging = module.Routes:new({
  prefix = '/api/staging',
})
staging:get('/ping', function(call)
  call:html('<h1>I am tired stop pinging</h1>', 200)
end)

app:registerRoutes(prod)
app:registerRoutes(staging)
app:registerEndpoint('/test-{case}', prod:getEndpoint('/ping').endpoint)

app:start()
