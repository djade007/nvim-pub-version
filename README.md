# nvim-pub-version

A Neovim plugin that checks your `pubspec.yaml` dependencies against the latest versions on [pub.dev](https://pub.dev), similar to the [Flutter Pub Version Checker](https://plugins.jetbrains.com/plugin/12400-flutter-pub-version-checker) for JetBrains IDEs.

## Features

- Automatically checks dependency versions when opening `pubspec.yaml`
- Displays latest version as virtual text at end of each dependency line
- Color-coded by upgrade type:
  - **Green** -- up to date
  - **Red** -- major update available
  - **Yellow** -- minor update available
  - **Blue** -- patch update available
  - **Strikethrough red** -- discontinued package
- **Quick-fix**: update a single dependency or all outdated deps in one command
- **Hover info**: floating window with package description, homepage, pub.dev link
- **Open on pub.dev**: jump to the package page from your cursor
- **Statusline**: expose `require("pub-version").statusline()` for lualine/heirline
- Async fetching with concurrency limiting (max 5 simultaneous requests)
- In-memory cache with configurable TTL (avoids redundant API calls)
- Debounced checks on save (no duplicate requests on rapid saves)
- Robust parser: handles inline versions, quoted carets, multi-line map form, `dependency_overrides`

## Requirements

- Neovim >= 0.10.0
- `curl` on PATH

## Installation

### lazy.nvim

```lua
{
  "djade007/nvim-pub-version",
  ft = "yaml",
  opts = {},
}
```

## Configuration

Default options:

```lua
require("pub-version").setup({
  auto_check = true,
  cache_ttl = 300,     -- seconds
  debounce_ms = 500,   -- milliseconds
  colors = {
    up_to_date    = "#a6e3a1", -- green
    major         = "#f38ba8", -- red
    minor         = "#f9e2af", -- yellow
    patch         = "#89b4fa", -- blue
    discontinued  = "#f38ba8", -- red
  },
  icons = {
    up_to_date    = "",
    major         = "",
    minor         = "",
    patch         = "",
    discontinued  = "",
  },
  keymaps = {
    enabled    = true,
    update     = "<leader>pu",  -- update dependency under cursor
    update_all = "<leader>pU",  -- update all outdated dependencies
    open       = "<leader>po",  -- open on pub.dev
    check      = "<leader>pc",  -- refresh version check
    info       = "K",            -- show package info float
  },
})
```

## Commands

| Command                  | Description                                |
| ------------------------ | ------------------------------------------ |
| `:PubVersionCheck`       | Check all dependencies for latest versions |
| `:PubVersionClear`       | Clear all version annotations              |
| `:PubVersionUpdate`      | Update dependency under cursor to latest   |
| `:PubVersionUpdateAll`   | Update all outdated dependencies           |
| `:PubVersionOpen`        | Open dependency on pub.dev                 |
| `:PubVersionInfo`        | Show package info in floating window       |
| `:PubVersionClearCache`  | Clear the version cache                    |

## Keymaps

Buffer-local keymaps are set automatically on `pubspec.yaml` files (disable with `keymaps.enabled = false`):

| Key            | Action                        |
| -------------- | ----------------------------- |
| `<leader>pu`   | Update dependency under cursor |
| `<leader>pU`   | Update all outdated deps       |
| `<leader>po`   | Open on pub.dev                |
| `<leader>pc`   | Refresh version check          |
| `K`            | Show package info float        |

## Statusline

```lua
-- lualine example
lualine_x = { require("pub-version").statusline }
```

Shows: `pub: 2 major, 5 minor` or `pub: up to date` (only on `pubspec.yaml` buffers).
