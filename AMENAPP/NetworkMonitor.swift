//
//  NetworkMonitor.swift
//  AMENAPP
//
//  Network connectivity monitoring
//

import Network
import SwiftUI
import Combine

class AMENNetworkMonitor: ObservableObject {
    static let shared = AMENNetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected = true
    @Published var connectionType: NWInterface.InterfaceType?
    @Published var isExpensive = false
    @Published var isConstrained = false
    
    var connectionDescription: String {
        if !isConnected {
            return "No Connection"
        }
        
        guard let type = connectionType else {
            return "Connected"
        }
        
        switch type {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return isExpensive ? "Cellular (Limited)" : "Cellular"
        case .wiredEthernet:
            return "Ethernet"
        default:
            return "Connected"
        }
    }
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}

// MARK: - SwiftUI View Modifier

struct NetworkStatusBanner: ViewModifier {
    @ObservedObject var monitor: AMENNetworkMonitor
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            if !monitor.isConnected {
                offlineBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14, weight: .semibold))
            
            Text("No internet connection")
                .font(.custom("OpenSans-SemiBold", size: 13))
            
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red)
        .animation(.spring(response: 0.3), value: monitor.isConnected)
    }
}

extension View {
    func networkStatusBanner() -> some View {
        modifier(NetworkStatusBanner(monitor: AMENNetworkMonitor.shared))
    }
}

// MARK: - Connection Quality

enum ConnectionQuality {
    case excellent
    case good
    case fair
    case poor
    case offline
    
    var icon: String {
        switch self {
        case .excellent: return "wifi"
        case .good: return "wifi"
        case .fair: return "wifi.exclamationmark"
        case .poor: return "wifi.slash"
        case .offline: return "wifi.slash"
        }
    }
    
    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .green
        case .fair: return .orange
        case .poor: return .red
        case .offline: return .red
        }
    }
    
    var description: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .offline: return "Offline"
        }
    }
}

extension AMENNetworkMonitor {
    var quality: ConnectionQuality {
        if !isConnected {
            return .offline
        }
        
        if isConstrained {
            return .fair
        }
        
        switch connectionType {
        case .wifi:
            return .excellent
        case .cellular:
            return isExpensive ? .fair : .good
        case .wiredEthernet:
            return .excellent
        default:
            return .good
        }
    }
}
