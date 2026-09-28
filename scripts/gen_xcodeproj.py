#!/usr/bin/env python3
"""Generate Vow.xcodeproj without XcodeGen.

This script mirrors `project.yml` (the XcodeGen spec at the repo root) so the
committed Vow.xcodeproj can be regenerated on machines that do not have
XcodeGen or Xcode (e.g. Linux). On a Mac, `xcodegen generate` is the canonical
way to produce the project; if you change project.yml, change the settings
below to match (and vice versa).

What it does:
  * walks <root>/Vow recursively and adds every *.swift file to the Vow target
    (groups mirror folders; hidden files and non-Swift files are ignored),
  * writes Vow.xcodeproj/project.pbxproj, the embedded workspace, the
    IDEWorkspaceChecks.plist, and the shared `Vow` scheme,
  * derives every object ID from an md5 of a stable role/path string, so
    reruns over the same tree produce byte-identical output,
  * re-parses the pbxproj it wrote (tiny old-style ASCII plist parser) and
    checks that every referenced object ID is defined; exits non-zero if not.

Usage:
  python3 scripts/gen_xcodeproj.py [ROOT]      # ROOT defaults to the repo root
  python3 scripts/gen_xcodeproj.py --check [ROOT]  # validate existing project only

Standard library only; Python 3.6+.
"""

import hashlib
import os
import re
import sys

# ---------------------------------------------------------------------------
# Configuration (keep in sync with project.yml)
# ---------------------------------------------------------------------------

PROJECT_NAME = "Vow"
TARGET_NAME = "Vow"
SOURCE_DIR = "Vow"
PRODUCT_FILE = "Vow.app"
DEPLOYMENT_TARGET = "17.0"
XCODE_VERSION_CODE = "1600"  # xcodeVersion: 16.0
OBJECT_VERSION = "56"
COMPATIBILITY_VERSION = "Xcode 14.0"

TARGET_SETTINGS = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "Vow",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "INFOPLIST_KEY_UIUserInterfaceStyle": "Dark",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.example.vow",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SDKROOT": "iphoneos",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}

PROJECT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_COMMA": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
}

PROJECT_DEBUG = dict(PROJECT_COMMON, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})

PROJECT_RELEASE = dict(PROJECT_COMMON, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "VALIDATE_PRODUCT": "YES",
})

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_SAFE = re.compile(r"^[A-Za-z0-9_$/.]+$")


def q(value):
    """Render a string as an old-style plist scalar, quoting when needed."""
    s = str(value)
    if s and _SAFE.match(s) and not s.startswith("//"):
        return s
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def cmt(text):
    """Comment text safe to embed inside /* ... */."""
    return str(text).replace("*/", "* /")


_ids = {}


def oid(*parts):
    """Stable 24-hex-char uppercase object ID from a role/path key."""
    key = "|".join(("vow",) + parts)
    h = hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()
    prev = _ids.get(h)
    if prev is not None and prev != key:
        raise SystemExit("ID collision between %r and %r" % (prev, key))
    _ids[h] = key
    return h


class Node(object):
    def __init__(self, name, rel):
        self.name = name     # folder name
        self.rel = rel       # path relative to root, posix
        self.groups = []     # [Node]
        self.files = []      # [rel path of .swift]


def scan(root):
    src = os.path.join(root, SOURCE_DIR)
    if not os.path.isdir(src):
        raise SystemExit("error: source directory not found: %s" % src)
    skipped = []

    def walk(abs_dir, rel):
        node = Node(os.path.basename(abs_dir), rel)
        for entry in sorted(os.listdir(abs_dir), key=lambda s: (s.lower(), s)):
            if entry.startswith("."):
                continue
            p = os.path.join(abs_dir, entry)
            r = rel + "/" + entry
            if os.path.isdir(p) and not entry.endswith((".xcassets", ".bundle", ".xcodeproj")):
                child = walk(p, r)
                if child.files or child.groups:
                    node.groups.append(child)
            elif os.path.isfile(p) and entry.endswith(".swift"):
                node.files.append(r)
            else:
                skipped.append(r)
        return node

    tree = walk(src, SOURCE_DIR)
    for s in skipped:
        sys.stderr.write("note: not added to project (not a .swift file): %s\n" % s)
    return tree


