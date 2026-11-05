Pod::Spec.new do |s|
  s.name             = 'textus_flutter_core_native_authentication'
  s.version          = '0.0.1'
  s.summary          = 'Internal opaque native authentication credential storage.'
  s.description      = 'Device-bound Keychain storage with revision comparisons and handle drain.'
  s.homepage         = 'https://github.com/asami/textus-flutter-core'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Textus' => 'https://github.com/asami' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.5'
  s.swift_version    = '5.0'
  s.frameworks       = 'Security'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
