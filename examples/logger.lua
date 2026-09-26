local bwf = require('bwf')

local logger = bwf.Logger:new()

logger:addStream(io.stdout, {
  format = 'pretty',
  level = 'debug',
})

logger:addFile('logs/app.log', {
  format = 'json',
  level = 'info',
})

logger:info('Server initializing on %s:%d', '127.0.0.1', 8080)
logger:warn('Database pool running low: %d connections left', 2)

local req_logger = logger:child({ req_id = 'req-abc-123', ip = '192.168.1.5' })

req_logger:debug('Parsing request headers')
req_logger:info('Authenticated user: %s', 'bilal')
req_logger:error('Payment processing failed: %s', 'Card expired')

local app = bwf.App:new({
  logger = logger,
  host = '127.0.0.1',
  port = 8080,
})

app:get('/ping', function(call)
  logger:info('handling request')
  call:html('<h1>Pong!</h1>', 200)
end)

app:start()
