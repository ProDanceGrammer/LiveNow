Pod::Spec.new do |s|
  s.name             = 'livenow_clipboard'
  s.version          = '0.0.1'
  s.summary          = 'Reads all images on the iOS clipboard.'
  s.description      = 'Reads all images on the iOS clipboard.'
  s.homepage         = 'http://example.com'
  s.license          = { :type => 'Private' }
  s.author           = { 'LiveNow' => 'none@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'livenow_clipboard/Sources/livenow_clipboard/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
