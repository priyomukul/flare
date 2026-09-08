cask "flare" do
  version "1.0.1"
  sha256 "bf41cc3a9f974daed760b9f9f72b811b82a245bdb2774934244e682f828b4e80"

  url "https://github.com/priyomukul/flare/releases/download/v#{version}/Flare-#{version}.dmg"
  name "Flare"
  desc "Menu bar app that flashes the screen when an AI agent is waiting on you"
  homepage "https://github.com/priyomukul/flare"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Flare.app"

  # Flare is ad-hoc signed rather than notarised, so Gatekeeper would refuse to
  # open what Homebrew just downloaded. Drop the quarantine flag it sets.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Flare.app"],
        writable_paths: ["{{appdir}}/Flare.app"],
        must_succeed:   false
  end

  uninstall quit:       "com.priyomukul.flare",
            login_item: "Flare"

  zap trash: [
    "~/Library/Preferences/com.priyomukul.flare.plist",
    "~/Library/Saved Application State/com.priyomukul.flare.savedState",
  ]
end
