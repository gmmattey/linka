import Foundation

/// Utilitário determinístico para sanitização e validação de endereços BSSID (MAC 802.11)
public enum WiFiBSSIDNormalizer {
    /// Normaliza qualquer formato comum de BSSID para o formato canônico IEEE 802: `AA:BB:CC:DD:EE:FF`
    /// Retorna `nil` se o endereço for inválido, corrompido, nulo ou consistir apenas em zeros.
    public static func normalize(_ rawBSSID: String?) -> String? {
        guard let rawBSSID else { return nil }

        let trimmed = rawBSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Remove delimitadores comuns (: - espaço)
        let hexOnly = trimmed
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        // Deve conter exatamente 12 dígitos hexadecimais
        guard hexOnly.count == 12 else { return nil }

        let hexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard CharacterSet(charactersIn: hexOnly).isSubset(of: hexCharacterSet) else { return nil }

        // Descarta endereços nulos de broadcast/dummy como 000000000000
        if hexOnly == "000000000000" {
            return nil
        }

        // Formata em pares de octetos separados por dois-pontos
        var formatted = ""
        var index = hexOnly.startIndex
        for i in 0..<6 {
            let nextIndex = hexOnly.index(index, offsetBy: 2)
            let octet = hexOnly[index..<nextIndex]
            formatted += octet
            if i < 5 {
                formatted += ":"
            }
            index = nextIndex
        }

        return formatted
    }
}

