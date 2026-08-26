--- Helpers shared by multiple adapters for converting data structures found in Call to something the backend understands.

local resolvers = {}

local duplicate_field = {
  ['set-cookie'] = true,
}

---@param headers { [string]: string | string[] | nil }
---@return {[1]: string, [2]: string}[]
---@nodiscard
function resolvers.headersToPairs(headers)
  local resolved = {}
  for name, value in pairs(headers) do
    if type(value) == 'table' then
      -- Headers with exceptions, duplicate the header to set multiple values
      if duplicate_field[name:lower()] then
        for _, v in ipairs(value) do
          resolved[#resolved + 1] = { name, v }
        end
      else
        -- Merge all fields into one comma-separated list
        resolved[#resolved + 1] = { name, table.concat(value, ',') }
      end
    else
      resolved[#resolved + 1] = { name, tostring(value) }
    end
  end
  return resolved
end

return resolvers
