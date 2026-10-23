#!/usr/bin/env python3
"""Generate a dependency-free Xcode app project from the Swift source folders."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

objects = []
def add(name, body):
    objects.append(f'{uid(name)} = {{ {body} }};')
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
app = add('app', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = "Mr. Still.app"; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products', f'isa = PBXGroup; children = ({app},); name = Products; sourceTree = "<group>";')
main = add('main', f'isa = PBXGroup; children = ({",".join(refs + [plist, icon, products])},); sourceTree = "<group>";')
phase = add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks = add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
resources = add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({icon_build},); runOnlyForDeploymentPostprocessing = 0;')
project_configs, target_configs = [], []
for config in ['Debug', 'Release']:
    project_configs.append(add('project.' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 14.0; CLANG_ENABLE_MODULES = YES; }};'))
    optimize = '-Onone' if config == 'Debug' else '-O'
    target_configs.append(add('target.' + config, f'''isa = XCBuildConfiguration; name = {config}; buildSettings = {{
      PRODUCT_NAME = "Mr. Still"; PRODUCT_BUNDLE_IDENTIFIER = "photoviewer.app.kryp.xyz";
      INFOPLIST_FILE = Resources/Info.plist; GENERATE_INFOPLIST_FILE = NO; SWIFT_VERSION = 5.0;
      SWIFT_OPTIMIZATION_LEVEL = "{optimize}"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "{'DEBUG' if config == 'Debug' else ''}";
      CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; ENABLE_APP_SANDBOX = NO;
      ENABLE_HARDENED_RUNTIME = YES; COMBINE_HIDPI_IMAGES = YES;
    }};'''))
pc = add('project.configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tc = add('target.configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = add('target', f'isa = PBXNativeTarget; name = PhotoViewer; productName = "Mr. Still"; productReference = {app}; productType = "com.apple.product-type.application"; buildConfigurationList = {tc}; buildPhases = ({phase},{frameworks},{resources},); buildRules = (); dependencies = ();')
project = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ko; knownRegions = (ko,en,Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
folder = root / 'PhotoViewer.xcodeproj'
folder.mkdir(exist_ok=True)
(folder / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project}; }}\n')
print(f'Generated project with {len(sources)} Swift files.')
