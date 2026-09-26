local termcolor = {}

function termcolor.detectColorSupport()
  local term = os.getenv('TERM')
  if term and term:lower() == 'dumb' then
    return 0
  end
  local colorterm = os.getenv('COLORTERM')
  if colorterm == 'truecolor' or colorterm == '24bit' then
    return 24
  end
  return 16
end

function termcolor.preferredMode()
  local force_color = os.getenv('FORCE_COLOR')
  if force_color and force_color ~= '' and force_color ~= '0' then
    return 16
  end
  local no_color = os.getenv('NO_COLOR')
  if no_color and no_color ~= '' and no_color ~= '0' then
    return 0
  end
  return termcolor.detectColorSupport()
end

return termcolor
