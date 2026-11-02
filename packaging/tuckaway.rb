# Homebrew cask for Tuckaway. It lives in the tap repository
# Bruno-Alumn/homebrew-tuckaway (Casks/tuckaway.rb); this copy is the source.
# scripts/update-cask.sh sets the version and sha256 from the latest release.
cask "tuckaway" do
  version "1.8.0"
  sha256 "9ecfbe3208c18c809fdcf9fe05a38cca13075e226ca9d35cf77a13dbfbcbdf30"

  url "https://github.com/Bruno-Alumn/Tuckaway/releases/download/v#{version}/Tuckaway.dmg"
  name "Tuckaway"
  desc "Hide menu bar icons without quitting their apps"
  homepage "https://github.com/Bruno-Alumn/Tuckaway"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The app updates itself from GitHub releases.
  auto_updates true
  depends_on macos: :ventura

  app "Tuckaway.app"

  uninstall quit: "com.brunoalumn.tuckaway"

  zap trash: [
    "~/Library/Caches/com.brunoalumn.tuckaway",
    "~/Library/Containers/com.brunoalumn.tuckaway",
    "~/Library/HTTPStorages/com.brunoalumn.tuckaway",
    "~/Library/Preferences/com.brunoalumn.tuckaway.plist",
  ]

  caveats <<~EOS
    Tuckaway isn't notarized by Apple. The first time you open it, macOS
    asks whether to open it: choose Open, or allow it in System Settings →
    Privacy & Security → Open Anyway.

    Tuckaway needs Accessibility access (Device Control and Data Access on
    macOS 27) to find and move menu bar icons. It asks on first launch.
  EOS
end
