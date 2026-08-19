local Endpoint = require('...') --[[@as bwf.Endpoint]]

---@class TestEndpoint: bwf.Endpoint
local TestEndpoint = Endpoint:extend()
TestEndpoint.summary = 'Foo bar'
TestEndpoint.permission = { 'admin' } --- Might be a better idea to keep this for the router

local ping = TestEndpoint:new({
  summary = 'Send a Ping',
  description = 'Sends a ping request and returns the time it took to process it.',
})

ping:get(function() end, {
  summary = 'fetches your data',
  description = 'a very detailed description.',
  method = 'getTestData',
  tags = { 'search', 'dummy' },
  deprecated = true,
  body = {
    description = 'Request body description',
    content = {},
    required = false,
  },
  parameters = {
    {
      name = 'ID of test subject',
      -- *in: path*
      description = 'Detailed description',
      required = true,
      deprecated = false,
    },
  },
  responses = {
    ['201'] = {
      description = 'Success',
      headers = {},
      content = {},
    },
  },
  docs = {
    description = 'Documentation for this operation',
    url = 'https://www.google.com/',
  },
  callbacks = {},
  security = {},
  servers = {},
})

return TestEndpoint
