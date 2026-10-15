# Despachante de build: macOS usa a aplicação Swift nativa; Linux usa Rust/Tauri.
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Linux)
.PHONY: gen build test test-ci verify-deps run install clean linux-build linux-test linux-run linux-package

gen:
	@echo "No Linux, a interface nativa é a implementação Rust/Tauri em windows/."

build: linux-build

linux-build:
	cd windows && cargo build --release --locked -p notfcode

test: linux-test

test-ci: linux-test

linux-test:
	cd windows && cargo test --locked

verify-deps:
	cd windows && cargo check --locked

run: linux-run

linux-run: linux-build
	./windows/scripts/run-linux.sh

linux-package:
	cd windows/notfcode && npx --yes @tauri-apps/cli@2 build --config tauri.linux.conf.json -- --locked

install: linux-package
	@echo "Pacotes Linux gerados em windows/target/release/bundle/. Instale o .deb ou execute o AppImage conforme sua distribuição."

clean:
	cd windows && cargo clean
else
include Makefile.macos
endif
