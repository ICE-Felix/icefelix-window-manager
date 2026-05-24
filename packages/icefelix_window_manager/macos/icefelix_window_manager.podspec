Pod::Spec.new do |s|
  s.name             = 'icefelix_window_manager'
  s.version          = '0.3.0'
  s.summary          = 'Cross-platform window management for Flutter desktop.'
  s.description      = <<-DESC
Single Flutter plugin (macOS + Windows native) for desktop window
management. Wraps NSWindow / AppKit on macOS via Pigeon-typed channels.
                       DESC
  s.homepage         = 'https://github.com/ICE-Felix/icefelix-window-manager'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'icefelix.com' => 'alex.bordei@icefelix.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
