set shell := ["bash", "-cu"]

plenary_dir := ".deps/plenary.nvim"
test_init := "tests/minimal_init.lua"

bootstrap-test-deps:
	mkdir -p .deps
	if [ -d "{{plenary_dir}}/.git" ]; then git -C "{{plenary_dir}}" pull --ff-only; else git clone --depth 1 https://github.com/nvim-lua/plenary.nvim "{{plenary_dir}}"; fi

test: bootstrap-test-deps test-unit test-contract

test-unit:
	for f in tests/unit/*_spec.lua; do CODEX_PLENARY_PATH="{{plenary_dir}}" nvim --headless -u "{{test_init}}" -c "PlenaryBustedFile $f" -c 'qa'; done

test-contract:
	CODEX_PLENARY_PATH="{{plenary_dir}}" nvim --headless -u "{{test_init}}" -c 'PlenaryBustedFile tests/contract/provider_contract_spec.lua' -c 'qa'

fmt:
	stylua lua plugin tests
	mdformat --number docs/ README.md

fmt-check:
	stylua --check lua plugin tests
	mdformat --number --check docs/ README.md

lint:
	if [ -f selene.toml ]; then selene --config selene.toml lua plugin tests; else selene lua plugin tests; fi

pre-commit-install:
	mise install aqua:pre-commit/pre-commit
	mise exec -- pre-commit install --hook-type pre-commit --hook-type commit-msg

pre-commit-run:
	mise exec -- pre-commit run --all-files
