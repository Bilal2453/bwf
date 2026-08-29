local uri = require('uri')

local inputs = {
  'http://[::1:2:3:4:5]',
  'http://[0:0:0:1:2:3:4:5]',
  'http://[1:2::3:4:5]',
  'http://[1:2:0:0:0:3:4:5]',
  'http://[1:2:3:4:5::]',
  'http://[1:2:3:4:5:0:0:0]',
  'http://[0:0:0:0:0:ffff:102:405]',
  'http://[::]',
  'http://[::0]',
  'http://[::1]',
  'http://[0:0:0::1]',
  'http://[ffff::1]',
  'http://[ffff:0:0:0:0:0:0:1]',
  'http://[2001:0db8:0a0b:12f0:0:0:0:1]',
  'http://[2001:db8:a0b:12f0::1]',
  'http://[::ffff:1.2.3.4]',
  'http://[::ffff:1.2.3.4]',
  'http://[::ffff:1.2.3.4]:5678',
  'http://[1:2:3:4:5:0:0:0]',
  'http://[1:2:3:4:5:0:0:0]:5678',
  'http://[1:2:3:4:5::]:5678',
}

for i, v in ipairs(inputs) do
  assert(uri.decode(v), i)
end
