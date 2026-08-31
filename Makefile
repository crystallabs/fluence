PREFIX=/usr/local
INSTALL_DIR=$(PREFIX)/bin
PROGRAM_SYSTEM=$(INSTALL_DIR)/fluence

OUT_DIR=$(shell pwd)/bin
PROGRAM=$(OUT_DIR)/fluence
PROGRAM_SOURCES=$(shell find src/ -type f -name '*.cr')

all: build

build: lib $(PROGRAM)

lib:
	@shards install --production

$(PROGRAM): $(PROGRAM_SOURCES) | $(OUT_DIR)
	@echo "Building fluence in $@"
	@crystal build -o $@ src/fluence.cr -p --no-debug

$(OUT_DIR) $(INSTALL_DIR):
	 @mkdir -p $@

.PHONY: release run install link force_link clean distclean lint test

release: $(PROGRAM_SOURCES) | $(OUT_DIR)
	@echo "Building fluence for release in $(PROGRAM)"
	@crystal build -p --no-debug --release -o $(PROGRAM) src/fluence.cr

run:
	$(PROGRAM)

install: build | $(INSTALL_DIR)
	@rm -f $(PROGRAM_SYSTEM)
	@cp $(PROGRAM) $(PROGRAM_SYSTEM)

link: build | $(INSTALL_DIR)
	@echo "Symlinking $(PROGRAM) to $(PROGRAM_SYSTEM)"
	@ln -s $(PROGRAM) $(PROGRAM_SYSTEM)

force_link: build | $(INSTALL_DIR)
	@echo "Symlinking $(PROGRAM) to $(PROGRAM_SYSTEM)"
	@ln -sf $(PROGRAM) $(PROGRAM_SYSTEM)

clean:
	rm -rf $(PROGRAM)

distclean:
	rm -rf $(PROGRAM) .crystal .shards libs lib

bin/ameba: | $(OUT_DIR)
	@crystal build lib/ameba/src/cli.cr -o bin/ameba

lint: bin/ameba
	bin/ameba

test:
	crystal spec
