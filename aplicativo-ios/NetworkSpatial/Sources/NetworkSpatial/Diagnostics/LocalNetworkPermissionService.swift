import Foundation
import os
#if os(iOS)
import UIKit
#endif
import Combine

public enum LocalNetworkPermissionStatus: String, Sendable, Equatable {
    case granted = "Concedida"
    case denied = "Negada"
    case notDetermined = "Não Determinada"
}

/// Serviço responsável pelo gerenciamento resiliente da permissão de Rede Local (Local Network Privacy do iOS 14+).
/// Evita que a medição seja executada incorretamente em background enquanto o diálogo de autorização do sistema estiver sendo exibido.
public final class LocalNetworkPermissionService: @unchecked Sendable {
    public static let shared = LocalNetworkPermissionService()

    private let userDefaults: UserDefaults
    private let permissionKey = "WiFiCheck.localNetworkPermissionGranted"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Indica se a permissão já foi confirmada anteriormente nesta instalação
    public var hasPreviouslyGrantedPermission: Bool {
        get { userDefaults.bool(forKey: permissionKey) }
        set { userDefaults.set(newValue, forKey: permissionKey) }
    }

    /// Verifica se a aplicação está em primeiro plano e ativa
    public var isAppActive: Bool {
        #if os(iOS)
        if Thread.isMainThread {
            return UIApplication.shared.applicationState == .active
        } else {
            return DispatchQueue.main.sync {
                UIApplication.shared.applicationState == .active
            }
        }
        #else
        return true
        #endif
    }

    /// Versão assíncrona não-bloqueante para invocação segura dentro de actors do Swift Concurrency
    public var isAppActiveAsync: Bool {
        get async {
            #if os(iOS)
            return await MainActor.run {
                UIApplication.shared.applicationState == .active
            }
            #else
            return true
            #endif
        }
    }

