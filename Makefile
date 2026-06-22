.PHONY: build run clean install-sysprep install-3x-ui install-selfsteal install-netbird install-all

build: src/dest/selfsteal.sh src/dest/3x-ui-docker.sh

src/dest/selfsteal.sh: src/selfsteal/main.sh src/build.sh $(shell find src/selfsteal src/common -type f -name '*.sh')
	@mkdir -p src/dest
	@echo "Building src/dest/selfsteal.sh..."
	@bash src/build.sh src/selfsteal/main.sh > src/dest/selfsteal.sh
	@chmod +x src/dest/selfsteal.sh

src/dest/3x-ui-docker.sh: src/3x-ui-docker/main.sh src/build.sh
	@mkdir -p src/dest
	@echo "Building src/dest/3x-ui-docker.sh..."
	@bash src/build.sh src/3x-ui-docker/main.sh > src/dest/3x-ui-docker.sh
	@chmod +x src/dest/3x-ui-docker.sh

run: build
	@./src/dest/selfsteal.sh $(ARGS)

clean:
	@rm -rf src/dest
	@rm -f selfsteal.sh

install-sysprep:
	@bash ./sysprep.sh

install-3x-ui: build
	@./src/dest/3x-ui-docker.sh $(ARGS)

install-selfsteal: build
	@./src/dest/selfsteal.sh install $(ARGS)

install-netbird:
	@bash ./netbird.sh menu

install-all: install-sysprep install-3x-ui install-selfsteal

