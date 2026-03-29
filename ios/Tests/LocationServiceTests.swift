import XCTest
import CoreLocation
@testable import libre_location

// MARK: - LocationServiceConfig Tests

final class LocationServiceConfigTests: XCTestCase {

    override func tearDown() {
        LocationServiceConfig.clear()
        super.tearDown()
    }

    func testDefaultValues() {
        let config = LocationServiceConfig()
        XCTAssertEqual(config.accuracy, 0)
        XCTAssertEqual(config.intervalMs, 60000)
        XCTAssertEqual(config.distanceFilter, 10.0)
        XCTAssertEqual(config.mode, 1)
        XCTAssertTrue(config.enableMotionDetection)
        XCTAssertEqual(config.stopTimeout, 5)
        XCTAssertEqual(config.stationaryRadius, 25.0)
        XCTAssertEqual(config.heartbeatInterval, 0)
        XCTAssertFalse(config.pausesLocationUpdatesAutomatically)
        XCTAssertEqual(config.activityType, 0)
        XCTAssertFalse(config.stopOnTerminate)
        XCTAssertFalse(config.keepAwake)
        XCTAssertFalse(config.significantChangesOnly)
        XCTAssertTrue(config.showsBackgroundLocationIndicator)
        XCTAssertTrue(config.locationFilterEnabled)
        XCTAssertEqual(config.maxAccuracy, 100.0)
        XCTAssertEqual(config.maxSpeed, 83.33)
    }

    func testSaveAndLoad() {
        var config = LocationServiceConfig()
        config.accuracy = 2
        config.distanceFilter = 50.0
        config.stopTimeout = 10
        config.heartbeatInterval = 300
        config.keepAwake = true
        config.maxAccuracy = 200.0
        config.maxSpeed = 50.0
        config.save()

        let loaded = LocationServiceConfig.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.accuracy, 2)
        XCTAssertEqual(loaded?.distanceFilter, 50.0)
        XCTAssertEqual(loaded?.stopTimeout, 10)
        XCTAssertEqual(loaded?.heartbeatInterval, 300)
        XCTAssertTrue(loaded?.keepAwake ?? false)
        XCTAssertEqual(loaded?.maxAccuracy, 200.0)
        XCTAssertEqual(loaded?.maxSpeed, 50.0)
    }

    func testClear() {
        var config = LocationServiceConfig()
        config.accuracy = 3
        config.save()

        LocationServiceConfig.clear()
        XCTAssertNil(LocationServiceConfig.load())
    }

    func testLoadReturnsNilWhenNoData() {
        LocationServiceConfig.clear()
        XCTAssertNil(LocationServiceConfig.load())
    }

    func testRoundTripPreservesAllFields() {
        var config = LocationServiceConfig()
        config.accuracy = 4
        config.intervalMs = 30000
        config.distanceFilter = 5.0
        config.mode = 2
        config.enableMotionDetection = false
        config.stopTimeout = 15
        config.stationaryRadius = 100.0
        config.heartbeatInterval = 600
        config.pausesLocationUpdatesAutomatically = true
        config.activityType = 2
        config.stopOnTerminate = true
        config.keepAwake = true
        config.significantChangesOnly = true
        config.showsBackgroundLocationIndicator = false
        config.locationFilterEnabled = false
        config.maxAccuracy = 500.0
        config.maxSpeed = 150.0
        config.save()

        let loaded = LocationServiceConfig.load()!
        XCTAssertEqual(loaded.accuracy, 4)
        XCTAssertEqual(loaded.intervalMs, 30000)
        XCTAssertEqual(loaded.distanceFilter, 5.0)
        XCTAssertEqual(loaded.mode, 2)
        XCTAssertFalse(loaded.enableMotionDetection)
        XCTAssertEqual(loaded.stopTimeout, 15)
        XCTAssertEqual(loaded.stationaryRadius, 100.0)
        XCTAssertEqual(loaded.heartbeatInterval, 600)
        XCTAssertTrue(loaded.pausesLocationUpdatesAutomatically)
        XCTAssertEqual(loaded.activityType, 2)
        XCTAssertTrue(loaded.stopOnTerminate)
        XCTAssertTrue(loaded.keepAwake)
        XCTAssertTrue(loaded.significantChangesOnly)
        XCTAssertFalse(loaded.showsBackgroundLocationIndicator)
        XCTAssertFalse(loaded.locationFilterEnabled)
        XCTAssertEqual(loaded.maxAccuracy, 500.0)
        XCTAssertEqual(loaded.maxSpeed, 150.0)
    }
}

// MARK: - LocationService locationToMap Tests

final class LocationToMapTests: XCTestCase {

    func testLocationToMapBasic() {
        let service = LocationService(onPosition: { _ in })
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.42, longitude: -122.08),
            altitude: 10.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 3.0,
            course: 90.0,
            speed: 2.5,
            timestamp: Date(timeIntervalSince1970: 1000)
        )

        let map = service.locationToMap(location)
        XCTAssertEqual(map["latitude"] as? Double, 37.42)
        XCTAssertEqual(map["longitude"] as? Double, -122.08)
        XCTAssertEqual(map["altitude"] as? Double, 10.0)
        XCTAssertEqual(map["accuracy"] as? Double, 5.0)
        XCTAssertEqual(map["speed"] as? Double, 2.5)
        XCTAssertEqual(map["heading"] as? Double, 90.0)
        XCTAssertEqual(map["timestamp"] as? Int64, 1000000)
        XCTAssertEqual(map["provider"] as? String, "core_location")
    }

    func testNegativeSpeedClampedToZero() {
        let service = LocationService(onPosition: { _ in })
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            course: -1,
            speed: -1,
            timestamp: Date()
        )
        let map = service.locationToMap(location)
        XCTAssertEqual(map["speed"] as? Double, 0.0)
        XCTAssertEqual(map["heading"] as? Double, 0.0)
    }
}

// MARK: - Geofence Distance Calculation Tests

final class GeofenceDistanceTests: XCTestCase {

    func testDistanceBetweenCoordinates() {
        // San Francisco to Los Angeles ~559 km
        let sf = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let la = CLLocation(latitude: 34.0522, longitude: -118.2437)
        let distance = sf.distance(from: la)
        XCTAssertEqual(distance, 559000, accuracy: 10000) // within 10km
    }

    func testInsideGeofence() {
        let center = CLLocation(latitude: 37.42, longitude: -122.08)
        let inside = CLLocation(latitude: 37.4201, longitude: -122.0801)
        let distance = center.distance(from: inside)
        XCTAssertLessThan(distance, 100) // should be within 100m radius
    }

    func testOutsideGeofence() {
        let center = CLLocation(latitude: 37.42, longitude: -122.08)
        let outside = CLLocation(latitude: 37.43, longitude: -122.08)
        let distance = center.distance(from: outside)
        XCTAssertGreaterThan(distance, 100) // ~1.1km away
    }
}