    /// Aguarda a aplicação retornar para o primeiro plano ativo caso tenha sido suspensa por modal do sistema
    public func waitForAppToBeActive(timeoutSeconds: Double = 30.0) async -> Bool {
        #if os(iOS)
        let isActiveNow = await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
        if isActiveNow { return true }

        return await withCheckedContinuation { continuation in
            var observer: NSObjectProtocol?
            let hasResumed = OSAllocatedUnfairLock(initialState: false)

            let finish = { (result: Bool) in
                let alreadyResumed = hasResumed.withLock { isResumed -> Bool in
                    if isResumed { return true }
                    isResumed = true
                    return false
                }
                if !alreadyResumed {
                    if let obs = observer {
                        NotificationCenter.default.removeObserver(obs)
                    }
                    continuation.resume(returning: result)
                }
            }

            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                finish(true)
            }

            // Timeout de segurança
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                finish(false)
            }
        }
        #else
        return true
        #endif
    }

    /// Executa o pre-flight de permissão de rede local com segurança.
    /// Se o prompt do sistema for exibido, aguarda a interação do usuário sem computar perda ou latência incorretas.
    public func prepareLocalNetworkAccess(
        gatewayIP: String,
        onWaitingForUserPermission: (@Sendable () -> Void)? = nil
    ) async -> LocalNetworkPermissionStatus {
        #if targetEnvironment(simulator)
        hasPreviouslyGrantedPermission = true
        return .granted
        #else

        #if os(iOS)
        // Se a permissão já foi concedida e validada anteriormente, prossegue sem interrupção
        if hasPreviouslyGrantedPermission {
            return .granted
        }

        // Se o app não estiver ativo neste momento, aguarda retorno
        let isCurrentlyActive = await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
        if !isCurrentlyActive {
            onWaitingForUserPermission?()
            let didBecomeActive = await waitForAppToBeActive(timeoutSeconds: 45.0)
            if !didBecomeActive {
                return .denied
            }
        }

        // Monitora se o diálogo de permissão do iOS vai desativar o app ao tentar conectar
        let resignationDetector = AppResignationDetector()
        resignationDetector.startListening()

        // Dispara uma tentativa leve de handshake na porta do gateway para provocar o prompt de rede local se necessário
        let probeResult = await triggerLocalNetworkPreflightSocket(gatewayIP: gatewayIP)

        // Se o app perdeu foco durante a tentativa de conexão, significa que o iOS exibiu o alerta de permissão!
        if resignationDetector.didResignActive {
            onWaitingForUserPermission?()
            resignationDetector.stopListening()

            // Aguarda o usuário responder ao diálogo do sistema e o app voltar ao primeiro plano
            let didReturnToActive = await waitForAppToBeActive(timeoutSeconds: 60.0)
            if !didReturnToActive {
                return .denied
            }

            // Janela de estabilização pós-resposta do prompt (400ms)
            try? await Task.sleep(nanoseconds: 400_000_000)

            // Valida se o acesso à rede local agora foi concedido
            let validationResult = await triggerLocalNetworkPreflightSocket(gatewayIP: gatewayIP)
            if validationResult.isAllowed {
                hasPreviouslyGrantedPermission = true
                return .granted
            } else {
                return .denied
            }
        }

        resignationDetector.stopListening()

        if probeResult.isAllowed {
            hasPreviouslyGrantedPermission = true
            return .granted
        } else if probeResult.isPermissionDenied {
            return .denied
        }

        // Se não foi erro de permissão (ex: apenas gateway temporariamente não respondeu nesta porta específica), considera não impeditivo de rede
        return .granted
        #else
        return .granted
        #endif

        #endif
    }

    /// Dispara uma sondagem não-bloqueante no gateway para forçar o prompt de rede local do sistema
    private func triggerLocalNetworkPreflightSocket(gatewayIP: String) async -> (isAllowed: Bool, isPermissionDenied: Bool) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var serverAddr = sockaddr_in()
                serverAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                serverAddr.sin_family = sa_family_t(AF_INET)
                serverAddr.sin_port = UInt16(53).bigEndian

                guard inet_pton(AF_INET, gatewayIP, &serverAddr.sin_addr) == 1 else {
                    continuation.resume(returning: (false, false))
                    return
                }

                let sock = socket(AF_INET, SOCK_STREAM, 0)
                guard sock >= 0 else {
                    let err = errno
                    let isDenied = (err == EPERM || err == EACCES)
                    continuation.resume(returning: (false, isDenied))
                    return
                }
                defer { close(sock) }

                let flags = fcntl(sock, F_GETFL, 0)
                _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

                let res = withUnsafePointer(to: &serverAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                        connect(sock, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                if res == 0 {
                    continuation.resume(returning: (true, false))
                    return
                }

                let connectErr = errno
                if connectErr == EPERM || connectErr == EACCES {
                    continuation.resume(returning: (false, true))
                    return
                }

                if connectErr == EINPROGRESS {
                    var pfd = pollfd(fd: sock, events: Int16(POLLOUT | POLLERR | POLLHUP), revents: 0)
                    let pollRes = poll(&pfd, 1, 350)
                    if pollRes > 0 {
                        var err: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &len)
                        if err == 0 || err == ECONNREFUSED {
                            continuation.resume(returning: (true, false))
                            return
                        }
                        if err == EPERM || err == EACCES {
                            continuation.resume(returning: (false, true))
                            return
                        }
                    }
                }

                continuation.resume(returning: (false, false))
            }
        }
    }
}

#if os(iOS)
/// Detector auxiliar de perda de foco do app disparado por diálogos de sistema
private final class AppResignationDetector: @unchecked Sendable {
    private var observer: NSObjectProtocol?
    private let _didResign = OSAllocatedUnfairLock(initialState: false)

    var didResignActive: Bool {
        _didResign.withLock { $0 }
    }

    func startListening() {
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?._didResign.withLock { $0 = true }
        }
    }

    func stopListening() {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
    }
}
#endif
