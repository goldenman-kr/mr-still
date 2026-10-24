#!/usr/bin/env python3
"""Generate a dependency-free Xcode app project from the Swift source folders."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

objects = []
def add(name, body):
    objects.append("\n".join(line.rstrip() for line in f'{uid(name)} = {{ {body} }};'.splitlines()))
    return uid(name)

sources = sorted(root.glob('Sources/**/*.swift'))
refs, builds = [], []
for source in sources:
    path = source.relative_to(root).as_posix()
    ref = add(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    builds.append(add(path + '.build', f'isa = PBXBuildFile; fileRef = {ref};'))
plist = add('plist', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Resources/Info.plist; sourceTree = SOURCE_ROOT;')
icon = add('icon', 'isa = PBXFileReference; lastKnownFileType = image.icns; path = Resources/AppIcon.icns; sourceTree = SOURCE_ROOT;')
icon_build = add('icon.build', f'isa = PBXBuildFile; fileRef = {icon};')
localizations = []
for language in ['en', 'ko']:
    path = f'Sources/PhotoViewerCore/Localization/{language}.lproj/Localizable.strings'
    localizations.append(add('strings.' + language, f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = {language}; path = "{path}"; sourceTree = SOURCE_ROOT;'))
strings = add('strings', f'isa = PBXVariantGroup; children = ({",".join(localizations)},); name = Localizable.strings; sourceTree = "<group>";')
strings_build = add('strings.build', f'isa = PBXBuildFile; fileRef = {strings};')
resource_refs, resource_builds = [], []
for filename, filetype in [('PrivacyInfo.xcprivacy', 'text.xml'), ('privacy-policy-en.html', 'text.html'), ('privacy-policy-ko.html', 'text.html')]:
    resource_ref = add(filename, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = Resources/{filename}; sourceTree = SOURCE_ROOT;')
    resource_refs.append(resource_ref)
    resource_builds.append(add(filename + '.build', f'isa = PBXBuildFile; fileRef = {resource_ref};'))
entitlements = add('entitlements', 'isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Resources/AppStore.entitlements; sourceTree = SOURCE_ROOT;')
app = add('app', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = "Mr. Still.app"; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products', f'isa = PBXGroup; children = ({app},); name = Products; sourceTree = "<group>";')
main = add('main', f'isa = PBXGroup; children = ({",".join(refs + [plist, icon, strings, entitlements] + resource_refs + [products])},); sourceTree = "<group>";')
phase = add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks = add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
resources = add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join([icon_build, strings_build] + resource_builds)},); runOnlyForDeploymentPostprocessing = 0;')
project_configs, target_configs = [], []
for config in ['Debug', 'Release', 'AppStoreDebug', 'AppStore']:
    is_debug = config in ['Debug', 'AppStoreDebug']
    is_store = config.startswith('AppStore')
    conditions = ' '.join((['DEBUG'] if is_debug else []) + (['APP_STORE'] if is_store else []))
    store_settings = 'CODE_SIGN_ENTITLEMENTS = Resources/AppStore.entitlements; ENABLE_USER_SELECTED_FILES = readwrite; ENABLE_RESOURCE_ACCESS_PRINTING = YES;' if is_store else ''
    project_configs.append(add('project.' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 14.0; CLANG_ENABLE_MODULES = YES; }};'))
    optimize = '-Onone' if is_debug else '-O'
    target_configs.append(add('target.' + config, f'''isa = XCBuildConfiguration; name = {config}; buildSettings = {{
      PRODUCT_NAME = "Mr. Still"; PRODUCT_BUNDLE_IDENTIFIER = "photoviewer.app.kryp.xyz";
      INFOPLIST_FILE = Resources/Info.plist; GENERATE_INFOPLIST_FILE = NO; SWIFT_VERSION = 5.0;
      SWIFT_OPTIMIZATION_LEVEL = "{optimize}"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "{conditions}";
      CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; ENABLE_APP_SANDBOX = {"YES" if is_store else "NO"};
      {store_settings}
      ARCHS = "$(ARCHS_STANDARD)"; ONLY_ACTIVE_ARCH = {"YES" if is_debug else "NO"};
      SKIP_INSTALL = NO; INSTALL_PATH = "$(LOCAL_APPS_DIR)";
      DEBUG_INFORMATION_FORMAT = "{"dwarf" if is_debug else "dwarf-with-dsym"}";
      ENABLE_HARDENED_RUNTIME = YES; COMBINE_HIDPI_IMAGES = YES;
    }};'''))
pc = add('project.configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tc = add('target.configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = add('target', f'isa = PBXNativeTarget; name = PhotoViewer; productName = "Mr. Still"; productReference = {app}; productType = "com.apple.product-type.application"; buildConfigurationList = {tc}; buildPhases = ({phase},{frameworks},{resources},); buildRules = (); dependencies = ();')
project = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (ko,en,Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
folder = root / 'PhotoViewer.xcodeproj'
folder.mkdir(exist_ok=True)
(folder / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project}; }}\n')
print(f'Generated project with {len(sources)} Swift files.')

# Explicit shared schemes make local and CI archives reproducible.
schemes = folder / 'xcshareddata' / 'xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
for scheme, debug_config, release_config in [('PhotoViewer', 'Debug', 'Release'), ('PhotoViewer-AppStore', 'AppStoreDebug', 'AppStore')]:
    reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Mr. Still.app" BlueprintName="PhotoViewer" ReferencedContainer="container:PhotoViewer.xcodeproj"/>'
    xml = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="{debug_config}" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="{debug_config}" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="{release_config}" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="{debug_config}"/>
  <ArchiveAction buildConfiguration="{release_config}" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (schemes / f'{scheme}.xcscheme').write_text(xml)
