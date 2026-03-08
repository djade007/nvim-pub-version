local parser = require("pub-version.parser")
local api = require("pub-version.api")
local display = require("pub-version.display")
local cache = require("pub-version.cache")
local version_util = require("pub-version.version")

local M = {}

M.config = {
  auto_check = true,
  cache_ttl = 300,
  debounce_ms = 500,
  colors = {
    up_to_date = "#a6e3a1",
    major = "#f38ba8",
    minor = "#f9e2af",
    patch = "#89b4fa",
    discontinued = "#f38ba8",
  },
  icons = {
    up_to_date = "",
    major = "",
    minor = "",
    patch = "",
    discontinued = "",
  },
  keymaps = {
    enabled = true,
    update = "<leader>pu",
    update_all = "<leader>pU",
    open = "<leader>po",
    check = "<leader>pc",
    info = "K",
  },
}

-- Per-buffer state: generation counters to cancel stale callbacks
---@type table<number, number>
local _generations = {}

-- Per-buffer debounce timers
---@type table<number, uv_timer_t>
local _timers = {}

-- Per-buffer results for quick-fix actions
---@type table<number, table<number, table>>
local _results = {}

--- Check if current buffer is a pubspec.yaml
---@param bufnr number
---@return boolean
local function is_pubspec(bufnr)
  return vim.fs.basename(vim.api.nvim_buf_get_name(bufnr)) == "pubspec.yaml"
end

--- Get the dependency on the current cursor line.
---@param bufnr number
---@return table|nil
local function get_dep_at_cursor(bufnr)
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed
  local buf_results = _results[bufnr]
  if not buf_results then return nil end
  return buf_results[line]
end

--- Apply a version update to a single dependency line (buffer text only).
---@param bufnr number
---@param dep table
---@return boolean true if the line was changed
local function apply_update(bufnr, dep)
  local line_content = vim.api.nvim_buf_get_lines(bufnr, dep.line, dep.line + 1, false)[1]
  if not line_content then return false end
  local new_line = line_content:gsub(vim.pesc(dep.current), dep.latest, 1)
  if new_line == line_content then return false end
  vim.api.nvim_buf_set_lines(bufnr, dep.line, dep.line + 1, false, { new_line })
  return true
end

