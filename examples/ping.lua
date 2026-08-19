local module = require('../init')

local app = module.App:new({
  host = '127.0.0.1',
  port = 8080,
})

app:get('/ping', function(call)
  call:html('<h1>Pong!</h1>', 200)
end)

app:post('/ping', function(call)
  call:html('<h1>Pong!</h1>', 200)
end)

app:start()
