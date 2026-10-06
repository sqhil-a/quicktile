#!/usr/bin/env python3
import pathlib, plistlib, subprocess
root=pathlib.Path(__file__).resolve().parent.parent
project=root/'QuickTile.xcodeproj/project.pbxproj'
p=plistlib.loads(subprocess.check_output(['plutil','-convert','xml1','-o','-',str(project)]));o=p['objects']
def uid(n):return f'515454455354544152{n:06X}'
def add(n,**v):o[uid(n)]=v;return uid(n)
for name,host,hostid,sdk,deployment,n,ui in [('QuickTileUITests','QuickTile','BA256987304D203A00DAC88D','iphoneos','18.0',10,True),('QuickTileMacTests','QuickTileMac','515549434B54494C45000028','macosx','14.0',40,False)]:
 ref=add(n,isa='PBXFileReference',explicitFileType='wrapper.cfbundle',path=name+'.xctest',sourceTree='BUILT_PRODUCTS_DIR')
 grp=add(n+1,isa='PBXFileSystemSynchronizedRootGroup',path=name,sourceTree='<group>')
 dep=add(n+2,isa='XCSwiftPackageProductDependency',productName='QuickTileCore')
 build=add(n+3,isa='PBXBuildFile',productRef=dep)
 files=[]
 if not ui:
  for j,filename in enumerate(['MacServer.swift','Catalog.swift','ActionExecutor.swift','VolumeControl.swift','ProcessRunner.swift','AgentStatus.swift','MediaPlayerControl.swift','GroqAssistant.swift','AssistantPlanValidation.swift']):
   fileref=add(200+j*2,isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path='QuickTileMac/'+filename,sourceTree='SOURCE_ROOT')
   files.append(add(201+j*2,isa='PBXBuildFile',fileRef=fileref))
 sources=add(n+4,isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)
 frameworks=add(n+5,isa='PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[build],runOnlyForDeploymentPostprocessing=0)
 resources=add(n+6,isa='PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
 configs=[]
 for i,config in enumerate(['Debug','Release']):
  s=dict(SWIFT_VERSION='5.0',CODE_SIGN_STYLE='Automatic',DEVELOPMENT_TEAM='M26FDHM6XS',PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_BUNDLE_IDENTIFIER='sahil.'+name,GENERATE_INFOPLIST_FILE='YES',SDKROOT=sdk,SWIFT_DEFAULT_ACTOR_ISOLATION='nonisolated')
  if ui:s.update(dict(IPHONEOS_DEPLOYMENT_TARGET=deployment,SUPPORTED_PLATFORMS='iphoneos iphonesimulator',TARGETED_DEVICE_FAMILY='1',TEST_TARGET_NAME=host))
  else:s.update(dict(MACOSX_DEPLOYMENT_TARGET=deployment,SUPPORTED_PLATFORMS='macosx',LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks'))
  configs.append(add(n+7+i,isa='XCBuildConfiguration',name=config,buildSettings=s))
 cl=add(n+9,isa='XCConfigurationList',buildConfigurations=configs,defaultConfigurationName='Release',defaultConfigurationIsVisible=0)
 proxy=add(n+10,isa='PBXContainerItemProxy',containerPortal=p['rootObject'],proxyType=1,remoteGlobalIDString=hostid,remoteInfo=host)
 dependency=add(n+11,isa='PBXTargetDependency',target=hostid,targetProxy=proxy)
 tid=add(n+12,isa='PBXNativeTarget',name=name,productName=name,productReference=ref,productType='com.apple.product-type.bundle.ui-testing' if ui else 'com.apple.product-type.bundle.unit-test',buildConfigurationList=cl,buildPhases=[sources,frameworks,resources],fileSystemSynchronizedGroups=[grp],packageProductDependencies=[dep],dependencies=[dependency],buildRules=[])
 for oid,field,value in [(p['rootObject'],'targets',tid),('BA25697F304D203A00DAC88D','children',grp),('BA256989304D203A00DAC88D','children',ref)]:o[oid][field]=[v for v in o[oid][field] if v!=value]+[value]
 scheme=root/f'QuickTile.xcodeproj/xcshareddata/xcschemes/{host}.xcscheme'
 s=scheme.read_text();import re
 test=f'<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{tid}" BuildableName="{name}.xctest" BlueprintName="{name}" ReferencedContainer="container:QuickTile.xcodeproj"/></TestableReference></Testables></TestAction>'
 s=re.sub(r'<TestAction\b[^>]*(?:/>|>.*?</TestAction>)',lambda _:test,s,flags=re.S);scheme.write_text(s)
project.write_bytes(plistlib.dumps(p,sort_keys=False))
