#!/usr/bin/env python3
"""Add reproducible companion and package references to the original Xcode starter."""
import pathlib, plistlib
root = pathlib.Path(__file__).resolve().parent.parent
project = root / 'QuickTile.xcodeproj/project.pbxproj'
import subprocess
raw = subprocess.check_output(['plutil', '-convert', 'xml1', '-o', '-', str(project)])
p = plistlib.loads(raw); o = p['objects']
def uid(n): return f'515549434B54494C45{n:06X}'
def add(n, **values): o[uid(n)] = values; return uid(n)
original = o['BA256987304D203A00DAC88D']
package = add(1, isa='XCLocalSwiftPackageReference', relativePath='Shared')
p['objects'][p['rootObject']]['packageReferences'] = [package]
for target, group, product, n in [('QuickTile','QuickTile','QuickTile.app',10), ('QuickTileMac','QuickTileMac','QuickTileMac.app',30)]:
    dep = add(n, isa='XCSwiftPackageProductDependency', productName='QuickTileCore')
    build = add(n+1, isa='PBXBuildFile', productRef=dep)
    if target == 'QuickTile':
        original['packageProductDependencies'] = [dep]
        o['BA256985304D203A00DAC88D']['files'] = [build]
        configs = ['BA256994304D203A00DAC88D','BA256995304D203A00DAC88D']
    else:
        ref = add(n+2, isa='PBXFileReference', explicitFileType='wrapper.application', path=product, sourceTree='BUILT_PRODUCTS_DIR')
        grp = add(n+3, isa='PBXFileSystemSynchronizedRootGroup', path=group, sourceTree='<group>')
        sources = add(n+4, isa='PBXSourcesBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
        frameworks = add(n+5, isa='PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[build], runOnlyForDeploymentPostprocessing=0)
        resources = add(n+6, isa='PBXResourcesBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
        helper = add(153, isa='PBXShellScriptBuildPhase', buildActionMask=2147483647, files=[], inputPaths=['$(SRCROOT)/Scripts/build-agent-helper.sh','$(SRCROOT)/Scripts/AgentEventHelper.swift','$(SRCROOT)/Shared/Sources/QuickTileCore/AgentActivity.swift'], outputPaths=['$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/QuickTileAgentEvent','$(DERIVED_FILE_DIR)/QuickTileAgentHelper'], runOnlyForDeploymentPostprocessing=0, shellPath='/bin/sh', shellScript='/bin/sh "$SRCROOT/Scripts/build-agent-helper.sh"')
        configs = [add(n+7+i, isa='XCBuildConfiguration', name=name, buildSettings={}) for i,name in enumerate(['Debug','Release'])]
        configlist = add(n+9, isa='XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')
        targetid = add(n+10, isa='PBXNativeTarget', name=target, productName=target, productReference=ref, productType='com.apple.product-type.application', buildConfigurationList=configlist, buildPhases=[sources,frameworks,resources,helper], fileSystemSynchronizedGroups=[grp], packageProductDependencies=[dep], buildRules=[])
        o[p['rootObject']]['targets'] = [v for v in o[p['rootObject']]['targets'] if v != targetid] + [targetid]
        for oid, field, value in [('BA25697F304D203A00DAC88D','children',grp),('BA256989304D203A00DAC88D','children',ref)]:
            o[oid][field] = [v for v in o[oid][field] if v != value] + [value]
    for cid in configs:
        s = o[cid]['buildSettings']
        s.update(dict(SWIFT_VERSION='5.0', SWIFT_DEFAULT_ACTOR_ISOLATION='nonisolated', SWIFT_APPROACHABLE_CONCURRENCY='NO', CODE_SIGN_STYLE='Automatic', DEVELOPMENT_TEAM='M26FDHM6XS', MARKETING_VERSION='1.0', CURRENT_PROJECT_VERSION='1', PRODUCT_NAME='$(TARGET_NAME)', GENERATE_INFOPLIST_FILE='YES', ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon', INFOPLIST_FILE=f'Configuration/{target}-Info.plist'))
        if target == 'QuickTile':
            s.update(dict(SDKROOT='iphoneos', SUPPORTED_PLATFORMS='iphoneos iphonesimulator', IPHONEOS_DEPLOYMENT_TARGET='18.0', TARGETED_DEVICE_FAMILY='1', SUPPORTS_MACCATALYST='NO', SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD='NO'))
            for k in ['MACOSX_DEPLOYMENT_TARGET','XROS_DEPLOYMENT_TARGET','REGISTER_APP_GROUPS','ENABLE_APP_SANDBOX','ENABLE_USER_SELECTED_FILES']: s.pop(k,None)
        else:
            s.update(dict(SDKROOT='macosx', SUPPORTED_PLATFORMS='macosx', MACOSX_DEPLOYMENT_TARGET='14.0', PRODUCT_BUNDLE_IDENTIFIER='sahil.QuickTile.Mac', ENABLE_APP_SANDBOX='NO', ENABLE_USER_SCRIPT_SANDBOXING='NO', ENABLE_HARDENED_RUNTIME='YES', CODE_SIGN_ENTITLEMENTS='Configuration/QuickTileMac.entitlements', LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/../Frameworks'))
project.write_bytes(plistlib.dumps(p, fmt=plistlib.FMT_XML, sort_keys=False))
subprocess.run(['plutil','-convert','openstep', str(project)], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
shared = root / 'QuickTile.xcodeproj/xcshareddata/xcschemes'; shared.mkdir(parents=True,exist_ok=True)
for name,tid in [('QuickTile','BA256987304D203A00DAC88D'),('QuickTileMac',uid(40))]:
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{tid}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:QuickTile.xcodeproj"/>'
    (shared / f'{name}.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
