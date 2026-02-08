set shell := ["bash", "-cu"]

plenary_dir := ".deps/plenary.nvim"
test_init := "tests/minimal_init.lua"

bootstrap-test-deps:
	mkdir -p .deps
	if [ -d "{{plenary_dir}}/.git" ]; then git -C "{{plenary_dir}}" pull --ff-only; else git clone --depth 1 https://github.com/nvim-lua/plenary.nvim "{{plenary_dir}}"; fi

test: bootstrap-test-deps test-unit test-contract

test-unit:
	CODEX_PLENARY_PATH="{{plenary_dir}}" nvim --headless -u "{{test_init}}" -c 'PlenaryBustedFile tests/unit/config_spec.lua' -c 'qa'
	CODEX_PLENARY_PATH="{{plenary_dir}}" nvim --headless -u "{{test_init}}" -c 'PlenaryBustedFile tests/unit/session_store_spec.lua' -c 'qa'
	CODEX_PLENARY_PATH="{{plenary_dir}}" nvim --headless -u "{{test_init}}" -c 'PlenaryBustedFile tests/unit/provider_registry_spec.lua' -c 'qa'

test-contract:
	CODEX_PLENARY_PATH="{{plenary_dir}}" nvim --headless -u "{{test_init}}" -c 'PlenaryBustedFile tests/contract/provider_contract_spec.lua' -c 'qa'

fmt:
	stylua lua plugin tests

fmt-check:
	stylua --check lua plugin tests

lint:
	if [ -f selene.toml ]; then selene --config selene.toml lua plugin tests; else selene lua plugin tests; fi
