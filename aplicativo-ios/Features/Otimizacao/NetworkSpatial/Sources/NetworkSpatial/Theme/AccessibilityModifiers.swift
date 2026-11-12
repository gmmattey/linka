import SwiftUI

extension View {
    /// Aplica navigationBarTitleDisplayMode inline apenas onde suportado (iOS)
    @ViewBuilder
    public func inlineTitleDisplayMode() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Aplica estilo insetGrouped no iOS e sidebar/inset no macOS
    @ViewBuilder
    public func appListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }
}
