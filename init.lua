local App = require('App')
local Endpoint = require('Endpoint')
local Routes = require('Routes')

-- TODO MAIN 1: right now I have endpoints and a place to store them, the Routes
-- what we need now is a real proper router, something that receives the requests and resolves them
-- that will be also the middleware between us and the weblit backend (or technically whatever backend)

-- TODO: proper localization framework
-- TODO: OpenAPI serialization support
-- TODO: IP utilities.
-- TODO: socket life management.
-- TODO: connection timeout management.
-- TODO: rate-limits.

return {
  App = App,
  Endpoint = Endpoint,
  Routes = Routes,
}
