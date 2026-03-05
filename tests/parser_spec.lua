local parser = require("pub-version.parser")

--- Helper: split a multiline string into a table of lines.
local function lines(s)
  local result = {}
  for line in s:gmatch("[^\n]*") do
    table.insert(result, line)
  end
  return result
end

--- Helper: find a dep by name in the result list.
local function find_dep(deps, name)
  for _, d in ipairs(deps) do
    if d.name == name then return d end
  end
  return nil
end

describe("parser", function()
  describe("parse_dependencies", function()
    it("parses basic inline dependencies", function()
      local deps = parser.parse_dependencies(lines([[
name: my_app

dependencies:
  provider: ^6.0.5
  http: ^1.1.0
  path: 1.8.3
]]))
      assert.are.equal(3, #deps)
      assert.are.equal("provider", deps[1].name)
      assert.are.equal("6.0.5", deps[1].version)
      assert.are.equal("http", deps[2].name)
      assert.are.equal("1.1.0", deps[2].version)
      assert.are.equal("path", deps[3].name)
      assert.are.equal("1.8.3", deps[3].version)
    end)

    it("parses quoted caret versions", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  cupertino_icons: '^1.0.2'
  build_runner: "^2.4.0"
]]))
      assert.are.equal(2, #deps)
      assert.are.equal("cupertino_icons", deps[1].name)
      assert.are.equal("1.0.2", deps[1].version)
      assert.are.equal("build_runner", deps[2].name)
      assert.are.equal("2.4.0", deps[2].version)
    end)

    it("parses range constraint versions", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  shared_preferences: ">=2.0.0 <3.0.0"
]]))
      assert.are.equal(1, #deps)
      assert.are.equal("shared_preferences", deps[1].name)
      assert.are.equal("2.0.0", deps[1].version)
    end)

    it("parses versions with build metadata", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  dio: ^5.3.2+1
]]))
      assert.are.equal(1, #deps)
      assert.are.equal("dio", deps[1].name)
      assert.are.equal("5.3.2+1", deps[1].version)
    end)

    it("parses multi-line map form with version key", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  json_annotation:
    version: ^4.8.1
  go_router:
    version: ">=10.0.0 <11.0.0"
]]))
      assert.are.equal(2, #deps)
      assert.are.equal("json_annotation", deps[1].name)
      assert.are.equal("4.8.1", deps[1].version)
      assert.are.equal("go_router", deps[2].name)
      assert.are.equal("10.0.0", deps[2].version)
    end)

    it("skips flutter SDK dependencies", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.5
]]))
      assert.are.equal(1, #deps)
      assert.are.equal("provider", deps[1].name)
    end)

    it("skips flutter_test SDK dependencies", function()
      local deps = parser.parse_dependencies(lines([[
dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.4.2
]]))
      assert.are.equal(1, #deps)
      assert.are.equal("mockito", deps[1].name)
    end)

    it("skips path dependencies", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  some_local:
    path: ../local_pkg
  provider: ^6.0.5
]]))
      assert.are.equal(1, #deps)
      assert.are.equal("provider", deps[1].name)
    end)

    it("skips git dependencies", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  some_git_dep:
    git:
      url: https://github.com/user/repo
  provider: ^6.0.5
]]))
      assert.are.equal(1, #deps)
      assert.are.equal("provider", deps[1].name)
    end)

    it("parses dev_dependencies", function()
      local deps = parser.parse_dependencies(lines([[
dev_dependencies:
  flutter_lints: ^3.0.1
  mockito: ^5.4.2
]]))
      assert.are.equal(2, #deps)
      assert.are.equal("flutter_lints", deps[1].name)
      assert.are.equal("mockito", deps[2].name)
    end)

    it("parses dependency_overrides", function()
      local deps = parser.parse_dependencies(lines([[
dependency_overrides:
  http: 1.2.0
]]))
      assert.are.equal(1, #deps)
      assert.are.equal("http", deps[1].name)
      assert.are.equal("1.2.0", deps[1].version)
    end)

    it("handles all three sections in one file", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  provider: ^6.0.5

dev_dependencies:
  mockito: ^5.4.2

dependency_overrides:
  http: 1.2.0
]]))
      assert.are.equal(3, #deps)
      assert.are.equal("provider", deps[1].name)
      assert.are.equal("mockito", deps[2].name)
      assert.are.equal("http", deps[3].name)
    end)

    it("stops dependency block at new top-level key", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  provider: ^6.0.5

flutter:
  uses-material-design: true
]]))
      assert.are.equal(1, #deps)
    end)

    it("ignores comments within dependency blocks", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  # This is a comment
  provider: ^6.0.5
  # Another comment
  http: ^1.1.0
]]))
      assert.are.equal(2, #deps)
    end)

    it("ignores blank lines within dependency blocks", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  provider: ^6.0.5

  http: ^1.1.0
]]))
      assert.are.equal(2, #deps)
    end)

    it("does not confuse top-level comments as block terminators", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  provider: ^6.0.5
# a top-level comment
  http: ^1.1.0
]]))
      -- The comment at col 0 without leading space, but starts with #
      -- so it should NOT terminate the deps block
      assert.are.equal(2, #deps)
    end)

    it("assigns correct 0-indexed line numbers", function()
      -- Line 0: "dependencies:"
      -- Line 1: "  provider: ^6.0.5"
      -- Line 2: "  http: ^1.1.0"
      local deps = parser.parse_dependencies({
        "dependencies:",
        "  provider: ^6.0.5",
        "  http: ^1.1.0",
      })
      assert.are.equal(1, deps[1].line)
      assert.are.equal(2, deps[2].line)
    end)

    it("assigns line number to name line for multi-line deps", function()
      local deps = parser.parse_dependencies({
        "dependencies:",
        "  json_annotation:",
        "    version: ^4.8.1",
      })
      assert.are.equal(1, deps[1].line) -- points to `json_annotation:` line
    end)

    it("handles custom skip list", function()
      local deps = parser.parse_dependencies(lines([[
dependencies:
  provider: ^6.0.5
  custom_skip: ^1.0.0
]]), { custom_skip = true })
      assert.are.equal(1, #deps)
      assert.are.equal("provider", deps[1].name)
    end)

    it("returns empty table for no dependencies", function()
      local deps = parser.parse_dependencies(lines([[
name: my_app
version: 1.0.0
]]))
      assert.are.equal(0, #deps)
    end)

    it("returns empty table for empty input", function()
      local deps = parser.parse_dependencies({})
      assert.are.equal(0, #deps)
    end)

    it("handles a realistic full pubspec", function()
      local deps = parser.parse_dependencies(lines([[
name: my_app
description: A test app
version: 1.0.0

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.5
  http: ^1.1.0
  shared_preferences: ">=2.0.0 <3.0.0"
  path: 1.8.3
  dio: ^5.3.2+1
  flutter_bloc: ^8.1.3
  cupertino_icons: '^1.0.2'
  json_annotation:
    version: ^4.8.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.1
  mockito: ^5.4.2

dependency_overrides:
  http: 1.2.0

flutter:
  uses-material-design: true
]]))
      -- provider, http, shared_preferences, path, dio, flutter_bloc,
      -- cupertino_icons, json_annotation, flutter_lints, mockito, http (override)
      assert.are.equal(11, #deps)

      local provider = find_dep(deps, "provider")
      assert.is_not_nil(provider)
      assert.are.equal("6.0.5", provider.version)

      local dio = find_dep(deps, "dio")
      assert.is_not_nil(dio)
      assert.are.equal("5.3.2+1", dio.version)

      local json = find_dep(deps, "json_annotation")
      assert.is_not_nil(json)
      assert.are.equal("4.8.1", json.version)
    end)
  end)

  describe("_extract_inline", function()
    it("extracts bare version", function()
      local name, ver = parser._extract_inline("  path: 1.8.3")
      assert.are.equal("path", name)
      assert.are.equal("1.8.3", ver)
    end)

    it("extracts caret version", function()
      local name, ver = parser._extract_inline("  provider: ^6.0.5")
      assert.are.equal("provider", name)
      assert.are.equal("6.0.5", ver)
    end)

    it("extracts quoted caret version (single quotes)", function()
      local name, ver = parser._extract_inline("  cupertino_icons: '^1.0.2'")
      assert.are.equal("cupertino_icons", name)
      assert.are.equal("1.0.2", ver)
    end)

    it("extracts quoted caret version (double quotes)", function()
      local name, ver = parser._extract_inline('  build_runner: "^2.4.0"')
      assert.are.equal("build_runner", name)
      assert.are.equal("2.4.0", ver)
    end)

    it("extracts range constraint (takes first version)", function()
      local name, ver = parser._extract_inline('  shared_preferences: ">=2.0.0 <3.0.0"')
      assert.are.equal("shared_preferences", name)
      assert.are.equal("2.0.0", ver)
    end)

    it("extracts version with build metadata", function()
      local name, ver = parser._extract_inline("  dio: ^5.3.2+1")
      assert.are.equal("dio", name)
      assert.are.equal("5.3.2+1", ver)
    end)

    it("returns nil version for name-only line", function()
      local name, ver = parser._extract_inline("  json_annotation:")
      assert.is_nil(name)
      assert.is_nil(ver)
    end)

    it("returns nil version for 'any'", function()
      local name, ver = parser._extract_inline("  some_pkg: any")
      assert.are.equal("some_pkg", name)
      assert.is_nil(ver)
    end)

    it("returns nil for non-dependency lines", function()
      local name, ver = parser._extract_inline("name: my_app")
      assert.is_nil(name)
      assert.is_nil(ver)
    end)
  end)
end)
