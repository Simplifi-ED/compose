BUILD_CONFIGURATION ?= release
WARNINGS_AS_ERRORS ?= true
SWIFT ?= /usr/bin/swift
SWIFT_FLAGS := $(if $(filter-out false,$(WARNINGS_AS_ERRORS)),-Xswiftc -warnings-as-errors)

.PHONY: build lint test dist clean

build:
	$(SWIFT) build -c $(BUILD_CONFIGURATION) $(SWIFT_FLAGS)

lint:
	./scripts/lint.sh

test:
	$(SWIFT) run -c release compose-verify

dist:
	./scripts/package.sh
	tar -czf dist/compose-plugin.tar.gz -C dist/compose .

clean:
	@rm -rf .build dist
