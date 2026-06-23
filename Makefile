.PHONY: build run clean install-sysprep install-3x-ui install-selfsteal install-netbird install-all

build: src/dest/selfsteal.sh src/dest/3x-ui-docker.sh

src/dest/selfsteal.sh: src/selfsteal/main.sh src/build.sh xhttp-client-import.json $(shell find src/selfsteal src/common -type f -name '*.sh')
	@mkdir -p src/dest
	@echo "Building src/dest/selfsteal.sh..."
	@echo -n "XHTTP_JSON_TEMPLATE='" > src/selfsteal/xhttp_template.sh
	@cat xhttp-client-import.json >> src/selfsteal/xhttp_template.sh
	@echo "'" >> src/selfsteal/xhttp_template.sh
	@bash src/build.sh src/selfsteal/main.sh > src/dest/selfsteal.sh
	@chmod +x src/dest/selfsteal.sh

src/dest/3x-ui-docker.sh: src/3x-ui-docker/main.sh src/build.sh
	@mkdir -p src/dest
	@echo "Building src/dest/3x-ui-docker.sh..."
	@bash src/build.sh src/3x-ui-docker/main.sh > src/dest/3x-ui-docker.sh
	@chmod +x src/dest/3x-ui-docker.sh

clean:
	@rm -rf src/dest
	@rm -f selfsteal.sh

sysprep:
	@bash ./sysprep.sh

3x-ui: build
	@./src/dest/3x-ui-docker.sh $(ARGS)

selfsteal: build
	@./src/dest/selfsteal.sh install $(ARGS)

netbird:
	@bash ./netbird.sh menu

all: 3x-ui selfsteal

