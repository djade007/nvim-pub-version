-- Support both lazy.nvim (local dev) and site/pack (CI) plenary locations
local plenary_paths = {
  vim.fn.expand("$HOME/.local/share/nvim/lazy/plenary.nvim"),
  vim.fn.expand("$HOME/.local/share/nvim/site/pack/vendor/start/plenary.nvim"),
}

for _, path in ipairs(plenary_paths) do
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.rtp:prepend(path)
    break
  end
end

vim.opt.rtp:prepend(".")
vim.cmd("runtime plugin/plenary.vim")
