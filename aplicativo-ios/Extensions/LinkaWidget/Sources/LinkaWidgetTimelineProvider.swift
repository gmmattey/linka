import WidgetKit
import LinkaWidgetShared

/// Uma entrada = o último resumo espelhado no App Group, no instante em
/// que a timeline foi construída. `summary == nil` é estado normal
/// ("sem medição anterior" — requisito de aceite da issue #55), não erro.
struct LinkaWidgetEntry: TimelineEntry {
    let date: Date
    let summary: LinkaWidgetShared.LatestMeasurementSummary?
}

/// A extensão de widget só lê — nunca mede e nunca escreve o resumo
/// (isso é responsabilidade de `SpeedTestViewModel`, no app host, depois
/// de `MeasurementHistoryRepository.save()`). Sem polling: a timeline tem
/// uma única entrada e `policy: .never`, porque o resumo só muda quando o
/// usuário efetivamente mede — o app host chama
/// `WidgetCenter.shared.reloadTimelines(ofKind:)` explicitamente depois de
/// cada teste concluído em vez desta extensão ficar consultando por
/// tempo.
struct LinkaWidgetTimelineProvider: TimelineProvider {
    private let summaryReader: () -> LinkaWidgetShared.LatestMeasurementSummary?

    init(summaryReader: @escaping () -> LinkaWidgetShared.LatestMeasurementSummary? = { LinkaWidgetShared.readLatestSummary() }) {
        self.summaryReader = summaryReader
    }

    func placeholder(in context: Context) -> LinkaWidgetEntry {
        LinkaWidgetEntry(date: Date(), summary: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (LinkaWidgetEntry) -> Void) {
        completion(snapshotEntry(isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LinkaWidgetEntry>) -> Void) {
        completion(timeline())
    }

    /// Mantido separado para cobrir o contrato de timeline sem precisar
    /// fabricar um `TimelineProviderContext`, que WidgetKit não expõe em
    /// testes unitários.
    func snapshotEntry(isPreview: Bool) -> LinkaWidgetEntry {
        LinkaWidgetEntry(date: Date(), summary: isPreview ? nil : summaryReader())
    }

    func timeline() -> Timeline<LinkaWidgetEntry> {
        Timeline(entries: [LinkaWidgetEntry(date: Date(), summary: summaryReader())], policy: .never)
    }
}
