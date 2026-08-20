.PHONY: test restart vm vm-action vm-record vm-logs vm-clean

SWIFT_ENV = CLANG_MODULE_CACHE_PATH=/private/tmp/shot-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/shot-clang-module-cache
SWIFT_PATHS = --cache-path /private/tmp/shot-swiftpm-cache --config-path /private/tmp/shot-swiftpm-config --security-path /private/tmp/shot-swiftpm-security
NAME ?= demo
SECONDS ?= 40

test:
	$(SWIFT_ENV) swift test --disable-sandbox $(SWIFT_PATHS)

restart:
	./scripts/rebuild-and-restart.sh

# Boot a disposable VM with the latest Shot.app for hands-on testing.
vm:
	./scripts/vm.sh interactive

# Start a capture in the running VM when host shortcuts cannot reach the guest.
vm-action:
	./scripts/vm.sh action "$(ACTION)"

# Record the running guest display and save it under ignored recordings/.
vm-record:
	./scripts/vm.sh record "$(NAME)" "$(SECONDS)"

# Print Shot's event log from the running disposable VM.
vm-logs:
	./scripts/vm.sh logs

# Delete disposable Shot test VMs.
vm-clean:
	./scripts/vm.sh clean
