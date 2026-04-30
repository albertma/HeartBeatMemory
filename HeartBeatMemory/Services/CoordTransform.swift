//
//  CoordType.swift
//  HeartBeatMemory
//
//  Created by albertma on 2026/4/29.
//


import Foundation
import CoreLocation

enum CoordType {
    case wgs84
    case gcj02
    case bd09
}

struct Coordinate {
    var lat: Double
    var lng: Double
    var type: CoordType
}

class CoordTransform {

    static let a = 6378245.0
    static let ee = 0.00669342162296594323

    static func outOfChina(_ lat: Double, _ lng: Double) -> Bool {
        return !(lng > 72.004 && lng < 137.8347 && lat > 0.8293 && lat < 55.8271)
    }

    static func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0*x + 3.0*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        ret += (20.0*sin(6.0*x*Double.pi) + 20.0*sin(2.0*x*Double.pi)) * 2.0/3.0
        ret += (20.0*sin(y*Double.pi) + 40.0*sin(y/3.0*Double.pi)) * 2.0/3.0
        ret += (160.0*sin(y/12.0*Double.pi) + 320*sin(y*Double.pi/30.0)) * 2.0/3.0
        return ret
    }

    static func transformLng(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        ret += (20.0*sin(6.0*x*Double.pi) + 20.0*sin(2.0*x*Double.pi)) * 2.0/3.0
        ret += (20.0*sin(x*Double.pi) + 40.0*sin(x/3.0*Double.pi)) * 2.0/3.0
        ret += (150.0*sin(x/12.0*Double.pi) + 300.0*sin(x/30.0*Double.pi)) * 2.0/3.0
        return ret
    }

    static func wgs84ToGcj02(_ coord: Coordinate) -> Coordinate {
        if outOfChina(coord.lat, coord.lng) {
            return coord
        }

        let dLat = transformLat(coord.lng - 105.0, coord.lat - 35.0)
        let dLng = transformLng(coord.lng - 105.0, coord.lat - 35.0)

        let radLat = coord.lat / 180.0 * Double.pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)

        let mgLat = coord.lat + (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * Double.pi)
        let mgLng = coord.lng + (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * Double.pi)

        return Coordinate(lat: mgLat, lng: mgLng, type: .gcj02)
    }
}