BUILD_CONFIGURATION ?= release
WARNINGS_AS_ERRORS ?= true
SWIFT ?= /usr/bin/swift
SWIFT_FLAGS := $(if $(filter-out false,$(WARNINGS_AS_ERRORS)),-Xswiftc -warnings-as-errors)

.PHONY: build lint test dist smoke smoke-volumes smoke-volumes-named smoke-networks clean

build:
	$(SWIFT) build -c $(BUILD_CONFIGURATION) $(SWIFT_FLAGS)

lint:
	./scripts/lint.sh

test:
	$(SWIFT) run -c release compose-verify

dist:
	./scripts/package.sh
	tar -czf dist/compose-plugin.tar.gz -C dist/compose .
	cd dist/compose && zip -r ../container-compose-macos-arm64.zip .

smoke:
	./scripts/smoke-test.sh

smoke-volumes: ## install plugin + live :ro/:z bind-mount runtime checks
	bash ./scripts/install.sh
	bash ./scripts/smoke-volume-mounts.sh

smoke-networks: ## install plugin + live compose networks runtime checks (macOS 26+)
	bash ./scripts/install.sh
	bash ./scripts/smoke-networks.sh

smoke-volumes-named: ## install plugin + live compose named volume runtime checks
	bash ./scripts/install.sh
	bash ./scripts/smoke-named-volumes.sh

clean:
	@rm -rf .build dist
