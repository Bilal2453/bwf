-- Copyright 2026 Truemedian
-- See https://github.com/truemedian/gud/blob/something-new/deps/uri.lua
-- modifications:
--  - removed resolve due to path requirement
--  - fixed userinfo not capturing percentDecode

local re = require('re')

--- @class bwf.uri
local uri = {}

--- @class bwf.uri.parsed
--- @field scheme string|nil
--- @field userinfo string|nil
--- @field hostname string|nil
--- @field port integer|nil
--- @field path string
--- @field query string|nil
--- @field fragment string|nil

local function percent_encode(c)
  return string.format('%%%02X', string.byte(c))
end

--- @param str string
--- @param space string|nil
--- @return string
function uri.percentEncode(str, space)
  local encoded = str:gsub('([^A-Za-z0-9._~-])', percent_encode)
  if space then
    encoded = encoded:gsub('%20', space)
  end

  return encoded
end

local function percent_decode(hex)
  return string.char(tonumber(hex, 16))
end

--- @param str string
--- @param space string|nil
--- @return string
function uri.percentDecode(str, space)
  local decoded = str:gsub('%%(%x%x)', percent_decode)
  if space then
    decoded = decoded:gsub(space, ' ')
  end

  return decoded
end

local grammar = re.compile(
  [[
    uri         <-  {| (scheme ':')? hierarchy ('?' query)? ('#' fragment)? !. |}
    scheme      <-  {:scheme: [%a] [%w+.-]* :}
    hierarchy   <-  ('//' authority path) / path

    authority   <-  (userinfo '@')? host (':' port)?
    userinfo    <-  {:user: {: ( percent_encoded / unreserved / sub_delims / ':' )* -> percentDecode :} :}
    port        <-  {:port: ( [0-9]+ ) -> tonumber :}

    host        <-  ip_literal / {:hostname: ip4_address :} / {:hostname: hostname -> percentDecode :}
    hostname    <- ( percent_encoded / unreserved / sub_delims )*

    ip4_address <-  dec_octet '.' dec_octet '.' dec_octet '.' dec_octet
    dec_octet   <-  '25' [0-5] / '2' [0-4] [0-9] / '1' [0-9] [0-9] / [1-9] [0-9]? / '0'

    ip_literal  <-  '[' {:hostname:  ip6_address :} ']'
    ip6_address <-                             ( h16 ':' )^6 ls32
                /                         '::' ( h16 ':' )^5 ls32
                / (                h16 )? '::' ( h16 ':' )^4 ls32
                / ( ( h16 ':' )^-1 h16 )? '::' ( h16 ':' )^3 ls32
                / ( ( h16 ':' )^-2 h16 )? '::' ( h16 ':' )^2 ls32
                / ( ( h16 ':' )^-3 h16 )? '::'   h16 ':'     ls32
                / ( ( h16 ':' )^-4 h16 )? '::'               ls32
                / ( ( h16 ':' )^-5 h16 )? '::'               h16
                / ( ( h16 ':' )^-6 h16 )? '::'
    ls32        <- ( h16 ':' h16 ) / ip4_address
    h16         <- [%x] [%x]^-3

    path        <-  {:path: pchar* ( '/' pchar* )* -> percentDecode :}
    query       <-  {:query: ( '/' / '?' / pchar )* -> percentDecode :}
    fragment    <-  {:fragment: ( '/' / '?' / pchar )* -> percentDecode :}
    pchar       <-  percent_encoded / unreserved / sub_delims / [:@]
    unreserved  <-  [%w._~-]
    sub_delims  <-  [!$&'()*+,;=]

	percent_encoded <- '%' %x %x
]],
  {
    tonumber = tonumber,
    percentDecode = uri.percentDecode,
  }
)

--- @param info bwf.uri.parsed
--- @return string
function uri.encode(info)
  local parts, n = {}, 0

  if info.scheme then
    parts[n + 1] = info.scheme
    parts[n + 2] = ':'
    n = n + 2
  end

  if info.hostname then
    parts[n + 1] = '//'
    n = n + 1

    if info.userinfo then
      parts[n + 1] = info.userinfo
      parts[n + 2] = '@'
      n = n + 2
    end

    parts[n + 1] = info.hostname

    if info.port then
      parts[n + 1] = ':'
      parts[n + 2] = tostring(info.port)
      n = n + 2
    end
  end

  parts[n + 1] = info.path
  n = n + 1

  if info.query then
    parts[n + 1] = '?'
    parts[n + 2] = info.query
    n = n + 2
  end

  if info.fragment then
    parts[n + 1] = '#'
    parts[n + 2] = info.fragment
    n = n + 2
  end

  return table.concat(parts, nil, 1, n)
end

--- @param str string
--- @return bwf.uri.parsed|nil parsed
function uri.decode(str)
  local parsed = grammar:match(str)
  if not parsed then
    return nil
  end

  return parsed
end

-- TODO: add back resolve

return uri
