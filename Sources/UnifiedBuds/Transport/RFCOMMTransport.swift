import Foundation
import IOBluetooth

/// Opens an RFCOMM channel to a paired Classic Bluetooth device, locating the
/// channel through SDP by service UUID. All callbacks arrive on the main run loop.
final class RFCOMMTransport: NSObject, IOBluetoothRFCOMMChannelDelegate {
    enum TransportError: LocalizedError {
        case serviceNotFound
        case openFailed(IOReturn)
        case busy
        case notOpen

        var errorDescription: String? {
            switch self {
            case .serviceNotFound:
                return "Control service not found. Close the brand's phone app and reconnect."
            case .openFailed(let code):
                return "Could not open control channel (0x\(String(UInt32(bitPattern: code), radix: 16)))."
            case .busy:
                return "The earbuds' control channel is busy. Close the brand's phone app (it holds the only control connection), then press reload."
            case .notOpen:
                return "Control channel is not open."
            }
        }
    }

    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: ((Error?) -> Void)?

    private let device: IOBluetoothDevice
    private let serviceUUIDs: [UUID]
    private let fallbackChannel: BluetoothRFCOMMChannelID?
    private var channel: IOBluetoothRFCOMMChannel?
    private var didRetrySDP = false
    /// Right after the Bluetooth link comes up the buds can refuse a channel for
    /// a moment, so failed opens are retried quickly instead of waiting up front.
    private var openAttempts = 0
    private static let maxOpenAttempts = 12
    private static let retryDelay: TimeInterval = 0.25
    /// An open that hasn't completed by then is abandoned and retried; reopening
    /// right after a close can otherwise hang with no callback at all.
    private static let openTimeout: TimeInterval = 0.7
    private var openTimer: DispatchWorkItem?

    init(device: IOBluetoothDevice, serviceUUIDs: [UUID], fallbackChannel: BluetoothRFCOMMChannelID? = nil) {
        self.device = device
        self.serviceUUIDs = serviceUUIDs
        self.fallbackChannel = fallbackChannel
    }

    func open() {
        guard let channelID = findChannelID() ?? (didRetrySDP ? fallbackChannel : nil) else {
            if didRetrySDP {
                onClose?(TransportError.serviceNotFound)
            } else {
                // Cached SDP records can be stale or missing; refresh once.
                didRetrySDP = true
                device.performSDPQuery(self)
            }
            return
        }
        openAttempts += 1
        connectionLog.info("rfcomm open request, channel \(channelID), attempt \(self.openAttempts)")
        var newChannel: IOBluetoothRFCOMMChannel?
        let status = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
        guard status == kIOReturnSuccess else {
            retryOrFail(TransportError.openFailed(status))
            return
        }
        channel = newChannel
        let timer = DispatchWorkItem { [weak self] in
            guard let self, let pending = self.channel, !pending.isOpen() else { return }
            connectionLog.info("rfcomm open timed out, attempt \(self.openAttempts)")
            pending.setDelegate(nil)
            pending.close()
            self.retryOrFail(TransportError.busy)
        }
        openTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.openTimeout, execute: timer)
    }

    private func retryOrFail(_ error: Error) {
        channel = nil
        guard openAttempts < Self.maxOpenAttempts, device.isConnected() else {
            openAttempts = 0
            onClose?(error)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
            guard let self, self.channel == nil, self.openAttempts > 0 else { return }
            self.open()
        }
    }

    func close() {
        openTimer?.cancel()
        openAttempts = 0
        didRetrySDP = false
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
    }

    func send(_ data: Data) throws {
        guard let channel, channel.isOpen() else { throw TransportError.notOpen }
        let mtu = max(Int(channel.getMTU()), 1)
        var bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let length = min(mtu, bytes.count - offset)
            let status = bytes.withUnsafeMutableBytes { buffer in
                channel.writeSync(buffer.baseAddress! + offset, length: UInt16(length))
            }
            guard status == kIOReturnSuccess else { throw TransportError.openFailed(status) }
            offset += length
        }
    }

    private func findChannelID() -> BluetoothRFCOMMChannelID? {
        for uuid in serviceUUIDs {
            var raw = uuid.uuid
            let sdpUUID = withUnsafeBytes(of: &raw) { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
            guard let record = device.getServiceRecord(for: sdpUUID) else { continue }
            var channelID: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
                return channelID
            }
        }
        return nil
    }

    // MARK: SDP

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        open()
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        openTimer?.cancel()
        if error == kIOReturnSuccess {
            connectionLog.info("rfcomm open after \(self.openAttempts) attempt(s)")
            openAttempts = 0
            onOpen?()
        } else {
            retryOrFail(TransportError.openFailed(error))
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        onData?(Data(bytes: dataPointer, count: dataLength))
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        channel = nil
        onClose?(nil)
    }
}
