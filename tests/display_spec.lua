local display = require("pub-version.display")

local config = {
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
}

--- Helper: create a buffer with given lines.
local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

--- Helper: get all extmarks in a buffer namespace.
local function get_extmarks(bufnr)
  local ns = vim.api.nvim_create_namespace("pub_version_checker")
  return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
end

describe("display", function()
  local bufnr

  before_each(function()
    display.setup_highlights(config)
    bufnr = make_buf({
      "dependencies:",
      "  provider: ^6.0.5",
      "  http: ^1.1.0",
      "  old_pkg: ^1.0.0",
    })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe("set_loading", function()
    it("adds virtual text with 'fetching...'", function()
      display.set_loading(bufnr, 1)
      local marks = get_extmarks(bufnr)
      assert.are.equal(1, #marks)
      local details = marks[1][4]
      assert.are.equal("  fetching...", details.virt_text[1][1])
    end)

    it("clears existing extmarks before adding", function()
      display.set_loading(bufnr, 1)
      display.set_loading(bufnr, 1)
      local marks = get_extmarks(bufnr)
      assert.are.equal(1, #marks) -- not 2
    end)

    it("does nothing for invalid buffer", function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
      -- Should not error
      display.set_loading(bufnr, 1)
    end)

    it("does nothing for out-of-range line", function()
      -- Buffer has 4 lines (0-3), line 10 is out of range
      display.set_loading(bufnr, 10)
      local marks = get_extmarks(bufnr)
      assert.are.equal(0, #marks)
    end)
  end)

  describe("set_result", function()
    it("shows up-to-date for equal versions", function()
      display.set_result(bufnr, 1, "6.0.5", "6.0.5")
      local marks = get_extmarks(bufnr)
      assert.are.equal(1, #marks)
      local text = marks[1][4].virt_text[1][1]
      local hl = marks[1][4].virt_text[1][2]
      assert.is_truthy(text:find("6.0.5"))
      assert.are.equal("PubVersionUpToDate", hl)
    end)

    it("shows major update", function()
      display.set_result(bufnr, 1, "5.0.0", "6.0.0")
      local marks = get_extmarks(bufnr)
      local text = marks[1][4].virt_text[1][1]
      local hl = marks[1][4].virt_text[1][2]
      assert.is_truthy(text:find("major"))
      assert.are.equal("PubVersionMajor", hl)
    end)

    it("shows minor update", function()
      display.set_result(bufnr, 1, "6.0.5", "6.1.5")
      local marks = get_extmarks(bufnr)
      local text = marks[1][4].virt_text[1][1]
      local hl = marks[1][4].virt_text[1][2]
      assert.is_truthy(text:find("minor"))
      assert.are.equal("PubVersionMinor", hl)
    end)

    it("shows patch update", function()
      display.set_result(bufnr, 1, "6.0.5", "6.0.6")
      local marks = get_extmarks(bufnr)
      local text = marks[1][4].virt_text[1][1]
      local hl = marks[1][4].virt_text[1][2]
      assert.is_truthy(text:find("patch"))
      assert.are.equal("PubVersionPatch", hl)
    end)

    it("shows discontinued package", function()
      display.set_result(bufnr, 3, "1.0.0", "1.0.0", { is_discontinued = true, replacement = "new_pkg" })
      local marks = get_extmarks(bufnr)
      local text = marks[1][4].virt_text[1][1]
      local hl = marks[1][4].virt_text[1][2]
      assert.is_truthy(text:find("DISCONTINUED"))
      assert.is_truthy(text:find("new_pkg"))
      assert.are.equal("PubVersionDiscontinued", hl)
    end)

    it("shows discontinued without replacement", function()
      display.set_result(bufnr, 3, "1.0.0", "1.0.0", { is_discontinued = true })
      local marks = get_extmarks(bufnr)
      local text = marks[1][4].virt_text[1][1]
      assert.is_truthy(text:find("DISCONTINUED"))
      assert.is_falsy(text:find("use"))
    end)

    it("replaces existing extmark on same line", function()
      display.set_loading(bufnr, 1)
      display.set_result(bufnr, 1, "6.0.5", "6.1.5")
      local marks = get_extmarks(bufnr)
      -- Should have exactly 1 mark, not 2
      local count = 0
      for _, m in ipairs(marks) do
        if m[2] == 1 then count = count + 1 end
      end
      assert.are.equal(1, count)
    end)

    it("does nothing for out-of-range line", function()
      display.set_result(bufnr, 10, "1.0.0", "2.0.0")
      local marks = get_extmarks(bufnr)
      assert.are.equal(0, #marks)
    end)
  end)

  describe("set_error", function()
    it("shows error message", function()
      display.set_error(bufnr, 1, "Failed to fetch")
      local marks = get_extmarks(bufnr)
      assert.are.equal(1, #marks)
      local text = marks[1][4].virt_text[1][1]
      local hl = marks[1][4].virt_text[1][2]
      assert.is_truthy(text:find("Failed to fetch"))
      assert.are.equal("DiagnosticError", hl)
    end)

    it("does nothing for out-of-range line", function()
      display.set_error(bufnr, 10, "error")
      local marks = get_extmarks(bufnr)
      assert.are.equal(0, #marks)
    end)
  end)

  describe("clear", function()
    it("removes all extmarks", function()
      display.set_loading(bufnr, 1)
      display.set_loading(bufnr, 2)
      display.set_result(bufnr, 3, "1.0.0", "2.0.0")

      display.clear(bufnr)
      local marks = get_extmarks(bufnr)
      assert.are.equal(0, #marks)
    end)

    it("does nothing for invalid buffer", function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
      -- Should not error
      display.clear(bufnr)
    end)
  end)

  describe("setup_highlights", function()
    it("creates highlight groups", function()
      display.setup_highlights(config)
      -- Verify highlight groups exist by checking they don't error
      local hl = vim.api.nvim_get_hl(0, { name = "PubVersionUpToDate" })
      assert.is_not_nil(hl.fg)
      local hl2 = vim.api.nvim_get_hl(0, { name = "PubVersionMajor" })
      assert.is_not_nil(hl2.fg)
      assert.is_true(hl2.bold)
    end)

    it("updates highlight groups on re-call", function()
      display.setup_highlights(config)
      local custom = vim.tbl_deep_extend("force", config, {
        colors = { up_to_date = "#ff0000" },
      })
      display.setup_highlights(custom)
      local hl = vim.api.nvim_get_hl(0, { name = "PubVersionUpToDate" })
      -- #ff0000 = 16711680
      assert.are.equal(0xff0000, hl.fg)
    end)
  end)
end)
