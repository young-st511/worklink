"""Check actual compiled icon layers and appearances; no external Python packages."""
import json
import plistlib
import subprocess
import sys
from pathlib import Path

app = Path(sys.argv[1] if len(sys.argv) > 1 else ".build/Worklink.app")
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
resources = app / "Contents/Resources"
assert info.get("CFBundleIconFile") == "Worklink", "Icon file is not registered"
assert (resources / "Worklink.icns").read_bytes().startswith(b"icns"), "Legacy icon missing"
assert info["LSMinimumSystemVersion"] == "14.0", "Runtime requirement changed"
if (resources / "Assets.car").exists():
    assert info.get("CFBundleIconName") == "Worklink", "Layered icon is not registered"
    entries = json.loads(subprocess.check_output(["xcrun", "assetutil", "--info", str(resources / "Assets.car")]))
    stacks = {e.get("Appearance") for e in entries if e.get("AssetType") == "IconImageStack" and e.get("Name") == "Worklink"}
    assert {"NSAppearanceNameAqua", "NSAppearanceNameDarkAqua", "ISAppearanceTintable"} <= stacks, "Liquid Glass appearance stacks missing"
    layers = {e.get("Name") for e in entries if e.get("AssetType") == "Vector"}
    assert {"Worklink_Assets/01-remote-link", "Worklink_Assets/02-local-link"} <= layers, "Vector layers missing"
    assert any(e.get("AssetType") == "Icon Image" and e.get("Name") == "Worklink" and e.get("PixelWidth", 0) >= 1024 for e in entries), "High-resolution icon missing"
    print("Native Liquid Glass layers, appearances, 1024px icon and macOS 14 compatibility verified.")
else:
    assert "CFBundleIconName" not in info, "Stale layered icon registration in legacy build"
    print("Legacy icon registration and macOS 14 compatibility verified.")
