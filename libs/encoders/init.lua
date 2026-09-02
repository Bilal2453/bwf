local json = require('json')

return {
  json = {
    phase = 'app',
    content_type = 'application/json',
    encode = function(call)
      return json.encode(call.body.data)
    end,
  },
  problem = {
    phase = 'app',
    content_type = 'application/problem+json',
    encode = function(call)
      return json.encode(call.body.data)
    end,
  },
}
