-- IsKeyIncluded() is genuine public API (addon:IsKeyIncluded), so these call it directly rather
-- than going through an event.

local fw = require("TestFramework")
local Env = require("Env")

fw.describe("MiniPressRelease - IsKeyIncluded", function()
	local env
	local db

	fw.before_each(function()
		env = Env.Build()
		db = _G["MiniPressReleaseCharDB"]
	end)

	fw.it("includes a key that is in the inclusion list when include mode is on", function()
		db.InclusionsEnabled = true
		db.Inclusions["A"] = true

		fw.truthy(env.Addon:IsKeyIncluded("A"), "the key is in the list")
	end)

	fw.it("excludes a key that is not in the inclusion list when include mode is on", function()
		db.InclusionsEnabled = true
		db.Inclusions["A"] = true

		fw.falsy(env.Addon:IsKeyIncluded("B"), "the key is missing from the list")
	end)

	fw.it("excludes a key that is in the exclusion list when exclude mode is on", function()
		db.ExclusionsEnabled = true
		db.Exclusions["A"] = true

		fw.falsy(env.Addon:IsKeyIncluded("A"), "the key is in the exclusion list")
	end)

	fw.it("includes a key that is not in the exclusion list when exclude mode is on", function()
		db.ExclusionsEnabled = true
		db.Exclusions["A"] = true

		fw.truthy(env.Addon:IsKeyIncluded("B"), "the key is missing from the exclusion list")
	end)

	fw.it("includes every key when neither mode is on", function()
		db.InclusionsEnabled = false
		db.ExclusionsEnabled = false

		fw.truthy(env.Addon:IsKeyIncluded("A"), "off means every key passes")
		fw.truthy(env.Addon:IsKeyIncluded("Z"), "off means every key passes, whichever key")
	end)

	-- Both flags can be true at once, since a reset only restores defaults and nothing stops a
	-- saved variables edit from setting both. The inclusion check runs first, so it decides.
	fw.it("lets include mode decide when both modes are somehow on at once", function()
		db.InclusionsEnabled = true
		db.ExclusionsEnabled = true
		db.Inclusions["A"] = true
		db.Exclusions["A"] = true

		fw.truthy(env.Addon:IsKeyIncluded("A"), "inclusion wins even though the same key is also excluded")
	end)
end)
