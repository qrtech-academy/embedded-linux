SHELL := /bin/bash

# Absolute path to this Makefile's directory, so the targets work from anywhere.
ROOT := $(dir $(firstword $(MAKEFILE_LIST)))

PYTHON := $(ROOT).venv/bin/python

.DEFAULT_GOAL := help
.PHONY: help env kernel rootfs qemu build test boot check lint links markdown \
        format format-check diagrams clean

help: ## Show this help.
	@echo "Targets:"
	@grep -hE '^[a-z-]+:.*##' $(MAKEFILE_LIST) \
	  | sed -e 's/:.*## / /' -e 's/^/  /' \
	  | awk '{ printf "  %-18s %s\n", $$1, substr($$0, index($$0, $$2)) }'
	@echo
	@echo "Narrow a target to one lecture:"
	@echo "  make test L=L06"
	@echo
	@echo "First time through, in order:"
	@echo "  make env kernel qemu rootfs boot"

# The four targets below build the machine the course runs on. None of them is quick, all of
# them are cached, and each one prints what it would do before it does it.
env: ## Build the container image with the cross toolchain, QEMU and kernel build deps.
	$(ROOT)ci/env.sh

qemu: ## Build qemu-system-aarch64 with the qa-dev device model patched in.
	$(ROOT)ci/qemu.sh

kernel: ## Cross-build the arm64 kernel and its modules. Optional: RT=1
	$(ROOT)ci/kernel.sh

rootfs: ## Build the BusyBox initramfs the target boots into.
	$(ROOT)ci/rootfs.sh

build: ## Build every lecture lab module that has been written. Optional: L=L04
	$(ROOT)ci/build.sh $(L)

test: ## Boot each lecture's lab in QEMU and run its tests. Optional: L=L05
	$(ROOT)ci/test.sh $(L)

boot: ## Boot the target in QEMU and drop to an interactive shell. Ctrl-A X to quit.
	$(ROOT)ci/boot.sh

# Deliberately not part of test, and never compared against a committed file: the numbers it
# prints are properties of the machine it ran on, under an emulator that is not a real-time
# host. L10's appendix records one run, names the machine, and says what that run is and is
# not evidence of.
check: ## Run the golden programs and diff their output against what is committed.
	$(ROOT)ci/check.sh

# Mirrors the CI lint job exactly, so a green "make lint" locally means a green lint in CI.
lint: links markdown format-check ## Run every check that needs no compiler.

links: ## Check that every relative Markdown link resolves.
	$(ROOT)ci/links.sh

markdown: ## Check the Markdown house rules: alt text, wrapping, headings, math fences.
	$(ROOT)ci/markdown.sh

format: ## Format the C with clang-format and the Python with black, in place.
	$(ROOT)ci/format.sh

format-check: ## Fail if any C or Python source is unformatted.
	$(ROOT)ci/format.sh --check

diagrams: ## Regenerate every figure into lectures/*/appendix/images.
	$(ROOT)ci/diagrams.sh

clean: ## Remove build products. Does not remove the kernel tree or the container image.
	$(ROOT)ci/clean.sh
