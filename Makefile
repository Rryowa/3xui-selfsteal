.PHONY: build run clean

build: dist/selfsteal.sh

dist/selfsteal.sh: src/selfsteal/main.sh build.sh $(shell find src -type f -name '*.sh')
	@mkdir -p dist
	@echo "Building selfsteal.sh..."
	@bash build.sh src/selfsteal/main.sh > dist/selfsteal.sh
	@chmod +x dist/selfsteal.sh

run: build
	@./dist/selfsteal.sh $(ARGS)

clean:
	@rm -rf dist
