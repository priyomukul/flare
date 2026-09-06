APP_NAME  := Flare
BUNDLE_ID := com.priyomukul.flare
CONFIG    := release
DIST      := dist
APP       := $(DIST)/$(APP_NAME).app

.PHONY: all build app run stop clean install smoke debug

all: app

build:
	swift build -c $(CONFIG)

## Assemble Flare.app (LSUIElement, ad-hoc signed) from the built binary.
app: build
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@BIN="$$(swift build -c $(CONFIG) --show-bin-path)/$(APP_NAME)"; \
	 test -x "$$BIN" || { echo "missing binary: $$BIN"; exit 1; }; \
	 cp "$$BIN" "$(APP)/Contents/MacOS/$(APP_NAME)"
	@cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	@printf 'APPL????' > "$(APP)/Contents/PkgInfo"
	@codesign --force --sign - --identifier "$(BUNDLE_ID)" "$(APP)"
	@echo "built $(APP)"

run: stop app
	@open "$(APP)"
	@echo "Flare running — look for the beacon in the menu bar"

stop:
	@pkill -x $(APP_NAME) 2>/dev/null || true

## A debug build in the same bundle layout, for symbolicated crashes.
debug:
	@$(MAKE) CONFIG=debug app

## Move to /Applications, which is where login-at-launch registration is reliable.
## Depends on stop: copying over a running app would otherwise leave two Flares,
## and whichever loses the race for the port sits there retrying.
install: stop app
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R "$(APP)" /Applications/
	@echo "installed /Applications/$(APP_NAME).app"

smoke:
	@./scripts/smoke.sh

clean:
	@rm -rf .build "$(DIST)"
