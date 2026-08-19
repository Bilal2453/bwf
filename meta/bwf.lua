---@meta

---@class bwf.Operation: table
---@field summary string?
---@field description string?
---@field method string?
---@field tags string[]?
---@field deprecated boolean?
---@field body bwf.RequestBody?
---@field parameters bwf.Parameter[]?
---@field responses bwf.Response[]?
---@field docs bwf.Doc?
---@field callbacks table? # TODO
---@field security table? # TODO
---@field servers table? # TODO

---@class bwf.Parameter: table
---@field name string
---@field description string?
---@field required boolean?
---@field deprecated boolean?

---@class bwf.Response: table
---@field description string?
---@field headers table?
---@field content table?

---@class bwf.RequestBody: table
---@field description string?
---@field content table?
---@field required boolean?

---@class bwf.Doc: table
---@field description string
---@field url string

---@class bwf.Routes.options: bwf.Endpoint.options
---@field prefix? string

---@class bwf.Endpoint.options: table
---@field parameters? bwf.Parameter[]
---@field responses? bwf.Response[]
---@field tags? string[]
---@field docs? bwf.Doc[]
---@field security? table
---@field servers? table
---@field callbacks? table

---@class bwf.Endpoint.struct: table
---@field path string
---@field endpoint bwf.Endpoint
---@field options bwf.Endpoint.options

---@class bwf.Hook.struct: table
---@field id string
---@field call fun(call: bwf.Call)

---@alias bwd.Hook.resolvable bwf.Hook | bwf.Hook.struct

---@alias bwf.alias.routes_options {prefix?: string, parameters?: bwf.Parameter[], responses?: bwf.Response[], tags?: string[], docs?: bwf.Doc[], security?: table, callbacks?: table, servers?: table}

---@alias bwf.alias.endpoint_callback fun(call: bwf.Call)

---@alias bwf.alias.http_method 'get' | 'post' | 'put' | 'delete' | 'head' | 'query' | 'options' | 'trace' | 'patch'

---@alias bwf.alias.operation_struct {operation?: bwf.Operation, callback: bwf.alias.endpoint_callback}
