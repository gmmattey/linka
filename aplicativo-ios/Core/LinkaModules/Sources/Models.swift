import Foundation
import NetworkCore
import LinkaEntitlements

/// Compatibilidade temporária com a fundação inicial da branch.
/// Código novo deve depender do contrato canônico `NetworkMeasurement`.
@available(*, deprecated, renamed: "NetworkMeasurement")
public typealias MeasurementSnapshot = NetworkMeasurement

/// Compatibilidade temporária. Código novo deve importar `LinkaEntitlements`.
public typealias LinkaTier = LinkaPlan

/// Compatibilidade temporária. Código novo deve importar `LinkaEntitlements`.
public typealias LinkaCapability = LinkaEntitlements.LinkaCapability
