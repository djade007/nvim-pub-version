local M = {}

local DEFAULT_SKIP = {
  flutter = true,
  flutter_test = true,
  flutter_localizations = true,
  flutter_driver = true,
  integration_test = true,
}

--- Parse a pubspec.yaml buffer and extract dependencies with their versions.
--- Handles: inline versions, quoted versions, caret/range constraints,
--- multi-line map form with `version:` key, and dependency_overrides.
---@param lines string[]
---@param skip_packages? table<string, boolean>
---@return table[]
function M.parse_dependencies(lines, skip_packages)
  local skip = skip_packages or DEFAULT_SKIP
  local deps = {}
  local in_deps_block = false
  local pending_name = nil
  local pending_name_line = nil
  local indent_level = nil

  for i, line in ipairs(lines) do
    local raw = line

    -- Detect dependency/dev_dependency/dependency_overrides block headers
    if
      raw:match("^dependencies:%s*$")
      or raw:match("^dev_dependencies:%s*$")
      or raw:match("^dependency_overrides:%s*$")
    then
      in_deps_block = true
      pending_name = nil
      indent_level = nil
    elseif raw:match("^%S") and not raw:match("^#") then
      -- A new non-comment top-level key ends the dependency block
      in_deps_block = false
      pending_name = nil
      indent_level = nil
    elseif in_deps_block then
      -- Skip blank lines and comments
      if raw:match("^%s*$") or raw:match("^%s*#") then
        goto continue
      end

      local leading_spaces = #(raw:match("^(%s*)") or "")

      -- Detect top-level dependency entry (2-space indent typically)
      if indent_level == nil and leading_spaces > 0 then
        indent_level = leading_spaces
      end

      if indent_level and leading_spaces == indent_level then
        -- This is a dependency line at the block's child level
        pending_name = nil -- reset any pending multi-line dep

        -- Try inline version: `  package_name: ^1.2.3` or `  package_name: ">=1.0.0 <2.0.0"`
        -- Handle all orderings: quotes then caret, caret then quotes, bare
        local name, version = M._extract_inline(raw)
        if name and version and not skip[name] then
          table.insert(deps, {
            name = name,
            version = version,
            line = i - 1, -- 0-indexed for extmark API
            raw_line = raw,
          })
        elseif not version then
          -- Could be multi-line map form: `  package_name:` or `  package_name:\n    version: ...`
          -- or sdk/path/git dep (no version to check)
          local n = raw:match("^%s+([%w_]+):%s*$")
          if n and not skip[n] then
            pending_name = n
            pending_name_line = i - 1
          end
        end
      elseif pending_name and indent_level and leading_spaces > indent_level then
        -- Inside a multi-line dependency map, look for `version:` key
        local version = raw:match("^%s+version:%s+[\"']?%^?[><=]*(%d+%.%d+%.%d+[%w%.%+%-]*)")
        if version then
          table.insert(deps, {
            name = pending_name,
            version = version,
            line = pending_name_line,
            raw_line = lines[pending_name_line + 1],
          })
          pending_name = nil
        end
        -- Check for sdk:/path:/git: keys to abandon this pending dep
        if raw:match("^%s+sdk:%s") or raw:match("^%s+path:%s") or raw:match("^%s+git:") then
          pending_name = nil
        end
      end
    end
    ::continue::
  end

  return deps
end

--- Extract package name and version from an inline dependency line.
--- Supports: `name: ^1.2.3`, `name: "^1.2.3"`, `name: '>=1.0.0 <2.0.0'`, `name: 1.2.3`, `name: any`
---@param line string
---@return string|nil name
---@return string|nil version
function M._extract_inline(line)
  -- Match: `  name: <optional quotes><optional constraint ops><version>`
  -- The version part: digits.digits.digits with optional suffix
  local name, rest = line:match("^%s+([%w_]+):%s+(.+)$")
  if not name or not rest then return nil, nil end

  -- Strip surrounding quotes
  rest = rest:gsub("^[\"']", ""):gsub("[\"']%s*$", "")

  -- Extract version number from constraint string
  -- Supports: ^1.2.3, >=1.2.3, <=1.2.3, >1.2.3, <1.2.3, =1.2.3, 1.2.3
  local version = rest:match("[%^><=]*%s*(%d+%.%d+%.%d+[%w%.%+%-]*)")
  if version then
    return name, version
  end

  -- No version found (could be `any`, a path, a git ref, or just `name:`)
  return name, nil
end

return M
