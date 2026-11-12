#!/usr/bin/env python3
"""Small deterministic native app wrapper around the pinned local Swift package."""
import pathlib
import shutil
ROOT = pathlib.Path(__file__).resolve().parents[1]
project = ROOT / 'Veylume.xcodeproj'
project.mkdir(exist_ok=True)
(project / 'project.pbxproj').write_text('''// !$*UTF8*$!
{ archiveVersion = 1; classes = {}; objectVersion = 60;
objects = {
000000000000000000000001 = {isa = PBXProject; attributes = {LastUpgradeCheck = 2700;}; buildConfigurationList = 000000000000000000000010; compatibilityVersion = "Xcode 15.0"; developmentRegion = en; knownRegions = (en, ru, es, fr, Base); mainGroup = 000000000000000000000002; packageReferences = (000000000000000000000020); productRefGroup = 000000000000000000000003; projectDirPath = ""; projectRoot = ""; targets = (000000000000000000000004);};
000000000000000000000002 = {isa = PBXGroup; children = (000000000000000000000005,000000000000000000000006,000000000000000000000007,000000000000000000000008,000000000000000000000009,000000000000000000000050,000000000000000000000003); sourceTree = "<group>";};
000000000000000000000003 = {isa = PBXGroup; children = (00000000000000000000000A); name = Products; sourceTree = "<group>";};
000000000000000000000004 = {isa = PBXNativeTarget; buildConfigurationList = 000000000000000000000011; buildPhases = (000000000000000000000030,000000000000000000000031,000000000000000000000032); buildRules = (); dependencies = (); name = Veylume; packageProductDependencies = (000000000000000000000021); productName = Veylume; productReference = 00000000000000000000000A; productType = "com.apple.product-type.application";};
000000000000000000000005 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Veylume/App/main.swift; sourceTree = "<group>";};
000000000000000000000006 = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Configuration/Info.plist; sourceTree = "<group>";};
000000000000000000000007 = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Configuration/Development.xcconfig; sourceTree = "<group>";};
000000000000000000000008 = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Configuration/Release.xcconfig; sourceTree = "<group>";};
000000000000000000000009 = {isa = PBXFileReference; lastKnownFileType = image.icns; path = Configuration/AppIcon.icns; sourceTree = "<group>";};
00000000000000000000000A = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Veylume.app; sourceTree = BUILT_PRODUCTS_DIR;};
000000000000000000000010 = {isa = XCConfigurationList; buildConfigurations = (000000000000000000000012,000000000000000000000013); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
000000000000000000000011 = {isa = XCConfigurationList; buildConfigurations = (000000000000000000000014,000000000000000000000015); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
000000000000000000000012 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = macosx; CLANG_ENABLE_MODULES = YES;}; name = Debug;};
000000000000000000000013 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = macosx; CLANG_ENABLE_MODULES = YES;}; name = Release;};
000000000000000000000014 = {isa = XCBuildConfiguration; baseConfigurationReference = 000000000000000000000007; buildSettings = {SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; SWIFT_OPTIMIZATION_LEVEL = "-Onone";}; name = Debug;};
000000000000000000000015 = {isa = XCBuildConfiguration; baseConfigurationReference = 000000000000000000000008; buildSettings = {}; name = Release;};
000000000000000000000020 = {isa = XCLocalSwiftPackageReference; relativePath = .;};
000000000000000000000021 = {isa = XCSwiftPackageProductDependency; package = 000000000000000000000020; productName = VeylumeKit;};
000000000000000000000030 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (000000000000000000000040); runOnlyForDeploymentPostprocessing = 0;};
000000000000000000000031 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (000000000000000000000041); runOnlyForDeploymentPostprocessing = 0;};
000000000000000000000032 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (000000000000000000000042,000000000000000000000043); runOnlyForDeploymentPostprocessing = 0;};
000000000000000000000040 = {isa = PBXBuildFile; fileRef = 000000000000000000000005;};
000000000000000000000041 = {isa = PBXBuildFile; productRef = 000000000000000000000021;};
000000000000000000000042 = {isa = PBXBuildFile; fileRef = 000000000000000000000009;};
000000000000000000000043 = {isa = PBXBuildFile; fileRef = 000000000000000000000050;};
000000000000000000000050 = {isa = PBXVariantGroup; children = (000000000000000000000051,000000000000000000000052,000000000000000000000053,000000000000000000000054); name = InfoPlist.strings; sourceTree = "<group>";};
000000000000000000000051 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = en; path = Configuration/en.lproj/InfoPlist.strings; sourceTree = "<group>";};
000000000000000000000052 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = ru; path = Configuration/ru.lproj/InfoPlist.strings; sourceTree = "<group>";};
000000000000000000000053 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = es; path = Configuration/es.lproj/InfoPlist.strings; sourceTree = "<group>";};
000000000000000000000054 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = fr; path = Configuration/fr.lproj/InfoPlist.strings; sourceTree = "<group>";};
}; rootObject = 000000000000000000000001; }
''')
scheme = project / 'xcshareddata/xcschemes'; scheme.mkdir(parents=True, exist_ok=True)
(scheme / 'Veylume.xcscheme').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="000000000000000000000004" BuildableName="Veylume.app" BlueprintName="Veylume" ReferencedContainer="container:Veylume.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="000000000000000000000004" BuildableName="Veylume.app" BlueprintName="Veylume" ReferencedContainer="container:Veylume.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="000000000000000000000004" BuildableName="Veylume.app" BlueprintName="Veylume" ReferencedContainer="container:Veylume.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
lockdir = project / 'project.xcworkspace/xcshareddata/swiftpm'; lockdir.mkdir(parents=True, exist_ok=True)
if (ROOT / 'Package.resolved').exists(): shutil.copyfile(ROOT / 'Package.resolved', lockdir / 'Package.resolved')
