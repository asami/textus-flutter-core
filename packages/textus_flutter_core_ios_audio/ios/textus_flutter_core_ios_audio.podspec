Pod::Spec.new do |s|
  s.name             = 'textus_flutter_core_ios_audio'
  s.version          = '0.0.1'
  s.summary          = 'Textus audio, transient speech input and on-device text cleanup.'
  s.description      = 'Session-owned recording, PCM replay, local speech and explicit Foundation Models text cleanup.'
  s.homepage         = 'https://github.com/asami/textus-flutter-core'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Textus' => 'https://github.com/asami' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.5'
  s.swift_version    = '5.0'
  s.frameworks       = 'AVFoundation', 'Speech'
  s.weak_frameworks  = 'FoundationModels'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
