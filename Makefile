APP_NAME  := Flare
BUNDLE_ID := com.priyomukul.flare
CONFIG    := release
DIST      := dist
APP       := $(DIST)/$(APP_NAME).app

.PHONY: all build app run stop clean install smoke debug icon dmg release

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
	@cp Resources/Flare.icns "$(APP)/Contents/Resources/Flare.icns"
	@cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	@printf 'APPL????' > "$(APP)/Contents/PkgInfo"
	@codesign --force --sign - --identifier "$(BUNDLE_ID)" "$(APP)"
	@echo "built $(APP)"

run: stop app
	@open "$(APP)"
	@echo "Flare running — look for the beacon in the menu bar"

stop:
	@pkill -x $(APP_NAME) 2>/dev/null || true

## Drag-and-drop installer: dist/Flare-<version>.dmg
dmg: app
	@./scripts/make-dmg.sh

## Cut a GitHub release and attach the DMG, so the Homebrew cask has something
## to download. Requires an authenticated `gh`.
release: dmg
	@VERSION="$$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"; \
	 DMG="dist/Flare-$$VERSION.dmg"; \
	 gh release view "v$$VERSION" >/dev/null 2>&1 \
	   && gh release upload "v$$VERSION" "$$DMG" --clobber \
	   || gh release create "v$$VERSION" "$$DMG" \
	        --title "Flare $$VERSION" \
	        --notes "Drag-and-drop installer. Or: \`brew tap priyomukul/flare https://github.com/priyomukul/flare\` then \`brew install --cask flare\`."; \
	 echo; echo "cask sha256: $$(shasum -a 256 "$$DMG" | cut -d' ' -f1)"

## Rebuild Flare.icns from the 1024pt source. Only needed if the artwork changes.
icon:
	@SET="$$(mktemp -d)/Flare.iconset"; mkdir -p "$$SET"; \
	 for s in 16 32 128 256 512; do \
	   sips -s format png -z $$s $$s Resources/flare-icon-1024.png --out "$$SET/icon_$${s}x$${s}.png" >/dev/null; \
	   sips -s format png -z $$((s*2)) $$((s*2)) Resources/flare-icon-1024.png --out "$$SET/icon_$${s}x$${s}@2x.png" >/dev/null; \
	 done; \
	 iconutil -c icns -o Resources/Flare.icns "$$SET"
	@echo "rebuilt Resources/Flare.icns"

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
