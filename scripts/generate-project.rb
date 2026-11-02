#!/usr/bin/env ruby
# Run from any directory with the xcodeproj gem installed.
require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'Moley.xcodeproj'))
config = project.main_group.new_file('Config/Project.xcconfig')
project.build_configurations.each do |build|
  build.base_configuration_reference = config
  build.build_settings['SDKROOT'] = 'iphoneos'
  build.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
end

app = project.new_target(:application, 'Moley', :ios, '17.0')
tunnel = project.new_target(:app_extension, 'MoleyTunnel', :ios, '17.0')
tests = project.new_target(:unit_test_bundle, 'MoleyTests', :ios, '17.0')
ui_tests = project.new_target(:ui_test_bundle, 'MoleyUITests', :ios, '17.0')
bridge = project.new_aggregate_target('WireGuardGoBridge')
bridge.build_configurations.each do |build|
  build.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
  build.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
end
phase = bridge.new_shell_script_build_phase('Build WireGuard Go backend')
phase.shell_script = 'bash "${SRCROOT}/scripts/build-wireguard.sh"'
phase.always_out_of_date = '1'

vendor = project.main_group.new_group('WireGuardKit', 'Vendor/WireGuard/Sources')
%w[WireGuardKit/*.swift WireGuardKitC/*.c].each do |pattern|
  Dir.glob(File.join(root, 'Vendor/WireGuard/Sources', pattern)).sort.each do |path|
    reference = vendor.new_file(path.sub(File.join(root, 'Vendor/WireGuard/Sources/'), ''))
    [app, tunnel].each { |target| target.source_build_phase.add_file_reference(reference) }
  end
end

groups = {}
%w[App Shared Tunnel Tests UITests].each do |folder|
  groups[folder] = project.main_group.new_group(folder, folder)
end
%w[App Shared Tunnel Tests UITests].each do |folder|
  Dir.glob(File.join(root, folder, '*.swift')).sort.each do |path|
    reference = groups[folder].new_file(File.basename(path))
    targets = case folder
              when 'App' then [app]
              when 'Shared' then [app, tunnel]
              when 'Tunnel' then [tunnel]
              when 'Tests' then [tests]
              when 'UITests' then [ui_tests]
              end
    targets.each { |target| target.source_build_phase.add_file_reference(reference) }
  end
end

assets = groups['App'].new_file('Assets.xcassets')
app.resources_build_phase.add_file_reference(assets)
app.build_configurations.each do |build|
  build.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
end

[app, tunnel].each do |target|
  target.add_dependency(bridge)
  target.build_configurations.each do |build|
    build.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'Config/WireGuard-Bridging-Header.h'
    build.build_settings['OTHER_LDFLAGS'] = '$(inherited) -lwg-go -lresolv'
  end
end
app.add_dependency(tunnel)
embed = app.new_copy_files_build_phase('Embed VPN Extension')
embed.dst_subfolder_spec = '13'
embedded = embed.add_file_reference(tunnel.product_reference)
embedded.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

{ app => '$(MOLEY_BUNDLE_ID)', tunnel => '$(MOLEY_BUNDLE_ID).tunnel',
  tests => '$(MOLEY_BUNDLE_ID).tests', ui_tests => '$(MOLEY_BUNDLE_ID).uitests' }.each do |target, bundle_id|
  target.build_configurations.each do |build|
    build.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
    build.build_settings['SWIFT_VERSION'] = '5.0'
    build.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    build.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    build.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    build.build_settings['ENABLE_BITCODE'] = 'NO'
    build.build_settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
    if [app, tunnel].include?(target)
      build.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Config/Moley.entitlements'
      build.build_settings['INFOPLIST_FILE'] = target == app ? 'Config/App-Info.plist' : 'Config/Tunnel-Info.plist'
      build.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    end
  end
end
tunnel.build_configurations.each do |build|
  build.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  build.build_settings['SKIP_INSTALL'] = 'YES'
end
tests.add_dependency(app)
tests.build_configurations.each do |build|
  build.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Moley.app/Moley'
  build.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
ui_tests.add_dependency(app)
ui_tests.build_configurations.each { |build| build.build_settings['TEST_TARGET_NAME'] = 'Moley' }

%w[Config scripts docs].each { |folder| project.main_group.new_group(folder, folder) }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.add_test_target(ui_tests)
scheme.save_as(project.path, 'Moley', true)
puts "Generated #{project.path}"
