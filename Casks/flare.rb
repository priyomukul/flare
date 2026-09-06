cask "flare" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/priyomukul/flare/releases/download/v#{version}/Flare-#{version}.dmg"
  name "Flare"
  desc "Menu bar app that flashes the screen when an AI agent is waiting on you"
  homepage "https://github.com/priyomukul/flare"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Flare.app"

  # Flare is ad-hoc signed rather than notarised, so Gatekeeper would refuse to
  # open what Homebrew just downloaded. Drop the quarantine flag it sets.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Flare.app"]
  end

  uninstall quit:       "com.priyomukul.flare",
            login_item: "Flare"

  zap trash: [
    "~/Library/Preferences/com.priyomukul.flare.plist",
    "~/Library/Saved Application State/com.priyomukul.flare.savedState",
  ]
end
