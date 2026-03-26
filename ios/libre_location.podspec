Pod::Spec.new do |s|
  s.name             = 'libre_location'
  s.version          = '0.1.0'
  s.summary          = 'Background location tracking without Google Play Services.'
  s.description      = <<-DESC
A Flutter plugin for background location tracking using pure platform APIs.
CoreLocation on iOS, AOSP LocationManager on Android. No proprietary SDKs.
                       DESC
  s.homepage         = 'https://github.com/Rezivure/libre-location'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'Rezivure' => 'developer@rezivure.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'

  s.frameworks       = 'CoreLocation', 'CoreMotion'

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/**/*'
    test_spec.frameworks   = 'XCTest', 'CoreLocation'
  end

  # Required Info.plist keys (must be added by the host app):
  #   NSLocationAlwaysAndWhenInUseUsageDescription
  #   NSLocationWhenInUseUsageDescription
  #   NSMotionUsageDescription
  #   UIBackgroundModes: [location]
end
