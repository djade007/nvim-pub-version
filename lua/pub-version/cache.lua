local M = {}

---@class CacheEntry
---@field version string
---@field is_discontinued boolean
---@field replacement string|nil
---@field description string|nil
---@field homepage string|nil
---@field fetched_at number

---@type table<string, CacheEntry>
local _cache = {}

local DEFAULT_TTL = 300 -- 5 minutes

---@param name string
---@param ttl? number seconds
---@return CacheEntry|nil
function M.get(name, ttl)
  ttl = ttl or DEFAULT_TTL
  local entry = _cache[name]
  if not entry then return nil end
  if os.time() - entry.fetched_at > ttl then
    _cache[name] = nil
    return nil
  end
  return entry
end

---@param name string
---@param entry CacheEntry
function M.set(name, entry)
  local stored = vim.tbl_extend("force", entry, { fetched_at = os.time() })
  _cache[name] = stored
end

function M.clear()
  _cache = {}
end

---@return number
function M.size()
  return vim.tbl_count(_cache)
end

return M
