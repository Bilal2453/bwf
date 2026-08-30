local json = require('json')

return {
  json = {
    phase = 'app',
    content_type = 'application/json',
    serialize = function(call)
      return json.encode(call.body.data)
    end,
  },
}
