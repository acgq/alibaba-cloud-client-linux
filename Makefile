SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

DMG ?=
DMG_URL ?= https://aliyun-client-assist.oss-accelerate.aliyuncs.com/client/releases/darwin/x64/alibaba-cloud-client-latest.dmg
REFRESH_DMG ?= 0
APP_DIR := $(CURDIR)/alibaba-cloud-client-app

.DEFAULT_GOAL := help

.PHONY: help build-app run pacman deb appimage package check test smoke clean

help:
	@printf '%s\n' \
		'Alibaba Cloud Client for Linux' \
		'' \
		'  make build-app                           Download the official DMG and build' \
		'  make build-app DMG=/path/to/client.dmg  Build from a local DMG instead' \
		'  make run                                Run the generated application' \
		'  make pacman                             Build Arch/Manjaro package' \
		'  make deb                                Build Debian/Ubuntu package' \
		'  make appimage                           Build AppImage' \
		'  make package                            Build pacman, deb and AppImage' \
		'  make check                              Run static checks' \
		'  make test                               Run tests' \
		'  make smoke                              Smoke-test the generated AppImage' \
		'  make clean                              Remove generated files'

build-app:
	ALIBABA_DMG_URL="$(DMG_URL)" ALIBABA_REFRESH_DMG="$(REFRESH_DMG)" \
		./install.sh $(if $(strip $(DMG)),"$(DMG)")

run:
	@[ -x "$(APP_DIR)/start.sh" ] || { echo 'Run make build-app first' >&2; exit 1; }
	"$(APP_DIR)/start.sh"

pacman:
	./scripts/build-pacman.sh

deb:
	./scripts/build-deb.sh

appimage:
	./scripts/build-appimage.sh

package: pacman deb appimage

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
