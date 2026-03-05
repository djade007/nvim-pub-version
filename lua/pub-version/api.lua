local cache = require("pub-version.cache")

local M = {}

local PUB_API_URL = "https://pub.dev/api/packages/"
local MAX_CONCURRENT = 5

local _active = 0
local _queue = {}

local function _drain_queue()
  while _active < MAX_CONCURRENT and #_queue > 0 do
    local task = table.remove(_queue, 1)
    _active = _active + 1
    task()
  end
end

local function _enqueue(fn)
  table.insert(_queue, fn)
  _drain_queue()
end

local function _release()
  _active = _active - 1
  _drain_queue()
end

---@class FetchResult
---@field version string
---@field is_discontinued boolean
---@field replacement string|nil
---@field description string|nil
---@field homepage string|nil

--- Fetch package info from pub.dev asynchronously with concurrency limiting and caching.
---@param name string Package name
---@param callback fun(result: FetchResult|nil, err: string|nil)
---@param cache_ttl? number Cache TTL in seconds (default 300)
function M.fetch_latest_version(name, callback, cache_ttl)
  -- Check cache first
  local cached = cache.get(name, cache_ttl)
  if cached then
    vim.schedule(function()
      callback(cached, nil)
    end)
    return
  end

  _enqueue(function()
    local url = PUB_API_URL .. name
    vim.system(
      { "curl", "-s", "-f", "--max-time", "10", url },
      { text = true },
      vim.schedule_wrap(function(result)
        _release()

        if result.code ~= 0 or not result.stdout or result.stdout == "" then
          callback(nil, "Failed to fetch " .. name)
          return
        end

        local ok, data = pcall(vim.json.decode, result.stdout)
        if not ok or not data then
          callback(nil, "Failed to parse JSON for " .. name)
          return
        end

        local latest = data.latest and data.latest.version
        if not latest then
          callback(nil, "No latest version found for " .. name)
          return
        end

        local pubspec = data.latest and data.latest.pubspec or {}
        local entry = {
          version = vim.trim(latest),
          is_discontinued = data.isDiscontinued == true,
          replacement = data.replacedBy,
          description = pubspec.description,
          homepage = pubspec.homepage or pubspec.repository,
        }

        cache.set(name, entry)

        callback(entry, nil)
      end)
    )
  end)
end

return M
