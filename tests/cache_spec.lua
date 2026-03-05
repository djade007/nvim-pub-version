local cache = require("pub-version.cache")

describe("cache", function()
  before_each(function()
    cache.clear()
  end)

  describe("set and get", function()
    it("stores and retrieves an entry", function()
      cache.set("provider", {
        version = "6.1.5",
        is_discontinued = false,
      })
      local entry = cache.get("provider")
      assert.is_not_nil(entry)
      assert.are.equal("6.1.5", entry.version)
      assert.are.equal(false, entry.is_discontinued)
    end)

    it("returns nil for missing entries", function()
      assert.is_nil(cache.get("nonexistent"))
    end)

    it("stores multiple entries independently", function()
      cache.set("provider", { version = "6.1.5", is_discontinued = false })
      cache.set("http", { version = "1.2.0", is_discontinued = false })

      local p = cache.get("provider")
      local h = cache.get("http")
      assert.are.equal("6.1.5", p.version)
      assert.are.equal("1.2.0", h.version)
    end)

    it("overwrites existing entry", function()
      cache.set("provider", { version = "6.0.5", is_discontinued = false })
      cache.set("provider", { version = "6.1.5", is_discontinued = false })

      local entry = cache.get("provider")
      assert.are.equal("6.1.5", entry.version)
    end)

    it("sets fetched_at automatically", function()
      cache.set("provider", { version = "6.1.5", is_discontinued = false })
      local entry = cache.get("provider")
      assert.is_not_nil(entry.fetched_at)
      assert.is_true(entry.fetched_at > 0)
    end)
  end)

  describe("TTL expiration", function()
    it("returns nil for expired entries", function()
      cache.set("provider", { version = "6.1.5", is_discontinued = false })
      -- Backdate fetched_at to simulate expiration
      cache.get("provider").fetched_at = os.time() - 400
      local entry = cache.get("provider", 300)
      assert.is_nil(entry)
    end)

    it("returns entry within TTL", function()
      cache.set("provider", { version = "6.1.5", is_discontinued = false })
      local entry = cache.get("provider", 300)
      assert.is_not_nil(entry)
    end)

    it("respects custom TTL", function()
      cache.set("provider", { version = "6.1.5", is_discontinued = false })
      -- Backdate by 2 seconds, then use 1s TTL
      cache.get("provider").fetched_at = os.time() - 2
      local entry = cache.get("provider", 1)
      assert.is_nil(entry)
    end)
  end)

  describe("clear", function()
    it("removes all entries", function()
      cache.set("provider", { version = "6.1.5", is_discontinued = false })
      cache.set("http", { version = "1.2.0", is_discontinued = false })
      assert.are.equal(2, cache.size())

      cache.clear()
      assert.are.equal(0, cache.size())
      assert.is_nil(cache.get("provider"))
      assert.is_nil(cache.get("http"))
    end)
  end)

  describe("size", function()
    it("returns 0 for empty cache", function()
      assert.are.equal(0, cache.size())
    end)

    it("returns correct count", function()
      cache.set("a", { version = "1.0.0", is_discontinued = false })
      cache.set("b", { version = "2.0.0", is_discontinued = false })
      cache.set("c", { version = "3.0.0", is_discontinued = false })
      assert.are.equal(3, cache.size())
    end)

    it("does not double-count overwrites", function()
      cache.set("a", { version = "1.0.0", is_discontinued = false })
      cache.set("a", { version = "2.0.0", is_discontinued = false })
      assert.are.equal(1, cache.size())
    end)
  end)

  describe("stores metadata fields", function()
    it("stores discontinued info", function()
      cache.set("old_pkg", {
        version = "1.0.0",
        is_discontinued = true,
        replacement = "new_pkg",
      })
      local entry = cache.get("old_pkg")
      assert.is_true(entry.is_discontinued)
      assert.are.equal("new_pkg", entry.replacement)
    end)

    it("stores description and homepage", function()
      cache.set("provider", {
        version = "6.1.5",
        is_discontinued = false,
        description = "A wrapper around InheritedWidget",
        homepage = "https://github.com/rrousselGit/provider",
      })
      local entry = cache.get("provider")
      assert.are.equal("A wrapper around InheritedWidget", entry.description)
      assert.are.equal("https://github.com/rrousselGit/provider", entry.homepage)
    end)
  end)
end)
