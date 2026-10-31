cask "tuckaway" do
  version "1.2.0"
  sha256 "15c1211144c57e0f177ed768b23247ce0a98772331ba93ef1d6cb252ee26f422"

  url "https://github.com/Bruno-Alumn/Tuckaway/releases/download/v#{version}/Tuckaway.dmg"
  name "Tuckaway"
  desc "Menu bar tidying without quitting apps"
  homepage "https://github.com/Bruno-Alumn/Tuckaway"

  depends_on macos: ">= 13"

  app "Tuckaway.app"

  caveats <<~EOS
    Tuckaway requires Accessibility permission (Device Control and Data Access on macOS 27).
    Releases are not notarized yet, so macOS may require Open Anyway on first launch.
  EOS
end
