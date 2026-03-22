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
end
