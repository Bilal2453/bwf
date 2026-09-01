local json = require('json')

return {
  ['application/json'] = {
    phase = 'app',
    decode = function(raw)
      return json.decode(raw)
    end,
  },
}
