local App = require('App')
local Endpoint = require('Endpoint')
local Routes = require('Routes')

-- TODO: bwf.builder.operation and bwf.builder.problem
-- TODO: proper logging
-- TODO: proper localization framework
-- TODO: OpenAPI serialization support
-- TODO: IP utilities.
-- TODO: socket life management.
-- TODO: connection timeout management.
-- TODO: rate-limits.
-- TODO: Authorization hooks
-- TODO: Authentication hooks
-- TODO: Database utilities?
-- TODO: CORS hooks
-- TODO: Memory limits? Body size safeguards?
-- TODO: default headers hooks `HSTS, X-Content-Type-Options: nosniff, X-Frame-Options, Content-Security-Policy` etc

return {
  App = App,
  Endpoint = Endpoint,
  Routes = Routes,
}
