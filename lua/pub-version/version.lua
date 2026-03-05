local M = {}

--- Parse a semver string into { major, minor, patch, prerelease, build }.
---@param v string
---@return table|nil
function M.parse(v)
  if not v then return nil end
  local major, minor, patch, rest = v:match("^(%d+)%.(%d+)%.(%d+)(.*)")
  if not major then return nil end
  local prerelease, build
  if rest and rest ~= "" then
    prerelease = rest:match("^%-([%w%.%-]+)")
    build = rest:match("%+([%w%.%-]+)$")
  end
  return {
    major = tonumber(major),
    minor = tonumber(minor),
    patch = tonumber(patch),
    prerelease = prerelease,
    build = build,
  }
end

--- Compare two prerelease strings per semver spec.
--- Split on '.', compare each identifier: numeric ids compared as integers,
--- string ids compared lexicographically, numeric < string.
---@param a string
---@param b string
---@return number -1, 0, or 1
local function compare_prerelease(a, b)
  local a_parts = vim.split(a, ".", { plain = true })
  local b_parts = vim.split(b, ".", { plain = true })

  local len = math.max(#a_parts, #b_parts)
  for i = 1, len do
    local ap = a_parts[i]
    local bp = b_parts[i]
    -- Fewer fields = lower precedence
    if not ap and bp then return -1 end
    if ap and not bp then return 1 end

    local an = tonumber(ap)
    local bn = tonumber(bp)

    if an and bn then
      -- Both numeric
      if an ~= bn then return an < bn and -1 or 1 end
    elseif an and not bn then
      -- Numeric < string
      return -1
    elseif not an and bn then
      return 1
    else
      -- Both strings
      if ap ~= bp then return ap < bp and -1 or 1 end
    end
  end
  return 0
end

--- Compare two parsed semver tables.
---@param va table
---@param vb table
---@return number -1, 0, or 1
local function compare_parsed(va, vb)
  if va.major ~= vb.major then return va.major < vb.major and -1 or 1 end
  if va.minor ~= vb.minor then return va.minor < vb.minor and -1 or 1 end
  if va.patch ~= vb.patch then return va.patch < vb.patch and -1 or 1 end

  -- Both have no prerelease: equal
  if not va.prerelease and not vb.prerelease then return 0 end
  -- Prerelease has lower precedence than release
  if va.prerelease and not vb.prerelease then return -1 end
  if not va.prerelease and vb.prerelease then return 1 end

  return compare_prerelease(va.prerelease, vb.prerelease)
end

--- Compare two semver strings.
--- Returns: 0 if equal, -1 if a < b, 1 if a > b, nil if either is unparseable
---@param a string
---@param b string
---@return number|nil
function M.compare(a, b)
  local va = M.parse(a)
  local vb = M.parse(b)
  if not va or not vb then return nil end
  return compare_parsed(va, vb)
end

--- Determine the upgrade type between current and latest.
---@param current string
---@param latest string
---@return "major"|"minor"|"patch"|"prerelease"|"up_to_date"|"unknown"
function M.upgrade_type(current, latest)
  local vc = M.parse(current)
  local vl = M.parse(latest)
  if not vc or not vl then return "unknown" end

  local cmp = compare_parsed(vc, vl)
  if cmp >= 0 then return "up_to_date" end

  if vl.major > vc.major then return "major" end
  if vl.minor > vc.minor then return "minor" end
  if vl.patch > vc.patch then return "patch" end
  return "prerelease"
end

return M
