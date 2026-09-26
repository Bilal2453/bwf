---@meta weblit

---@alias weblit.httpmethods 'GET'|'POST'|'PUT'|'DELETE'|'HEAD'|'TRACE'|'PATCH'|'CONNECT'|'OPTIONS'

---@class weblit.req
---@field socket uv_tcp_t
---@field method weblit.httpmethods
---@field path string
---@field headers {[1]: string, [2]: string}[] | {[string]: string?}
---@field version string
---@field keepAlive boolean
---@field body string
---@field query {[string]: string|string[]|nil}
---@field params {[string]: string|nil}

---@class weblit.res
---@field code integer
---@field headers {[1]: string, [2]: string}[] | {[string]: string?}
---@field body string?
---@field keepAlive boolean?
---@field upgrade function?

---@alias weblit.go function

---@alias weblit.handler fun(req: weblit.req, res: weblit.res, go: weblit.go)

---@class weblit.router
---@field use fun(handler: weblit.handler): weblit.app
---@field route fun(options: {method: weblit.httpmethods?, path: string?, host: string?, filter: (fun(req: weblit.req): boolean)?}, handler: weblit.handler): weblit.app
---@field run weblit.handler

---@class weblit.server
---@field setRun fun(newRun: fun(req, res, go)): weblit.app
---@field bind fun(options: {host: string?, port: integer?, tls: boolean?}): weblit.app
---@field start fun(): weblit.app
---@field websocket fun(options: table, handler: weblit.handler): weblit.app

---@class weblit.app: weblit.router, weblit.server

---@class weblit
---@field app weblit.app
---@field autoHeaders weblit.handler
---@field etagCache weblit.handler
---@field logger weblit.handler
---@field static fun(rootPath: string, redirect: string|boolean): weblit.handler
---@field websocket fun(options: table, handler: weblit.handler): weblit.handler
local weblit = {}

return weblit
