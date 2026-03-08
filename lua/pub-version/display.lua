local version_util = require("pub-version.version")

local M = {}

local ns = vim.api.nvim_create_namespace("pub_version_checker")

local _config = nil

--- Check that a line is within buffer bounds.
---@param bufnr number
---@param line number 0-indexed
---@return boolean
local function line_valid(bufnr, line)
  if not vim.api.nvim_buf_is_valid(bufnr) then return false end
  return line >= 0 and line < vim.api.nvim_buf_line_count(bufnr)
end

--- Clear extmarks on a line and set new virtual text.
---@param bufnr number
---@param line number 0-indexed
---@param text string
---@param hl string highlight group
local function set_virt_text(bufnr, line, text, hl)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, line, line + 1)
  vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
    virt_text = { { "  " .. text, hl } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
end

--- Clear all virtual text in the buffer.
---@param bufnr number
function M.clear(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Show a loading indicator on a dependency line.
---@param bufnr number
---@param line number 0-indexed
function M.set_loading(bufnr, line)
  if not line_valid(bufnr, line) then return end
  set_virt_text(bufnr, line, "fetching...", "Comment")
end

--- Display the version check result on a dependency line.
---@param bufnr number
---@param line number 0-indexed
---@param current string
---@param latest string
---@param opts? { is_discontinued: boolean?, replacement: string? }
function M.set_result(bufnr, line, current, latest, opts)
  if not line_valid(bufnr, line) then return end
  opts = opts or {}
  local config = _config

  -- Handle discontinued packages
  if opts.is_discontinued then
    local disc_text = config.icons.discontinued .. " DISCONTINUED"
    if opts.replacement then
      disc_text = disc_text .. " -> use " .. opts.replacement
    end
    set_virt_text(bufnr, line, disc_text, "PubVersionDiscontinued")
    return
  end

  local upgrade = version_util.upgrade_type(current, latest)
  local text, hl

  if upgrade == "up_to_date" then
    return
  elseif upgrade == "major" then
    text = config.icons.major .. " " .. latest .. " (major)"
    hl = "PubVersionMajor"
  elseif upgrade == "minor" then
    text = config.icons.minor .. " " .. latest .. " (minor)"
    hl = "PubVersionMinor"
  elseif upgrade == "patch" or upgrade == "prerelease" then
    text = config.icons.patch .. " " .. latest .. " (patch)"
    hl = "PubVersionPatch"
  else
    text = " " .. latest
    hl = "Comment"
  end

  set_virt_text(bufnr, line, text, hl)
end

--- Display an error on a dependency line.
---@param bufnr number
---@param line number 0-indexed
---@param msg string
function M.set_error(bufnr, line, msg)
  if not line_valid(bufnr, line) then return end
  set_virt_text(bufnr, line, msg, "DiagnosticError")
end

--- Setup highlight groups and store config reference.
---@param config table
function M.setup_highlights(config)
  _config = config
  vim.api.nvim_set_hl(0, "PubVersionUpToDate", { fg = config.colors.up_to_date, italic = true })
  vim.api.nvim_set_hl(0, "PubVersionMajor", { fg = config.colors.major, bold = true })
  vim.api.nvim_set_hl(0, "PubVersionMinor", { fg = config.colors.minor, italic = true })
  vim.api.nvim_set_hl(0, "PubVersionPatch", { fg = config.colors.patch, italic = true })
  vim.api.nvim_set_hl(0, "PubVersionDiscontinued", { fg = config.colors.discontinued, bold = true, strikethrough = true })
end

return M
