#!/usr/bin/env python3
import os
import uuid
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "CFAL3")
TEST = os.path.join(ROOT, "CFAL3Tests")


def uid():
    return uuid.uuid4().hex[:24].upper()


sources = []
for dirpath, _, filenames in os.walk(APP):
    for f in sorted(filenames):
        if f.endswith(".swift"):
            sources.append(os.path.relpath(os.path.join(dirpath, f), ROOT))

resources = [
    "CFAL3/Resources/question_bank.json",
    "CFAL3/Resources/los_master.json",
    "CFAL3/Resources/topics.json",
    "CFAL3/Resources/reading_notes.json",
    "CFAL3/Resources/content_targets.json",
    "CFAL3/Resources/los_drills_index.json",
    "CFAL3/Assets.xcassets",
]
resources.extend(
    sorted(
        os.path.relpath(p, ROOT)
        for p in Path(os.path.join(ROOT, "CFAL3/Resources")).glob("los_drills_r*.json")
    )
)
tests = [
    f"CFAL3Tests/{f}"
    for f in sorted(os.listdir(TEST))
    if f.endswith(".swift")
]

file_refs = {p: uid() for p in sources + resources + tests}
build_files = {p: uid() for p in sources + resources + tests}

project_uid = uid()
target_uid = uid()
test_target_uid = uid()
sources_phase = uid()
resources_phase = uid()
frameworks_phase = uid()
test_sources_phase = uid()
test_frameworks_phase = uid()
products_group = uid()
main_group = uid()
product_ref = uid()
test_product_ref = uid()
project_config_list = uid()
target_config_list = uid()
test_config_list = uid()
debug_config = uid()
release_config = uid()
target_debug = uid()
target_release = uid()
test_debug = uid()
test_release = uid()

groups = {}

def ensure_group(path):
    if path not in groups:
        groups[path] = uid()
    return groups[path]


ensure_group("CFAL3")
ensure_group("CFAL3Tests")
groups["Products"] = products_group
for path in sources + resources:
    parts = path.split("/")
    for i in range(1, len(parts)):
        ensure_group("/".join(parts[:i]))

children_map = {}
for path in sources + resources:
    parent = "/".join(path.split("/")[:-1])
    children_map.setdefault(parent, []).append(path)
for path in tests:
    children_map.setdefault("CFAL3Tests", []).append(path)

out = []
out.append("// !$*UTF8*$!")
out.append("{")
out.append("\tarchiveVersion = 1;")
out.append("\tclasses = {};")
out.append("\tobjectVersion = 56;")
out.append("\tobjects = {")
out.append("")
out.append("/* Begin PBXBuildFile section */")
for path in sources + tests:
    name = os.path.basename(path)
    out.append(
        f"\t\t{build_files[path]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {name} */; }};"
    )
for path in resources:
    name = os.path.basename(path)
    out.append(
        f"\t\t{build_files[path]} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {name} */; }};"
    )
out.append("/* End PBXBuildFile section */")
out.append("")
out.append("/* Begin PBXFileReference section */")
out.append(
    f"\t\t{product_ref} /* CFAL3.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = CFAL3.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
)
out.append(
    f"\t\t{test_product_ref} /* CFAL3Tests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = CFAL3Tests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
)
for path in sources + resources + tests:
    name = os.path.basename(path)
    if path.endswith(".swift"):
        out.append(
            f"\t\t{file_refs[path]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};"
        )
    elif path.endswith(".json"):
        out.append(
            f"\t\t{file_refs[path]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = {name}; sourceTree = \"<group>\"; }};"
        )
    else:
        out.append(
            f"\t\t{file_refs[path]} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};"
        )
