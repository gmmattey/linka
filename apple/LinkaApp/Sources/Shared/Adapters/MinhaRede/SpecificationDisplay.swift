import Foundation
import NetworkInventory

/// Display typed wire values as readable capabilities, never raw JSON or measured results.
enum SpecificationDisplay {
    static func value(_ attribute: SpecificationAttribute) -> String {
        let values = attribute.value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        switch attribute.key {
        case "deviceKind": return LinkaCopy.value("inventory.kind.\(attribute.value)")
        case "meshTechnology": return ["easyMesh": "EasyMesh", "oneMesh": "OneMesh", "aiMesh": "AiMesh", "orbi": "Orbi", "deco": "Deco", "eero": "eero", "velop": "Velop"][attribute.value] ?? LinkaCopy.value(attribute.value == "other" ? "inventory.kind.other" : "inventory.unknown")
        case "firmwareSupportStatus": return LinkaCopy.value("inventory.firmware.\(attribute.value)")
        case "supportsMesh": return LinkaCopy.value("inventory.answer.\(attribute.value == "true" ? "yes" : "no")")
        case "supportedModes": return values.map { ($0 == "router" ? LinkaCopy.value("inventory.capability.router") : LinkaCopy.value("inventory.role.\($0)")) }.joined(separator: ", ")
        case "wanMedia", "supportedBackhaul", "fiberTermination": return values.map { LinkaCopy.value("inventory.capability.\($0)") }.joined(separator: ", ")
        case "radioCapabilities":
            struct Radio: Decodable { var bandGHz: Double; var maxChannelWidthMHz: Double?; var maxPhyRateMbps: Double?; var spatialStreams: Int? }
            guard let rows = try? JSONDecoder().decode([Radio].self, from: Data(attribute.value.utf8)) else { return LinkaCopy.value("inventory.unknown") }
            return rows.map { row in
                var parts = ["\(number(row.bandGHz)) GHz"]
                if let n = row.maxChannelWidthMHz { parts.append("\(number(n)) MHz") }
                if let n = row.maxPhyRateMbps { parts.append("\(number(n)) Mbps PHY") }
                if let n = row.spatialStreams { parts.append("\(n) " + LinkaCopy.value("inventory.capability.streams")) }
                return parts.joined(separator: " · ")
            }.joined(separator: "\n")
        case "ethernetPorts":
            struct Ports: Decodable { var role: String; var portCount: Int; var speedMbps: Double }
            guard let rows = try? JSONDecoder().decode([Ports].self, from: Data(attribute.value.utf8)) else { return LinkaCopy.value("inventory.unknown") }
            return rows.map { row in "\(row.portCount) × \(row.role == "lanWan" ? "LAN/WAN" : row.role.uppercased()) · \(number(row.speedMbps)) Mbps" }.joined(separator: "\n")
        default: return attribute.value + (attribute.unit.map { " " + $0 } ?? "")
        }
    }
    /// Only everyday capabilities belong in the summary; technical tables remain expandable.
    static func summary(_ snapshot: DeviceSpecificationSnapshot) -> [String] {
        var lines: [String] = []
        if let bands = snapshot.attributes.first(where: { $0.key == "bandsGHz" }) {
            let values = bands.value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                .map { number($0) }.joined(separator: " / ")
            lines.append("Wi-Fi · " + values + " GHz")
        }
        if let ports = snapshot.attributes.first(where: { $0.key == "lanPorts" }) {
            lines.append(LinkaCopy.value("inventory.summary.cablePorts") + ": " + ports.value)
        }
        return lines
    }
    private static func number(_ value: Double) -> String { value.formatted(.number.locale(LinkaLanguagePreference.currentLocale)) }
}