--- Run the version check on a buffer.
---@param bufnr? number
function M.check(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not is_pubspec(bufnr) then
    vim.notify("pub-version: Not a pubspec.yaml file", vim.log.levels.WARN)
    return
  end

  -- Increment generation to invalidate any in-flight callbacks
  local gen = (_generations[bufnr] or 0) + 1
  _generations[bufnr] = gen
  _results[bufnr] = {}

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local deps = parser.parse_dependencies(lines)

  if #deps == 0 then
    display.clear(bufnr)
    return
  end

  -- Show loading indicators (replaces any existing extmarks per-line)
  for _, dep in ipairs(deps) do
    display.set_loading(bufnr, dep.line)
  end

  local pending = #deps

  for _, dep in ipairs(deps) do
    api.fetch_latest_version(dep.name, function(result, err)
      vim.schedule(function()
        -- Discard if buffer gone or generation is stale
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        if _generations[bufnr] ~= gen then return end

        if err or not result then
          display.set_error(bufnr, dep.line, err or "unknown error")
        else
          display.set_result(bufnr, dep.line, dep.version, result.version, {
            is_discontinued = result.is_discontinued,
            replacement = result.replacement,
          })

          -- Store result for quick-fix actions
          _results[bufnr][dep.line] = {
            name = dep.name,
            current = dep.version,
            latest = result.version,
            raw_line = dep.raw_line,
            line = dep.line,
            is_discontinued = result.is_discontinued,
            replacement = result.replacement,
            description = result.description,
            homepage = result.homepage,
            upgrade = version_util.upgrade_type(dep.version, result.version),
          }
        end

        pending = pending - 1
        if pending == 0 then
          vim.notify(
            string.format("pub-version: Checked %d dependencies", #deps),
            vim.log.levels.INFO
          )
        end
      end)
    end, M.config.cache_ttl)
  end
end

--- Debounced check — cancels previous pending check for this buffer.
---@param bufnr number
local function debounced_check(bufnr)
  local timer = _timers[bufnr]
  if timer then
    timer:stop()
    timer:close()
  end
  local t = vim.uv.new_timer()
  _timers[bufnr] = t
  t:start(M.config.debounce_ms, 0, vim.schedule_wrap(function()
    t:stop()
    t:close()
    _timers[bufnr] = nil
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.check(bufnr)
    end
  end))
end

--- Update the dependency under cursor to its latest version.
---@param bufnr? number
function M.update(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local dep = get_dep_at_cursor(bufnr)
  if not dep then
    vim.notify("pub-version: No dependency found on this line", vim.log.levels.WARN)
    return
  end
  if dep.current == dep.latest then
    vim.notify("pub-version: " .. dep.name .. " is already up to date", vim.log.levels.INFO)
    return
  end

  if apply_update(bufnr, dep) then
    vim.notify("pub-version: Updated " .. dep.name .. " to " .. dep.latest, vim.log.levels.INFO)
    M.check(bufnr) -- re-check to realign all annotations
  end
end

--- Update all outdated dependencies.
---@param bufnr? number
function M.update_all(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buf_results = _results[bufnr]
  if not buf_results then
    vim.notify("pub-version: No check results available. Run :PubVersionCheck first", vim.log.levels.WARN)
    return
  end

  -- Collect outdated deps, sort by line descending to preserve line numbers
  local outdated = {}
  for _, dep in pairs(buf_results) do
    if dep.current ~= dep.latest and not dep.is_discontinued then
      table.insert(outdated, dep)
    end
  end

  if #outdated == 0 then
    vim.notify("pub-version: All dependencies are up to date", vim.log.levels.INFO)
    return
  end

  table.sort(outdated, function(a, b) return a.line > b.line end)

  local count = 0
  for _, dep in ipairs(outdated) do
    if apply_update(bufnr, dep) then
      count = count + 1
    end
  end

  vim.notify(
    string.format("pub-version: Updated %d/%d dependencies", count, #outdated),
    vim.log.levels.INFO
  )

  -- Re-check to re-parse the modified buffer and realign all annotations.
  -- Versions are cached so this is instant.
  if count > 0 then
    M.check(bufnr)
  end
end

--- Open the pub.dev page for the dependency under cursor.
---@param bufnr? number
function M.open(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local dep = get_dep_at_cursor(bufnr)
  if not dep then
    vim.notify("pub-version: No dependency found on this line", vim.log.levels.WARN)
    return
  end
  vim.ui.open("https://pub.dev/packages/" .. dep.name)
end

--- Show package info in a floating window for the dependency under cursor.
---@param bufnr? number
function M.info(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local dep = get_dep_at_cursor(bufnr)
  if not dep then return nil end -- Return nil so fallback K mapping works

  local lines_content = {
    "# " .. dep.name,
    "",
    "**Current:** " .. dep.current,
    "**Latest:**  " .. dep.latest .. " (" .. (dep.upgrade or "unknown") .. ")",
  }

  if dep.is_discontinued then
    table.insert(lines_content, "")
    local disc = "**Status:** DISCONTINUED"
    if dep.replacement then
      disc = disc .. " -> use **" .. dep.replacement .. "**"
    end
    table.insert(lines_content, disc)
  end

  if dep.description then
    table.insert(lines_content, "")
    table.insert(lines_content, dep.description)
  end

  if dep.homepage then
    table.insert(lines_content, "")
    table.insert(lines_content, dep.homepage)
  end

  table.insert(lines_content, "")
  table.insert(lines_content, "https://pub.dev/packages/" .. dep.name)

  vim.lsp.util.open_floating_preview(lines_content, "markdown", {
    border = "rounded",
    focus_id = "pub_version_info",
  })
  return true -- Signal that we handled it
end

--- Get statusline component text for the current buffer.
---@return string
function M.statusline()
  local bufnr = vim.api.nvim_get_current_buf()
  if not is_pubspec(bufnr) then return "" end
  local buf_results = _results[bufnr]
  if not buf_results then return "" end

  local counts = { major = 0, minor = 0, patch = 0, discontinued = 0 }
  for _, dep in pairs(buf_results) do
    if dep.is_discontinued then
      counts.discontinued = counts.discontinued + 1
    else
      local upgrade = dep.upgrade or "up_to_date"
      if upgrade ~= "up_to_date" and upgrade ~= "unknown" then
        counts[upgrade] = (counts[upgrade] or 0) + 1
      end
    end
  end

  local parts = {}
  if counts.major > 0 then table.insert(parts, counts.major .. " major") end
  if counts.minor > 0 then table.insert(parts, counts.minor .. " minor") end
  if counts.patch > 0 then table.insert(parts, counts.patch .. " patch") end
  if counts.discontinued > 0 then table.insert(parts, counts.discontinued .. " discontinued") end

  if #parts == 0 then return "pub: up to date" end
  return "pub: " .. table.concat(parts, ", ")
end

--- Set buffer-local keymaps for pubspec.yaml buffers.
---@param bufnr number
local function set_keymaps(bufnr)
  if not M.config.keymaps.enabled then return end
  local km = M.config.keymaps

  local opts = function(desc)
    return { buffer = bufnr, desc = desc, silent = true }
  end

  vim.keymap.set("n", km.update, function() M.update() end, opts("Update dependency"))
  vim.keymap.set("n", km.update_all, function() M.update_all() end, opts("Update all dependencies"))
  vim.keymap.set("n", km.open, function() M.open() end, opts("Open on pub.dev"))
  vim.keymap.set("n", km.check, function() M.check() end, opts("Check pub versions"))

  -- For K, try info first, fall back to default K behavior
  if km.info then
    vim.keymap.set("n", km.info, function()
      if not M.info() then
        vim.cmd("normal! K")
      end
    end, opts("Package info"))
  end
end

---@param opts? table
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  display.setup_highlights(M.config)

  vim.api.nvim_create_user_command("PubVersionCheck", function()
    M.check()
  end, { desc = "Check pub.dev for latest dependency versions" })

  vim.api.nvim_create_user_command("PubVersionClear", function()
    display.clear(vim.api.nvim_get_current_buf())
  end, { desc = "Clear pub version annotations" })

  vim.api.nvim_create_user_command("PubVersionUpdate", function()
    M.update()
  end, { desc = "Update dependency under cursor to latest" })

  vim.api.nvim_create_user_command("PubVersionUpdateAll", function()
    M.update_all()
  end, { desc = "Update all outdated dependencies" })

  vim.api.nvim_create_user_command("PubVersionOpen", function()
    M.open()
  end, { desc = "Open dependency on pub.dev" })

  vim.api.nvim_create_user_command("PubVersionInfo", function()
    M.info()
  end, { desc = "Show package info float" })

  vim.api.nvim_create_user_command("PubVersionClearCache", function()
    cache.clear()
    vim.notify("pub-version: Cache cleared", vim.log.levels.INFO)
  end, { desc = "Clear version cache" })

  -- Always create augroup to clear previous autocmds on re-setup
  local group = vim.api.nvim_create_augroup("PubVersionChecker", { clear = true })

  if M.config.auto_check then
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "pubspec.yaml",
      callback = function(ev)
        -- Only check if we don't already have results for this buffer
        if not _results[ev.buf] or vim.tbl_isempty(_results[ev.buf]) then
          debounced_check(ev.buf)
        end
      end,
      group = group,
    })

    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = "pubspec.yaml",
      callback = function(ev)
        debounced_check(ev.buf)
      end,
      group = group,
    })
  end

  -- Set buffer-local keymaps for pubspec.yaml files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "yaml",
    callback = function(ev)
      if is_pubspec(ev.buf) then
        set_keymaps(ev.buf)
      end
    end,
    group = group,
  })

  -- Cleanup on buffer wipeout
  vim.api.nvim_create_autocmd("BufWipeout", {
    pattern = "pubspec.yaml",
    callback = function(ev)
      _generations[ev.buf] = (_generations[ev.buf] or 0) + 1 -- invalidate callbacks
      _results[ev.buf] = nil
      local timer = _timers[ev.buf]
      if timer then
        timer:stop()
        timer:close()
        _timers[ev.buf] = nil
      end
    end,
    group = group,
  })
end

return M