def all_files(node):
    out = list(node.files)
    for g in node.groups:
        out.extend(all_files(g))
    return out


# ---------------------------------------------------------------------------
# pbxproj writer
# ---------------------------------------------------------------------------

def settings_block(settings, indent):
    t = "\t" * indent
    lines = []
    for k in sorted(settings):
        v = settings[k]
        if isinstance(v, list):
            lines.append("%s%s = (" % (t, q(k)))
            for item in v:
                lines.append("%s\t%s," % (t, q(item)))
            lines.append("%s);" % t)
        else:
            lines.append("%s%s = %s;" % (t, q(k), q(v)))
    return lines


def build_pbxproj(tree):
    files = all_files(tree)

    project_id = oid("project")
    main_group = oid("group", "<main>")
    products_group = oid("group", "<products>")
    product_ref = oid("product", PRODUCT_FILE)
    target_id = oid("target", TARGET_NAME)
    sources_phase = oid("phase", "sources", TARGET_NAME)
    frameworks_phase = oid("phase", "frameworks", TARGET_NAME)
    resources_phase = oid("phase", "resources", TARGET_NAME)
    proj_cfg_list = oid("configlist", "project")
    tgt_cfg_list = oid("configlist", "target", TARGET_NAME)
    proj_debug = oid("config", "project", "Debug")
    proj_release = oid("config", "project", "Release")
    tgt_debug = oid("config", "target", TARGET_NAME, "Debug")
    tgt_release = oid("config", "target", TARGET_NAME, "Release")

    file_ref = {f: oid("fileref", f) for f in files}
    build_file = {f: oid("buildfile", "sources", f) for f in files}

    def base(f):
        return f.rsplit("/", 1)[-1]

    L = []
    a = L.append
    a("// !$*UTF8*$!")
    a("{")
    a("\tarchiveVersion = 1;")
    a("\tclasses = {")
    a("\t};")
    a("\tobjectVersion = %s;" % OBJECT_VERSION)
    a("\tobjects = {")
    a("")

    # PBXBuildFile
    a("/* Begin PBXBuildFile section */")
    for f in sorted(files, key=lambda f: build_file[f]):
        a("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
          % (build_file[f], cmt(base(f)), file_ref[f], cmt(base(f))))
    a("/* End PBXBuildFile section */")
    a("")

    # PBXFileReference
    a("/* Begin PBXFileReference section */")
    refs = [(file_ref[f],
             "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = %s; };"
             % (file_ref[f], cmt(base(f)), q(base(f)), q("<group>")))
            for f in files]
    refs.append((product_ref,
                 "\t\t%s /* %s */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = %s; sourceTree = BUILT_PRODUCTS_DIR; };"
                 % (product_ref, cmt(PRODUCT_FILE), q(PRODUCT_FILE))))
    for _, line in sorted(refs):
        a(line)
    a("/* End PBXFileReference section */")
    a("")

    # PBXFrameworksBuildPhase
    a("/* Begin PBXFrameworksBuildPhase section */")
    a("\t\t%s /* Frameworks */ = {" % frameworks_phase)
    a("\t\t\tisa = PBXFrameworksBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXFrameworksBuildPhase section */")
    a("")

    # PBXGroup
    groups = []  # (id, lines)

    def emit_group(gid, children, extra):
        lines = ["\t\t%s%s = {" % (gid, extra["comment"]),
                 "\t\t\tisa = PBXGroup;",
                 "\t\t\tchildren = ("]
        for cid, cname in children:
            lines.append("\t\t\t\t%s /* %s */," % (cid, cmt(cname)))
        lines.append("\t\t\t);")
        for k, v in extra["props"]:
            lines.append("\t\t\t%s = %s;" % (k, v))
        lines.append("\t\t};")
        groups.append((gid, lines))

    def group_id(node):
        return oid("group", node.rel)

    def walk_groups(node):
        children = [(group_id(g), g.name) for g in node.groups]
        children += [(file_ref[f], base(f)) for f in node.files]
        emit_group(group_id(node), children,
                   {"comment": " /* %s */" % cmt(node.name),
                    "props": [("path", q(node.name)), ("sourceTree", q("<group>"))]})
        for g in node.groups:
            walk_groups(g)

    emit_group(main_group, [(group_id(tree), tree.name), (products_group, "Products")],
               {"comment": "", "props": [("sourceTree", q("<group>"))]})
    emit_group(products_group, [(product_ref, PRODUCT_FILE)],
               {"comment": " /* Products */",
                "props": [("name", "Products"), ("sourceTree", q("<group>"))]})
    walk_groups(tree)

    a("/* Begin PBXGroup section */")
    for _, lines in sorted(groups):
        L.extend(lines)
    a("/* End PBXGroup section */")
    a("")

    # PBXNativeTarget
    a("/* Begin PBXNativeTarget section */")
    a("\t\t%s /* %s */ = {" % (target_id, TARGET_NAME))
    a("\t\t\tisa = PBXNativeTarget;")
    a("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"%s\" */;"
      % (tgt_cfg_list, TARGET_NAME))
    a("\t\t\tbuildPhases = (")
    a("\t\t\t\t%s /* Sources */," % sources_phase)
    a("\t\t\t\t%s /* Frameworks */," % frameworks_phase)
    a("\t\t\t\t%s /* Resources */," % resources_phase)
    a("\t\t\t);")
    a("\t\t\tbuildRules = (")
    a("\t\t\t);")
    a("\t\t\tdependencies = (")
    a("\t\t\t);")
    a("\t\t\tname = %s;" % q(TARGET_NAME))
    a("\t\t\tproductName = %s;" % q(TARGET_NAME))
    a("\t\t\tproductReference = %s /* %s */;" % (product_ref, PRODUCT_FILE))
    a("\t\t\tproductType = %s;" % q("com.apple.product-type.application"))
    a("\t\t};")
    a("/* End PBXNativeTarget section */")
    a("")

    # PBXProject
    a("/* Begin PBXProject section */")
    a("\t\t%s /* Project object */ = {" % project_id)
    a("\t\t\tisa = PBXProject;")
    a("\t\t\tattributes = {")
    a("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    a("\t\t\t\tLastSwiftUpdateCheck = %s;" % XCODE_VERSION_CODE)
    a("\t\t\t\tLastUpgradeCheck = %s;" % XCODE_VERSION_CODE)
    a("\t\t\t\tTargetAttributes = {")
    a("\t\t\t\t\t%s = {" % target_id)
    a("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    a("\t\t\t\t\t};")
    a("\t\t\t\t};")
    a("\t\t\t};")
    a("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"%s\" */;"
      % (proj_cfg_list, PROJECT_NAME))
    a("\t\t\tcompatibilityVersion = %s;" % q(COMPATIBILITY_VERSION))
    a("\t\t\tdevelopmentRegion = en;")
    a("\t\t\thasScannedForEncodings = 0;")
    a("\t\t\tknownRegions = (")
    a("\t\t\t\ten,")
    a("\t\t\t\tBase,")
    a("\t\t\t);")
    a("\t\t\tmainGroup = %s;" % main_group)
    a("\t\t\tproductRefGroup = %s /* Products */;" % products_group)
    a("\t\t\tprojectDirPath = \"\";")
    a("\t\t\tprojectRoot = \"\";")
    a("\t\t\ttargets = (")
    a("\t\t\t\t%s /* %s */," % (target_id, TARGET_NAME))
    a("\t\t\t);")
    a("\t\t};")
    a("/* End PBXProject section */")
    a("")

    # PBXResourcesBuildPhase
    a("/* Begin PBXResourcesBuildPhase section */")
    a("\t\t%s /* Resources */ = {" % resources_phase)
    a("\t\t\tisa = PBXResourcesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXResourcesBuildPhase section */")
    a("")

    # PBXSourcesBuildPhase
    a("/* Begin PBXSourcesBuildPhase section */")
    a("\t\t%s /* Sources */ = {" % sources_phase)
    a("\t\t\tisa = PBXSourcesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    for f in files:
        a("\t\t\t\t%s /* %s in Sources */," % (build_file[f], cmt(base(f))))
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXSourcesBuildPhase section */")
    a("")

    # XCBuildConfiguration
    configs = [
        (proj_debug, "Debug", PROJECT_DEBUG),
        (proj_release, "Release", PROJECT_RELEASE),
        (tgt_debug, "Debug", TARGET_SETTINGS),
        (tgt_release, "Release", TARGET_SETTINGS),
    ]
    a("/* Begin XCBuildConfiguration section */")
    for cid, name, settings in sorted(configs):
        a("\t\t%s /* %s */ = {" % (cid, name))
        a("\t\t\tisa = XCBuildConfiguration;")
        a("\t\t\tbuildSettings = {")
        L.extend(settings_block(settings, 4))
        a("\t\t\t};")
        a("\t\t\tname = %s;" % name)
        a("\t\t};")
    a("/* End XCBuildConfiguration section */")
    a("")

    # XCConfigurationList
    lists = [
        (proj_cfg_list, "PBXProject", PROJECT_NAME, proj_debug, proj_release),
        (tgt_cfg_list, "PBXNativeTarget", TARGET_NAME, tgt_debug, tgt_release),
    ]
    a("/* Begin XCConfigurationList section */")
    for lid, kind, name, dbg, rel in sorted(lists):
        a("\t\t%s /* Build configuration list for %s \"%s\" */ = {" % (lid, kind, name))
        a("\t\t\tisa = XCConfigurationList;")
        a("\t\t\tbuildConfigurations = (")
        a("\t\t\t\t%s /* Debug */," % dbg)
        a("\t\t\t\t%s /* Release */," % rel)
        a("\t\t\t);")
        a("\t\t\tdefaultConfigurationIsVisible = 0;")
        a("\t\t\tdefaultConfigurationName = Release;")
        a("\t\t};")
    a("/* End XCConfigurationList section */")
    a("\t};")
    a("\trootObject = %s /* Project object */;" % project_id)
    a("}")
    return "\n".join(L) + "\n", target_id


# ---------------------------------------------------------------------------
# Other project files
# ---------------------------------------------------------------------------

WORKSPACE_DATA = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""

WORKSPACE_CHECKS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>IDEDidComputeMac32BitWarning</key>
	<true/>
</dict>
</plist>
"""


def build_scheme(target_id):
    def ref(indent):
        pad = " " * indent
        return "\n".join([
            "<BuildableReference",
            pad + '   BuildableIdentifier = "primary"',
            pad + '   BlueprintIdentifier = "%s"' % target_id,
            pad + '   BuildableName = "%s"' % PRODUCT_FILE,
            pad + '   BlueprintName = "%s"' % TARGET_NAME,
            pad + '   ReferencedContainer = "container:%s.xcodeproj">' % PROJECT_NAME,
            pad + "</BuildableReference>",
        ])

    return """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "{ver}"
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
            {ref_build}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
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
         {ref_run}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref_run}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""".format(ver=XCODE_VERSION_CODE,
           ref_build=ref(12),
           ref_run=ref(9))


# ---------------------------------------------------------------------------
# Validation: minimal old-style (NeXTSTEP) ASCII plist parser
# ---------------------------------------------------------------------------

class PlistError(Exception):
    pass


_UNQUOTED = re.compile(r"[A-Za-z0-9_$/:.\-]+")
_ID = re.compile(r"^[0-9A-F]{24}$")


def parse_plist(text):
    pos = [0]
    n = len(text)

    def skip():
        i = pos[0]
        while i < n:
            c = text[i]
            if c in " \t\r\n":
                i += 1
            elif text.startswith("//", i):
                j = text.find("\n", i)
                i = n if j < 0 else j + 1
            elif text.startswith("/*", i):
                j = text.find("*/", i + 2)
                if j < 0:
                    raise PlistError("unterminated comment at %d" % i)
                i = j + 2
            else:
                break
        pos[0] = i

    def expect(ch):
        skip()
        if pos[0] >= n or text[pos[0]] != ch:
            got = text[pos[0]:pos[0] + 20] if pos[0] < n else "EOF"
            raise PlistError("expected %r at %d, got %r" % (ch, pos[0], got))
        pos[0] += 1

    def peek():
        skip()
        return text[pos[0]] if pos[0] < n else ""

    def string():
        skip()
        i = pos[0]
        if i < n and text[i] == '"':
            i += 1
            out = []
            esc = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}
            while True:
                if i >= n:
                    raise PlistError("unterminated string")
                c = text[i]
                if c == '"':
                    pos[0] = i + 1
                    return "".join(out)
                if c == "\\":
                    nxt = text[i + 1] if i + 1 < n else ""
                    if nxt not in esc:
                        raise PlistError("bad escape \\%s at %d" % (nxt, i))
                    out.append(esc[nxt])
                    i += 2
                    continue
                if c == "\n":
                    raise PlistError("raw newline in string at %d" % i)
                out.append(c)
                i += 1
        m = _UNQUOTED.match(text, i)
        if not m:
            raise PlistError("expected string at %d: %r" % (i, text[i:i + 20]))
        pos[0] = m.end()
        return m.group(0)

    def value():
        c = peek()
        if c == "{":
            pos[0] += 1
            d = {}
            while peek() != "}":
                k = string()
                expect("=")
                v = value()
                expect(";")
                if k in d:
                    raise PlistError("duplicate key %r" % k)
                d[k] = v
            pos[0] += 1
            return d
        if c == "(":
            pos[0] += 1
            arr = []
            while peek() != ")":
                arr.append(value())
                if peek() == ",":
                    pos[0] += 1
                elif peek() != ")":
                    raise PlistError("expected ',' or ')' at %d" % pos[0])
            pos[0] += 1
            return arr
        return string()

    if not text.startswith("// !$*UTF8*$!"):
        raise PlistError("missing UTF8 header")
    root = value()
    skip()
    if pos[0] != n:
        raise PlistError("trailing data at %d" % pos[0])
    return root


def validate(pbx_text, expected_files=None):
    """Return a list of problems (empty == OK)."""
    problems = []
    # Bracket balance outside strings/comments is implied by a successful parse,
    # but check raw counts too for a fast, independent signal.
    stripped = re.sub(r'"(?:[^"\\]|\\.)*"', '""', pbx_text)
    stripped = re.sub(r"/\*.*?\*/", "", stripped, flags=re.S)
    for o, c in ("{}", "()"):
        if stripped.count(o) != stripped.count(c):
            problems.append("unbalanced %s%s: %d vs %d" % (o, c, stripped.count(o), stripped.count(c)))
    try:
        root = parse_plist(pbx_text)
    except PlistError as e:
        return problems + ["parse error: %s" % e]

    objects = root.get("objects", {})
    for key in ("archiveVersion", "objectVersion", "objects", "rootObject"):
        if key not in root:
            problems.append("missing top-level key %s" % key)
    if root.get("rootObject") not in objects:
        problems.append("rootObject not defined")

    for oid_, obj in objects.items():
        if not _ID.match(oid_):
            problems.append("bad object id %r" % oid_)
        if not isinstance(obj, dict) or "isa" not in obj:
            problems.append("object %s has no isa" % oid_)

    def refs(v, path):
        if isinstance(v, dict):
            for k, x in v.items():
                if _ID.match(k):
                    yield k, path + "/" + k
                for r in refs(x, path + "/" + k):
                    yield r
        elif isinstance(v, list):
            for x in v:
                for r in refs(x, path):
                    yield r
        elif isinstance(v, str) and _ID.match(v):
            yield v, path

    for oid_, obj in objects.items():
        for r, where in refs(obj, oid_):
            if r not in objects:
                problems.append("undefined reference %s at %s" % (r, where))

    # Every object other than the root must be reachable from the root.
    seen = set()
    stack = [root.get("rootObject")]
    while stack:
        cur = stack.pop()
        if cur in seen or cur not in objects:
            continue
        seen.add(cur)
        stack.extend(r for r, _ in refs(objects[cur], cur))
    orphans = sorted(set(objects) - seen)
    if orphans:
        problems.append("unreachable objects: %s" % ", ".join(orphans))

    # Sources phase holds exactly the swift files.
    phases = [o for o in objects.values() if o.get("isa") == "PBXSourcesBuildPhase"]
    if len(phases) != 1:
        problems.append("expected 1 PBXSourcesBuildPhase, found %d" % len(phases))
    elif expected_files is not None:
        names = []
        for bf in phases[0].get("files", []):
            fr = objects.get(objects.get(bf, {}).get("fileRef"), {})
            names.append(fr.get("path", "<missing %s>" % bf))
        want = sorted(f.rsplit("/", 1)[-1] for f in expected_files)
        if sorted(names) != want:
            problems.append("sources phase mismatch: %s vs %s" % (sorted(names), want))
    return problems


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def write(path, text):
    d = os.path.dirname(path)
    if not os.path.isdir(d):
        os.makedirs(d)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def main(argv):
    check_only = "--check" in argv
    args = [a for a in argv if a != "--check"]
    if args and args[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    root = os.path.abspath(args[0]) if args else \
        os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    proj = os.path.join(root, PROJECT_NAME + ".xcodeproj")
    pbx_path = os.path.join(proj, "project.pbxproj")

    tree = scan(root)
    files = all_files(tree)
    seen_names = {}
    for f in files:
        b = f.rsplit("/", 1)[-1]
        if b in seen_names:
            sys.stderr.write("error: duplicate Swift file name %s (%s, %s); swiftc rejects this\n"
                             % (b, seen_names[b], f))
            return 1
        seen_names[b] = f

    if check_only:
        with open(pbx_path, encoding="utf-8") as fh:
            problems = validate(fh.read(), files)
    else:
        pbx, target_id = build_pbxproj(tree)
        problems = validate(pbx, files)
        if problems:
            for p in problems:
                sys.stderr.write("error: %s\n" % p)
            sys.stderr.write("refusing to write an invalid project\n")
            return 1
        write(pbx_path, pbx)
        write(os.path.join(proj, "project.xcworkspace", "contents.xcworkspacedata"), WORKSPACE_DATA)
        write(os.path.join(proj, "project.xcworkspace", "xcshareddata", "IDEWorkspaceChecks.plist"),
              WORKSPACE_CHECKS)
        write(os.path.join(proj, "xcshareddata", "xcschemes", TARGET_NAME + ".xcscheme"),
              build_scheme(target_id))

    if problems:
        for p in problems:
            sys.stderr.write("error: %s\n" % p)
        return 1
    print("%s %s (%d Swift files)" % ("validated" if check_only else "wrote",
                                      os.path.relpath(proj, os.getcwd()), len(files)))
    for f in files:
        print("  " + f)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
