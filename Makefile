SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

DMG ?=
APP_DIR := $(CURDIR)/alibaba-cloud-client-app

.DEFAULT_GOAL := help

.PHONY: help build-app run pacman appimage package check test smoke clean

help:
	@printf '%s\n' \
		'Alibaba Cloud Client for Linux' \
		'' \
		'  make build-app DMG=/path/to/client.dmg  Build the Linux application' \
		'  make run                                Run the generated application' \
		'  make pacman                             Build Arch/Manjaro package' \
		'  make appimage                           Build AppImage' \
		'  make package                            Build pacman package and AppImage' \
		'  make check                              Run static checks' \
		'  make test                               Run tests' \
		'  make smoke                              Smoke-test the generated AppImage' \
		'  make clean                              Remove generated files'

build-app:
	./install.sh $(if $(strip $(DMG)),"$(DMG)")

run:
	@[ -x "$(APP_DIR)/start.sh" ] || { echo 'Run make build-app first' >&2; exit 1; }
	"$(APP_DIR)/start.sh"

pacman:
	./scripts/build-pacman.sh

appimage:
	./scripts/build-appimage.sh

package: pacman appimage

check:
	bash -n install.sh scripts/*.sh scripts/lib/*.sh launcher/start.sh.template packaging/appimage/AppRun
	node --check scripts/patch-linux.js
	node --check scripts/test-patches.js

test: check
	node --test scripts/test-patches.js
	bash tests/scripts-smoke.sh

smoke:
	./scripts/smoke-appimage.sh

clean:
	rm -rf "$(CURDIR)/build" "$(CURDIR)/dist" "$(APP_DIR)"
