cask "unifiedbuds" do
  version "0.3.0"
  sha256 :no_check

  url "https://github.com/amitdeb9/unifiedbuds-macos/releases/download/v#{version}/UnifiedBuds.dmg"
  name "UnifiedBuds"
  desc "macOS menu bar app for wireless earbuds: battery, noise control, EQ presets, and shortcuts"
  homepage "https://github.com/amitdeb9/unifiedbuds-macos"

  depends_on macos: ">= :ventura"

  app "UnifiedBuds.app"

  zap trash: [
    "~/Library/Preferences/com.unifiedbuds.app.plist",
  ]
end
