import Foundation

struct SunPosition {
    var elevation: Double     // degrees above the horizon
    var rising: Bool          // before solar noon
    var maxElevation: Double  // today's highest point
}

/// NOAA's low-precision solar position, accurate to well under a degree. No location permission needed.
func sunPosition(at date: Date, latitude: Double, longitude: Double) -> SunPosition {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let day = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
    let c = cal.dateComponents([.hour, .minute, .second], from: date)
    let hour = Double(c.hour!) + Double(c.minute!) / 60 + Double(c.second!) / 3600

    let g = 2 * Double.pi / 365 * (day - 1 + (hour - 12) / 24)
    let eqTime = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g)
                           - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
    let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g)
             + 0.000907 * sin(2 * g) - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)

    let trueSolarMinutes = hour * 60 + eqTime + 4 * longitude
    var hourAngle = trueSolarMinutes / 4 - 180
    hourAngle = (hourAngle + 540).truncatingRemainder(dividingBy: 360) - 180

    let lat = latitude * .pi / 180
    let ha = hourAngle * .pi / 180
    let cosZenith = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha)
    let elevation = 90 - acos(max(-1, min(1, cosZenith))) * 180 / .pi
    let maxElevation = 90 - abs(latitude - decl * 180 / .pi)

    return SunPosition(elevation: elevation, rising: hourAngle < 0, maxElevation: maxElevation)
}
