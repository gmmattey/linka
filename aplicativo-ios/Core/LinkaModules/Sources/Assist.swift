import NetworkAssist

/// Compatibilidade temporária com a fundação inicial da branch.
/// Código novo deve importar `NetworkAssist` diretamente.
public typealias AssistContext = NetworkAssist.NetworkAssistContext
public typealias AssistResponse = NetworkAssist.NetworkAssistResponse
public typealias AssistProviding = NetworkAssist.NetworkAssistProviding
public typealias AssistTransport = NetworkAssist.NetworkAssistTransport
public typealias AssistError = NetworkAssist.NetworkAssistError
public typealias UnconfiguredAssistTransport = NetworkAssist.UnconfiguredNetworkAssistTransport
public typealias TransportBackedAssistProvider<Transport: NetworkAssistTransport> = NetworkAssist.NetworkAssistService<Transport>

// Issue #69 — resposta progressiva do Assist.
public typealias AssistStreamingTransport = NetworkAssist.NetworkAssistStreamingTransport
public typealias AssistStreamEvent = NetworkAssist.NetworkAssistStreamEvent
public typealias AssistProgressStep = NetworkAssist.NetworkAssistProgressStep
