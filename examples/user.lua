local module = require('../init')

local app = module.App:new({
  host = '127.0.0.1',
  port = 8080,
})

-- Mock database of users
local users = {
  { id = 1, username = 'bilal', email = 'bilal@bilal0.com', role = 'admin' },
  { id = 2, username = 'support', email = 'support@bilal0.com', role = 'support' },
  { id = 3, username = 'manager', email = 'manager@bilal0.com', role = 'manager' },
}

-- GET /users - list all users
app:get('/users', function(call)
  call:json(users, 200)
end)

-- GET /users/{id} - get a specific user by ID
app:get('/users/{id}', function(call)
  local id = tonumber(call:getParam('id'))
  local user = users[id]

  if user then
    call:json(user, 200)
  else
    call:problem('User not found', 404)
  end
end)

-- POST /users - create a new user
app:post('/users', {
  description = 'Create a new user',
  body = {
    content = {
      ['application/json'] = {}, -- TODO: true can be used to avoid a table allocation
    },
    required = true,
  },
}, function(call)
  local payload = call.req.body

  -- simple validation check (should later be handled by framework)
  if not payload.username or not payload.email then
    call:problem({
      type = '/errors/users/invalid-user',
      detail = 'Missing username or email',
    }, 400)
    return
  end

  local new_id = #users + 1
  local new_user = {
    id = new_id,
    username = payload.username,
    email = payload.email,
    role = payload.role or 'user',
  }
  users[new_id] = new_user

  call:json(new_user, 201)
end)

app:start()
