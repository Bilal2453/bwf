local module = require('../init')

local app = module.App:new({
  host = '127.0.0.1',
  port = 8080,
})

-- Mock database of users
local users = {
  ['1'] = { id = 1, username = 'bilal', email = 'bilal@bilal0.com', role = 'admin' },
  ['2'] = { id = 2, username = 'support', email = 'support@bilal0.com', role = 'support' },
  ['3'] = { id = 3, username = 'manager', email = 'manager@bilal0.com', role = 'manager' },
}

-- GET /users - list all users
app:get('/users', function(call)
  local user_list = {}
  for _, user in pairs(users) do
    table.insert(user_list, user)
  end
  call:json(user_list, 200)
end)

-- GET /users/{id} - get a specific user by ID
app:get('/users/{id}', function(call)
  local id = call:getParam('id')
  local user = users[id]

  if user then
    call:json(user, 200)
  else
    call:json({ error = 'User not found' }, 404)
  end
end)

app:start()
