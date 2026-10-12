#!/usr/bin/env python3
"""One-time, deterministic addition to the existing CocoaPods project; no project regeneration."""
from pathlib import Path
p = Path(__file__).resolve().parents[2] / 'frontend/ios/App/App.xcodeproj/project.pbxproj'
s = p.read_text()
if 'AC0000000000000000000001' in s:
    raise SystemExit('Test targets already registered; do not regenerate user project changes.')
def add(section, text):
    global s
    end = f'/* End {section} section */'
    if end in s:
        s = s.replace(end, text + '\n' + end)
    else:
        s = s.replace('/* Begin PBXBuildFile section */', f'/* Begin {section} section */\n{text}\n{end}\n\n/* Begin PBXBuildFile section */')
# Source reference + build membership for the production helper.
add('PBXFileReference', '\t\tAB0000000000000000000007 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShellGeometry.swift; sourceTree = "<group>"; };')
add('PBXBuildFile', '\t\tAB0000000000000000000008 = {isa = PBXBuildFile; fileRef = AB0000000000000000000007; };')
s = s.replace('AB0000000000000000000001 /* OpenGymBridgeViewController.swift */,', 'AB0000000000000000000007 /* ShellGeometry.swift */,\n\t\t\t\tAB0000000000000000000001 /* OpenGymBridgeViewController.swift */,')
s = s.replace('AB0000000000000000000002 /* OpenGymBridgeViewController.swift in Sources */,', 'AB0000000000000000000008 /* ShellGeometry.swift in Sources */,\n\t\t\t\tAB0000000000000000000002 /* OpenGymBridgeViewController.swift in Sources */,')
for prefix, name, file, product in [('AC', 'AppleShellTests', 'ShellGeometryTests.swift', 'bundle.unit-test'), ('AD', 'OpenGymUITests', 'StandaloneSmokeTests.swift', 'bundle.ui-testing')]:
    ident = lambda n: prefix + f'{n:022X}'
    target, group, ref, build, prod, sources, resources, frameworks, cfgs, debug, release, dep, proxy = [ident(n) for n in range(1,14)]
    add('PBXFileReference', f'\t\t{ref} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file}; sourceTree = "<group>"; }};\n\t\t{prod} = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = {name}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
    add('PBXBuildFile', f'\t\t{build} = {{isa = PBXBuildFile; fileRef = {ref}; }};')
    add('PBXGroup', f'\t\t{group} = {{isa = PBXGroup; children = ({ref},); path = {name}; sourceTree = "<group>"; }};')
    s = s.replace('504EC3061FED79650016851F /* App */,', f'{group} /* {name} */,\n\t\t\t\t504EC3061FED79650016851F /* App */,')
    s = s.replace('504EC3041FED79650016851F /* App.app */,', f'{prod} /* {name}.xctest */,\n\t\t\t\t504EC3041FED79650016851F /* App.app */,')
    add('PBXSourcesBuildPhase', f'\t\t{sources} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({build},); runOnlyForDeploymentPostprocessing = 0; }};')
    add('PBXResourcesBuildPhase', f'\t\t{resources} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};')
    add('PBXFrameworksBuildPhase', f'\t\t{frameworks} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};')
    add('PBXContainerItemProxy', f'\t\t{proxy} = {{isa = PBXContainerItemProxy; containerPortal = 504EC2FC1FED79650016851F; proxyType = 1; remoteGlobalIDString = 504EC3031FED79650016851F; remoteInfo = App; }};')
    add('PBXTargetDependency', f'\t\t{dep} = {{isa = PBXTargetDependency; target = 504EC3031FED79650016851F; targetProxy = {proxy}; }};')
    add('PBXNativeTarget', f'\t\t{target} = {{isa = PBXNativeTarget; buildConfigurationList = {cfgs}; buildPhases = ({sources}, {frameworks}, {resources},); buildRules = (); dependencies = ({dep},); name = {name}; productName = {name}; productReference = {prod}; productType = "com.apple.product-type.{product}"; }};')
    s = s.replace('targets = (\n', f'targets = (\n\t\t\t\t{target} /* {name} */,\n', 1)
    for cfg, config_name in [(debug,'Debug'), (release,'Release')]:
        host = 'BUNDLE_LOADER = "$(TEST_HOST)"; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/App.app/App";' if prefix=='AC' else 'TEST_TARGET_NAME = App;'
        add('XCBuildConfiguration', f'\t\t{cfg} = {{isa = XCBuildConfiguration; buildSettings = {{CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; PRODUCT_BUNDLE_IDENTIFIER = "com.example.opengym.{name}"; PRODUCT_NAME = "$(TARGET_NAME)"; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = 1; {host}}}; name = {config_name}; }};')
    add('XCConfigurationList', f'\t\t{cfgs} = {{isa = XCConfigurationList; buildConfigurations = ({debug}, {release},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};')
p.write_text(s)
scheme = p.parent / 'xcshareddata/xcschemes/OpenGym.xcscheme'
text = scheme.read_text()
tests = ''.join(f'<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{prefix}0000000000000000000001" BuildableName="{name}.xctest" BlueprintName="{name}" ReferencedContainer="container:App.xcodeproj"/></TestableReference>' for prefix,name in [('AC','AppleShellTests'),('AD','OpenGymUITests')])
text = text.replace('<Testables/>', f'<Testables>{tests}</Testables>')
scheme.write_text(text)
