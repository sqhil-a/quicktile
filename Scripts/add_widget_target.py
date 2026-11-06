#!/usr/bin/env python3
"""Reproducibly add the WidgetKit extension and shared App Intent sources."""
from pathlib import Path
import plistlib, subprocess
root=Path(__file__).resolve().parent.parent
project=root/'QuickTile.xcodeproj/project.pbxproj'
p=plistlib.loads(subprocess.check_output(['plutil','-convert','xml1','-o','-',str(project)]));o=p['objects']
def uid(n): return f'515457494447455453{n:06X}'
def add(n,**v): o[uid(n)]=v;return uid(n)
ref=add(1,isa='PBXFileReference',explicitFileType='wrapper.app-extension',path='QuickTileWidgets.appex',sourceTree='BUILT_PRODUCTS_DIR')
grp=add(2,isa='PBXFileSystemSynchronizedRootGroup',path='QuickTileWidgets',sourceTree='<group>')
shared=add(3,isa='PBXFileSystemSynchronizedRootGroup',path='WidgetShared',sourceTree='<group>')
dep=add(4,isa='XCSwiftPackageProductDependency',productName='QuickTileCore')
link=add(5,isa='PBXBuildFile',productRef=dep)
sources=add(6,isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
frameworks=add(7,isa='PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[link],runOnlyForDeploymentPostprocessing=0)
resources=add(8,isa='PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
configs=[]
for i,name in enumerate(('Debug','Release')):
    settings=dict(SWIFT_VERSION='5.0',SWIFT_DEFAULT_ACTOR_ISOLATION='nonisolated',CODE_SIGN_STYLE='Automatic',DEVELOPMENT_TEAM='M26FDHM6XS',PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_BUNDLE_IDENTIFIER='sahil.QuickTile.Widgets',MARKETING_VERSION='1.0',CURRENT_PROJECT_VERSION='1',SDKROOT='iphoneos',SUPPORTED_PLATFORMS='iphoneos iphonesimulator',IPHONEOS_DEPLOYMENT_TARGET='18.0',TARGETED_DEVICE_FAMILY='1',SUPPORTS_MACCATALYST='NO',APPLICATION_EXTENSION_API_ONLY='YES',SKIP_INSTALL='YES',GENERATE_INFOPLIST_FILE='YES',INFOPLIST_FILE='Configuration/QuickTileWidgets-Info.plist',CODE_SIGN_ENTITLEMENTS='Configuration/QuickTile.entitlements',SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) QUICKTILE_WIDGET_EXTENSION',LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks')
    configs.append(add(10+i,isa='XCBuildConfiguration',name=name,buildSettings=settings))
cl=add(12,isa='XCConfigurationList',buildConfigurations=configs,defaultConfigurationName='Release',defaultConfigurationIsVisible=0)
tid=add(13,isa='PBXNativeTarget',name='QuickTileWidgets',productName='QuickTileWidgets',productReference=ref,productType='com.apple.product-type.app-extension',buildConfigurationList=cl,buildPhases=[sources,frameworks,resources],fileSystemSynchronizedGroups=[grp,shared],packageProductDependencies=[dep],dependencies=[],buildRules=[])
proxy=add(14,isa='PBXContainerItemProxy',containerPortal=p['rootObject'],proxyType=1,remoteGlobalIDString=tid,remoteInfo='QuickTileWidgets')
dependency=add(15,isa='PBXTargetDependency',target=tid,targetProxy=proxy)
embed=add(16,isa='PBXBuildFile',fileRef=ref,settings=dict(ATTRIBUTES=['RemoveHeadersOnCopy']))
phase=add(17,isa='PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embed],name='Embed Widget Extension',runOnlyForDeploymentPostprocessing=0)
app=o['BA256987304D203A00DAC88D']
for field,value in [('dependencies',dependency),('buildPhases',phase),('fileSystemSynchronizedGroups',shared)]: app[field]=[v for v in app.get(field,[]) if v!=value]+[value]
for cid in ['BA256994304D203A00DAC88D','BA256995304D203A00DAC88D']: o[cid]['buildSettings']['CODE_SIGN_ENTITLEMENTS']='Configuration/QuickTile.entitlements'
for oid,field,value in [(p['rootObject'],'targets',tid),('BA25697F304D203A00DAC88D','children',grp),('BA25697F304D203A00DAC88D','children',shared),('BA256989304D203A00DAC88D','children',ref)]: o[oid][field]=[v for v in o[oid][field] if v!=value]+[value]
project.write_bytes(plistlib.dumps(p,sort_keys=False))
(root/'Configuration/QuickTile.entitlements').write_bytes(plistlib.dumps({'com.apple.security.application-groups':['group.sahil.QuickTile']}))
(root/'Configuration/QuickTileWidgets-Info.plist').write_bytes(plistlib.dumps({'NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}}))
