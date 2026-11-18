.PHONY: help validate build test release install-global uninstall-global install-project uninstall-project config-show clean

VERSION := $(shell cat VERSION)
DIR ?=

help:
	@echo "Pilotfish for Antigravity (v$(VERSION))"
	@echo ""
	@echo "Targets:"
	@echo "  make validate                      Validate plugin manifest, config, rules, skill, and agent invariants"
	@echo "  make build                         Build clean plugin bundle into dist/pilotfish-agy/"
	@echo "  make test                          Run automated validation, install & configure tests"
	@echo "  make release                       Build, test, and package .tar.gz, .zip, portable kit, SHA256SUMS"
	@echo "  make install-global                Install into ~/.gemini/config/plugins/pilotfish-agy"
	@echo "  make uninstall-global              Remove from ~/.gemini/config/plugins/pilotfish-agy"
	@echo "  make install-project DIR=/path     Install into <DIR>/.agents/plugins/pilotfish-agy"
	@echo "  make uninstall-project DIR=/path   Remove from <DIR>/.agents/plugins/pilotfish-agy"
	@echo "  make config-show                   Show current global pilotfish-agy configuration"
	@echo "  make clean                         Remove dist/ build and release artifacts"

validate:
	@bash scripts/validate.sh plugin

build:
	@bash scripts/build.sh --sync-version

test:
	@bash tests/test-plugin.sh

release:
	@bash scripts/release.sh

install-global: build
	@bash scripts/install.sh --global

uninstall-global:
	@bash scripts/install.sh --global --uninstall

install-project: build
	@test -n "$(DIR)" || (echo "Error: pass DIR=/path/to/project"; exit 1)
	@bash scripts/install.sh --project "$(DIR)"

uninstall-project:
	@test -n "$(DIR)" || (echo "Error: pass DIR=/path/to/project"; exit 1)
	@bash scripts/install.sh --project "$(DIR)" --uninstall

config-show:
	@bash scripts/configure.sh --global --show

clean:
	@rm -rf dist
