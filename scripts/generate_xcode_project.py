#!/usr/bin/env python3
"""Generate the native Xcode app target using the existing App/Core sources.

No AppleProductTypes, external project generator, signing key, or Apple account
is needed to generate this project. Compiling it still requires Xcode on macOS.
"""
from pathlib import Path
import hashlib
import json
import plistlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "MacBuild/PencilNotes.xcodeproj"


def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def openstep(value, level=0):
    if isinstance(value, dict):
        rows = ["\t" * (level + 1) + json.dumps(str(k)) + " = " + openstep(v, level + 1) + ";" for k, v in value.items()]
        return "{\n" + "\n".join(rows) + "\n" + "\t" * level + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (level + 1) + openstep(v, level + 1) + ",\n" for v in value) + "\t" * level + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(str(value))


def generate():
    objects = {}

    def add(key_name, isa, **fields):
        key = identifier(key_name)
        objects[key] = {"isa": isa, **fields}
        return key

    groups = []
    build_files = []
    for folder in ["App", "Core"]:
        children = []
        for path in sorted((ROOT / "PencilNotes.swiftpm" / folder).glob("*.swift")):
            name = str(path.relative_to(ROOT))
            file_id = add(name, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=path.name, sourceTree="<group>")
            children.append(file_id)
            build_files.append(add("build:" + name, "PBXBuildFile", fileRef=file_id))
        assert children, f"No Swift files in {folder}"
        groups.append(add(folder, "PBXGroup", children=children, name=folder,
                          path="../PencilNotes.swiftpm/" + folder, sourceTree="<group>"))

    product = add("product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0,
                  path="PencilNotes.app", sourceTree="BUILT_PRODUCTS_DIR")
    products = add("products", "PBXGroup", children=[product], name="Products", sourceTree="<group>")
    info = add("info", "PBXFileReference", lastKnownFileType="text.plist.xml", path="Info.plist", sourceTree="<group>")
    main = add("main", "PBXGroup", children=[*groups, info, products], sourceTree="<group>")
    sources = add("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=build_files, runOnlyForDeploymentPostprocessing=0)
    frameworks = add("frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
    catalog = add("assets", "PBXFileReference", lastKnownFileType="folder.assetcatalog",
                  path="../PencilNotes.swiftpm/Resources/Assets.xcassets", sourceTree="<group>")
    objects[main]["children"].insert(2, catalog)
    resources = add("resources", "PBXResourcesBuildPhase", buildActionMask=2147483647,
                    files=[add("build:assets", "PBXBuildFile", fileRef=catalog)], runOnlyForDeploymentPostprocessing=0)

    project_configs = []
    target_configs = []
    for name in ["Debug", "Release"]:
        settings = {
            "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "SDKROOT": "iphoneos",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O",
            "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if name == "Debug" else "",
        }
        if name == "Release":
            settings["SWIFT_COMPILATION_MODE"] = "wholemodule"
        project_configs.append(add("project:" + name, "XCBuildConfiguration", name=name, buildSettings=settings))
        target_configs.append(add("target:" + name, "XCBuildConfiguration", name=name, buildSettings={
            "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "app.pencilnotes.personal",
            "TARGETED_DEVICE_FAMILY": "2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "SUPPORTS_MACCATALYST": "NO", "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "",
            "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "$(SRCROOT)/Info.plist",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
            "CURRENT_PROJECT_VERSION": "2", "MARKETING_VERSION": "1.1", "SWIFT_EMIT_LOC_STRINGS": "YES",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "ENABLE_TESTABILITY": "YES" if name == "Debug" else "NO",
        }))
    project_list = add("project_configs", "XCConfigurationList", buildConfigurations=project_configs,
                       defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    target_list = add("target_configs", "XCConfigurationList", buildConfigurations=target_configs,
                      defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    target = add("target", "PBXNativeTarget", buildConfigurationList=target_list, buildPhases=[sources, frameworks, resources],
                 buildRules=[], dependencies=[], name="PencilNotes", productName="PencilNotes", productReference=product,
                 productType="com.apple.product-type.application")
    project = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600",
                  "TargetAttributes": {target: {"CreatedOnToolsVersion": "16.0", "ProvisioningStyle": "Automatic"}}},
                  buildConfigurationList=project_list, compatibilityVersion="Xcode 14.0", developmentRegion="en",
                  hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main, productRefGroup=products,
                  projectDirPath="", projectRoot="", targets=[target])
    test_files = []
    test_refs = []
    for path in sorted((ROOT / "Tests/PencilNotesAppTests").glob("*.swift")):
        ref = add("test:" + path.name, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=path.name, sourceTree="<group>")
        test_refs.append(ref)
        test_files.append(add("testbuild:" + path.name, "PBXBuildFile", fileRef=ref))
    test_group = add("tests", "PBXGroup", children=test_refs, name="AppTests", path="../Tests/PencilNotesAppTests", sourceTree="<group>")
    objects[main]["children"].append(test_group)
    test_product = add("testproduct", "PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0, path="PencilNotesAppTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    objects[products]["children"].append(test_product)
    test_sources = add("testsources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=test_files, runOnlyForDeploymentPostprocessing=0)
    test_configs = []
    for name in ["Debug", "Release"]:
        test_configs.append(add("testconfig:" + name, "XCBuildConfiguration", name=name, buildSettings={
            "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "app.pencilnotes.personal.tests",
            "GENERATE_INFOPLIST_FILE": "YES", "TARGETED_DEVICE_FAMILY": "2", "CODE_SIGN_STYLE": "Automatic",
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/PencilNotes.app/PencilNotes", "BUNDLE_LOADER": "$(TEST_HOST)",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
        }))
    test_list = add("testconfigs", "XCConfigurationList", buildConfigurations=test_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
    proxy = add("testproxy", "PBXContainerItemProxy", containerPortal=project, proxyType=1, remoteGlobalIDString=target, remoteInfo="PencilNotes")
    dependency = add("testdependency", "PBXTargetDependency", target=target, targetProxy=proxy)
    test_target = add("testtarget", "PBXNativeTarget", name="PencilNotesAppTests", productName="PencilNotesAppTests",
                      productReference=test_product, productType="com.apple.product-type.bundle.unit-test",
                      buildConfigurationList=test_list, buildPhases=[test_sources], buildRules=[], dependencies=[dependency])
    objects[project]["targets"].append(test_target)
    contents = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}
    PROJECT.mkdir(parents=True, exist_ok=True)
    (PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + openstep(contents) + "\n")

    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")
    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entry = ET.SubElement(ET.SubElement(build, "BuildActionEntries"), "BuildActionEntry",
                         buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")

    def reference(parent):
        ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target,
                      BuildableName="PencilNotes.app", BlueprintName="PencilNotes", ReferencedContainer="container:PencilNotes.xcodeproj")

    reference(entry)
    test_action = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    testable = ET.SubElement(ET.SubElement(test_action, "Testables"), "TestableReference", skipped="NO")
    ET.SubElement(testable, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=test_target,
                  BuildableName="PencilNotesAppTests.xctest", BlueprintName="PencilNotesAppTests", ReferencedContainer="container:PencilNotes.xcodeproj")
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                           selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO",
                           ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", allowLocationSimulation="YES")
    reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"))
    profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"))
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    destination = PROJECT / "xcshareddata/xcschemes/PencilNotes.xcscheme"
    destination.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(scheme)
    ET.ElementTree(scheme).write(destination, encoding="utf-8", xml_declaration=True)

    info = {
        "CFBundleDevelopmentRegion": "en", "CFBundleDisplayName": "PencilNotes", "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "LSRequiresIPhoneOS": True, "UILaunchScreen": {},
        "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False, "UISceneConfigurations": {}},
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
    }
    (PROJECT.parent / "Info.plist").write_bytes(plistlib.dumps(info, sort_keys=True))
    print(f"Generated {PROJECT.relative_to(ROOT)} with {len(build_files)} Swift sources.")


if __name__ == "__main__":
    generate()
