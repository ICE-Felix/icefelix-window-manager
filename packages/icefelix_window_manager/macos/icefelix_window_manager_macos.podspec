Pod::Spec.new do |s|
  s.name             = 'icefelix_window_manager_macos'
  s.version          = '0.1.0'
  s.summary          = 'macOS impl of icefelix_window_manager (NSWindow + AppKit).'
  s.description      = <<-DESC
macOS platform implementation for icefelix_window_manager. Wraps NSWindow,
NSScreen, and NSWindowDelegate via Pigeon-typed channels.
                       DESC
  s.homepage         = 'https://icefelix.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'icefelix.com' => 'alex.bordei@icefelix.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
