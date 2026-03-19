V ?= v

.PHONY: build test fmt release

build:
	$(V) -o slower ./cmd/slower/main.v

test:
	$(V) test .

fmt:
	$(V) fmt -w cmd/slower/main.v slowerlib/*.v

release:
	$(V) -prod -o slower ./cmd/slower/main.v
