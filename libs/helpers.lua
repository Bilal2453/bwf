local helpers = {}

--- Use table `t` to store all of the vararg values,
--- only the array portion is used for storing the varargs
--- field `n` is also set to the current amount of arguments stored.
---
--- Table `t` can be reused as many times, it will automatically clear
--- the old values making use of the `n` field.
---@param t table
---@param ... any
---@return table
function helpers.fill(t, ...)
  local old_n = t.n or 0
  local n = select('#', ...)
  for i = 1, n do
    t[i] = select(i, ...)
  end
  t.n = n
  if old_n > n then
    for i = n + 1, old_n do
      t[i] = nil
    end
  end
  return t
end

--- Scan the give function for an upvalue that has a matching name and return it.
---@param fn function
---@param name string
---@return any
function helpers.getUpvalue(fn, name)
  local upvalue_name, value
  local i = 1
  repeat
    upvalue_name, value = debug.getupvalue(fn, i)
    i = i + 1
  until not upvalue_name or upvalue_name == name
  return value
end

return helpers
