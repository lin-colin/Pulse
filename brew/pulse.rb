cask "pulse" do
  version "1.0.0"
  sha256 "REPLACE_WITH_ACTUAL_SHA256_HASH_OF_ZIP_FILE"

  url "https://github.com/lin-colin/Pulse/releases/download/v#{version}/Pulse_macOS.zip"
  name "Pulse"
  desc "Lightweight macOS menu bar system monitor"
  homepage "https://github.com/lin-colin/Pulse"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "Pulse.app"

  uninstall quit: "com.hlc.pulse"

  zap trash: [
    "~/Library/Preferences/com.hlc.pulse.plist",
    # Add any other cached data or app support folders here if needed
  ]
end