out.append("/* End PBXFileReference section */")
out.append("")
out.append("/* Begin PBXFrameworksBuildPhase section */")
for phase in [frameworks_phase, test_frameworks_phase]:
    out.extend(
        [
            f"\t\t{phase} /* Frameworks */ = {{",
            "\t\t\tisa = PBXFrameworksBuildPhase;",
            "\t\t\tbuildActionMask = 2147483647;",
            "\t\t\tfiles = (",
            "\t\t\t);",
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
            "\t\t};",
        ]
    )
out.append("/* End PBXFrameworksBuildPhase section */")
out.append("")
out.append("/* Begin PBXGroup section */")
out.append(f"\t\t{main_group} = {{")
out.append("\t\t\tisa = PBXGroup;")
out.append("\t\t\tchildren = (")
out.append(f"\t\t\t\t{groups['CFAL3']} /* CFAL3 */,")
out.append(f"\t\t\t\t{groups['CFAL3Tests']} /* CFAL3Tests */,")
out.append(f"\t\t\t\t{products_group} /* Products */,")
out.append("\t\t\t);")
out.append('\t\t\tsourceTree = "<group>";')
out.append("\t\t};")
out.append(f"\t\t{products_group} /* Products */ = {{")
out.append("\t\t\tisa = PBXGroup;")
out.append("\t\t\tchildren = (")
out.append(f"\t\t\t\t{product_ref} /* CFAL3.app */,")
out.append(f"\t\t\t\t{test_product_ref} /* CFAL3Tests.xctest */,")
out.append("\t\t\t);")
out.append("\t\t\tname = Products;")
out.append('\t\t\tsourceTree = "<group>";')
out.append("\t\t};")
for group_path in sorted(groups.keys(), key=lambda p: (-p.count("/"), p)):
    if group_path == "Products":
        continue
    gid = groups[group_path]
    name = os.path.basename(group_path)
    out.append(f"\t\t{gid} /* {name} */ = {{")
    out.append("\t\t\tisa = PBXGroup;")
    out.append("\t\t\tchildren = (")
    for other in sorted(groups.keys()):
        if other.startswith(group_path + "/") and other.count("/") == group_path.count("/") + 1:
            out.append(f"\t\t\t\t{groups[other]} /* {os.path.basename(other)} */,")
    for child in sorted(children_map.get(group_path, [])):
        out.append(f"\t\t\t\t{file_refs[child]} /* {os.path.basename(child)} */,")
    out.append("\t\t\t);")
    out.append(f"\t\t\tpath = {name};")
    out.append('\t\t\tsourceTree = "<group>";')
    out.append("\t\t};")
