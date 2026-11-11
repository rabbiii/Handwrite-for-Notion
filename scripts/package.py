#!/usr/bin/env python3
"""Create source-only iPad and Windows-build deliveries; exclude caches and data."""
from pathlib import Path
import hashlib
import stat
import zipfile

root = Path(__file__).resolve().parents[1]
output = root / "dist"
output.mkdir(exist_ok=True)
app = root / "PencilNotes.swiftpm"
sources = sorted((app / "Core").glob("*.swift")) + sorted((app / "App").glob("*.swift"))
combined = output / "PencilNotes-All.swift"
header = "// Single-file fallback for a NEW Swift Playground App template.\n// Replace the template's @main file and remove its ContentView; do not also add split sources.\n// Do not paste either Package.swift manifest here.\n\n"
combined.write_text(header + "\n\n".join("// MARK: - " + str(p.relative_to(app)) + "\n" + p.read_text() for p in sources))
files = [app / "Package.swift", *sources, root / "README.md", *sorted((root / "docs").glob("*.md"))]


def add_entry(bundle, name, data=b"", *, directory=False):
    # Do not export the cloud executor's owner-only modes. Explicit directory
    # entries also prevent an extractor's defaults from defining package modes.
    info = zipfile.ZipInfo(name)
    info.create_system = 3  # Unix mode bits, without owner/group IDs or ACLs.
    info.compress_type = zipfile.ZIP_DEFLATED
    mode = (stat.S_IFDIR | 0o755) if directory else (stat.S_IFREG | 0o644)
    info.external_attr = (mode << 16) | (0x10 if directory else 0)
    bundle.writestr(info, data)


def write_archive(archive, entries):
    assert len({name for name, _ in entries}) == len(entries)
    directories = sorted({str(parent) for name, _ in entries
                          for parent in Path(name).parents if parent != Path(".")})
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for directory in directories:
            add_entry(bundle, directory + "/", directory=True)
        for name, path in entries:
            add_entry(bundle, name, path.read_bytes())
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None
        assert "PencilNotes.swiftpm/Package.swift" in bundle.namelist()
        assert all(not name.startswith("/") and ".." not in Path(name).parts for name in bundle.namelist())
        for info in bundle.infolist():
            assert stat.S_IMODE(info.external_attr >> 16) == (0o755 if info.is_dir() else 0o644)
        for name, path in entries:
            assert bundle.read(name) == path.read_bytes()
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    print(f"Created {archive} ({archive.stat().st_size:,} bytes)")
    return f"{checksum}  {archive.name}\n"


entries = [(str(path.relative_to(root)), path) for path in files]
checksums = write_archive(output / "PencilNotes-iPad.zip", [*entries, (combined.name, combined)])
build_files = [root / path for path in [
    "Package.swift", ".gitignore", ".github/workflows/build-ios.yml", "MacBuild/Info.plist",
    "MacBuild/PencilNotes.xcodeproj/project.pbxproj",
    "MacBuild/PencilNotes.xcodeproj/xcshareddata/xcschemes/PencilNotes.xcscheme",
    "scripts/generate_xcode_project.py", "scripts/build_ios_unsigned.sh", "scripts/test.sh", "scripts/package.py",
]]
build_files += sorted((root / "Tests/PencilNotesCoreTests").glob("*.swift"))
checksums += write_archive(output / "PencilNotes-Windows-build-kit.zip",
                          [*entries, *((str(path.relative_to(root)), path) for path in build_files)])
(output / "SHA256SUMS").write_text(checksums)
