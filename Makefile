PLENARY := $(HOME)/.local/share/nvim/lazy/plenary.nvim

.PHONY: test test-version test-parser test-cache test-display

test:
	nvim --headless --noplugin \
		-u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

test-version:
	nvim --headless --noplugin \
		-u tests/minimal_init.lua \
		-c "PlenaryBustedFile tests/version_spec.lua"

test-parser:
	nvim --headless --noplugin \
		-u tests/minimal_init.lua \
		-c "PlenaryBustedFile tests/parser_spec.lua"

test-cache:
	nvim --headless --noplugin \
		-u tests/minimal_init.lua \
		-c "PlenaryBustedFile tests/cache_spec.lua"

test-display:
	nvim --headless --noplugin \
		-u tests/minimal_init.lua \
		-c "PlenaryBustedFile tests/display_spec.lua"