out.append("/* End PBXGroup section */")
out.append("")
out.append("/* Begin PBXNativeTarget section */")
out.append(f"\t\t{target_uid} /* CFAL3 */ = {{")
out.append("\t\t\tisa = PBXNativeTarget;")
out.append(
    f"\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget \"CFAL3\" */;"
)
out.append("\t\t\tbuildPhases = (")
out.append(f"\t\t\t\t{sources_phase} /* Sources */,")
out.append(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
out.append(f"\t\t\t\t{resources_phase} /* Resources */,")
out.append("\t\t\t);")
out.append("\t\t\tbuildRules = (")
out.append("\t\t\t);")
out.append("\t\t\tdependencies = (")
out.append("\t\t\t);")
out.append("\t\t\tname = CFAL3;")
out.append("\t\t\tproductName = CFAL3;")
out.append(f"\t\t\tproductReference = {product_ref} /* CFAL3.app */;")
out.append('\t\t\tproductType = "com.apple.product-type.application";')
out.append("\t\t};")
out.append(f"\t\t{test_target_uid} /* CFAL3Tests */ = {{")
out.append("\t\t\tisa = PBXNativeTarget;")
out.append(
    f"\t\t\tbuildConfigurationList = {test_config_list} /* Build configuration list for PBXNativeTarget \"CFAL3Tests\" */;"
)
out.append("\t\t\tbuildPhases = (")
out.append(f"\t\t\t\t{test_sources_phase} /* Sources */,")
out.append(f"\t\t\t\t{test_frameworks_phase} /* Frameworks */,")
out.append("\t\t\t);")
out.append("\t\t\tbuildRules = (")
out.append("\t\t\t);")
out.append("\t\t\tdependencies = (")
out.append("\t\t\t);")
out.append("\t\t\tname = CFAL3Tests;")
out.append("\t\t\tproductName = CFAL3Tests;")
out.append(f"\t\t\tproductReference = {test_product_ref} /* CFAL3Tests.xctest */;")
out.append('\t\t\tproductType = "com.apple.product-type.bundle.unit-test";')
out.append("\t\t};")
out.append("/* End PBXNativeTarget section */")
out.append("")
out.append("/* Begin PBXProject section */")
out.append(f"\t\t{project_uid} /* Project object */ = {{")
out.append("\t\t\tisa = PBXProject;")
out.append(
    '\t\t\tattributes = {\n'
    '\t\t\t\tBuildIndependentTargetsInParallel = 1;\n'
    '\t\t\t\tLastSwiftUpdateCheck = 1500;\n'
    '\t\t\t\tLastUpgradeCheck = 1500;\n'
    '\t\t\t};'
)
out.append(
    f"\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"CFAL3\" */;"
)
out.append('\t\t\tcompatibilityVersion = "Xcode 14.0";')
out.append("\t\t\tdevelopmentRegion = en;")
out.append("\t\t\thasScannedForEncodings = 0;")
out.append("\t\t\tknownRegions = (")
out.append("\t\t\t\ten,")
out.append("\t\t\t\tBase,")
out.append("\t\t\t);")
out.append(f"\t\t\tmainGroup = {main_group};")
out.append(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
out.append('\t\t\tprojectDirPath = "";')
out.append('\t\t\tprojectRoot = "";')
out.append("\t\t\ttargets = (")
out.append(f"\t\t\t\t{target_uid} /* CFAL3 */,")
out.append(f"\t\t\t\t{test_target_uid} /* CFAL3Tests */,")
out.append("\t\t\t);")
out.append("\t\t};")
out.append("/* End PBXProject section */")
out.append("")
out.append("/* Begin PBXResourcesBuildPhase section */")
out.append(f"\t\t{resources_phase} /* Resources */ = {{")
out.append("\t\t\tisa = PBXResourcesBuildPhase;")
out.append("\t\t\tbuildActionMask = 2147483647;")
out.append("\t\t\tfiles = (")
for path in resources:
    name = os.path.basename(path)
    out.append(f"\t\t\t\t{build_files[path]} /* {name} in Resources */,")
out.append("\t\t\t);")
out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
out.append("\t\t};")
out.append("/* End PBXResourcesBuildPhase section */")
out.append("")
out.append("/* Begin PBXSourcesBuildPhase section */")
for phase, paths in [(sources_phase, sources), (test_sources_phase, tests)]:
    out.append(f"\t\t{phase} /* Sources */ = {{")
    out.append("\t\t\tisa = PBXSourcesBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    for path in paths:
        name = os.path.basename(path)
        out.append(f"\t\t\t\t{build_files[path]} /* {name} in Sources */,")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")
out.append("/* End PBXSourcesBuildPhase section */")
out.append("")
out.append("/* Begin XCBuildConfiguration section */")
for cid, name in [(debug_config, "Debug"), (release_config, "Release")]:
    out.append(f"\t\t{cid} /* {name} */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    out.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    if name == "Debug":
        out.extend(
            [
                "\t\t\t\tENABLE_TESTABILITY = YES;",
                "\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;",
                "\t\t\t\tONLY_ACTIVE_ARCH = YES;",
                "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
                '\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";',
            ]
        )
    else:
        out.append("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    out.extend(
        [
            "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;",
            "\t\t\t\tSDKROOT = iphoneos;",
            "\t\t\t};",
            f"\t\t\tname = {name};",
            "\t\t};",
        ]
    )
app_settings = [
    ("PRODUCT_NAME", "CFAL3"),
    ("PRODUCT_BUNDLE_IDENTIFIER", "com.brandonkeeny.CFAL3"),
    ("CURRENT_PROJECT_VERSION", "1"),
    ("MARKETING_VERSION", "1.0"),
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("INFOPLIST_KEY_CFBundleDisplayName", '"CFA L3"'),
    ("INFOPLIST_KEY_UIApplicationSceneManifest_Generation", "YES"),
    ("INFOPLIST_KEY_UILaunchScreen_Generation", "YES"),
    ("INFOPLIST_FILE", "CFAL3/Info.plist"),
    ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("IPHONEOS_DEPLOYMENT_TARGET", "17.0"),
    ("SWIFT_VERSION", "5.0"),
    ("TARGETED_DEVICE_FAMILY", '"1,2"'),
]
for cid, name in [(target_debug, "Debug"), (target_release, "Release")]:
    out.append(f"\t\t{cid} /* {name} */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    for k, v in app_settings:
        out.append(f"\t\t\t\t{k} = {v};")
    out.append("\t\t\t};")
    out.append(f"\t\t\tname = {name};")
    out.append("\t\t};")
for cid, name in [(test_debug, "Debug"), (test_release, "Release")]:
    out.append(f"\t\t{cid} /* {name} */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.extend(
        [
            '\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";',
            "\t\t\t\tCODE_SIGN_STYLE = Automatic;",
            "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;",
            "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;",
            "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.brandonkeeny.CFAL3Tests;",
            "\t\t\t\tPRODUCT_NAME = CFAL3Tests;",
            "\t\t\t\tSWIFT_VERSION = 5.0;",
            '\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";',
            '\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/CFAL3.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/CFAL3";',
        ]
    )
    out.append("\t\t\t};")
    out.append(f"\t\t\tname = {name};")
    out.append("\t\t};")
out.append("/* End XCBuildConfiguration section */")
out.append("")
out.append("/* Begin XCConfigurationList section */")
for clist, cfgs in [
    (project_config_list, [(debug_config, "Debug"), (release_config, "Release")]),
    (target_config_list, [(target_debug, "Debug"), (target_release, "Release")]),
    (test_config_list, [(test_debug, "Debug"), (test_release, "Release")]),
]:
    out.append(f"\t\t{clist} /* Build configuration list */ = {{")
    out.append("\t\t\tisa = XCConfigurationList;")
    out.append("\t\t\tbuildConfigurations = (")
    for cid, name in cfgs:
        out.append(f"\t\t\t\t{cid} /* {name} */,")
    out.append("\t\t\t);")
    out.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    out.append("\t\t\tdefaultConfigurationName = Release;")
    out.append("\t\t};")
out.append("/* End XCConfigurationList section */")
out.append("\t};")
out.append(f"\trootObject = {project_uid} /* Project object */;")
out.append("}")

proj_dir = os.path.join(ROOT, "CFAL3.xcodeproj")
os.makedirs(proj_dir, exist_ok=True)
with open(os.path.join(proj_dir, "project.pbxproj"), "w", encoding="utf-8") as f:
    f.write("\n".join(out))
print(f"Generated {len(sources)} source files, {len(tests)} tests")

scheme_dir = os.path.join(proj_dir, "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_uid}"
               BuildableName = "CFAL3.app"
               BlueprintName = "CFAL3"
               ReferencedContainer = "container:CFAL3.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target_uid}"
               BuildableName = "CFAL3Tests.xctest"
               BlueprintName = "CFAL3Tests"
               ReferencedContainer = "container:CFAL3.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_uid}"
            BuildableName = "CFAL3.app"
            BlueprintName = "CFAL3"
            ReferencedContainer = "container:CFAL3.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
</Scheme>
'''
with open(os.path.join(scheme_dir, "CFAL3.xcscheme"), "w", encoding="utf-8") as f:
    f.write(scheme)
