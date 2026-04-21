import CoreBluetooth
import Flutter

// ============================================================================
// BlePeripheralManager — CoreBluetooth ペリフェラルモード
// ============================================================================
// Service UUID  : 4b474150-4c45-5353-0001-000000000001 (GapLess共通)
// RX Char UUID  : ...0005  Notify — CentralへのデータPush
// TX Char UUID  : ...0004  Write  — Centralからのデータ受信
//
// Flutter → Native:
//   startAdvertising()         : アドバタイズ開始
//   stopAdvertising()          : アドバタイズ停止
//   updateData(bytes)          : RX Char値を更新して購読Central全員に通知
//
// Native → Flutter (onDataReceived):
//   受信データ(bytes)をFlutterに渡す
// ============================================================================

class BlePeripheralManager: NSObject {

    // MARK: - UUIDs (BleRoadReportService.dart と一致させる)
    static let serviceUUID = CBUUID(string: "4b474150-4c45-5353-0001-000000000001")
    static let rxCharUUID  = CBUUID(string: "4b474150-4c45-5353-0001-000000000005") // Notify to Central
    static let txCharUUID  = CBUUID(string: "4b474150-4c45-5353-0001-000000000004") // Write from Central

    static let methodChannelName = "gapless/ble_peripheral"

    // MARK: - Internals
    private var peripheralManager: CBPeripheralManager!
    private var rxCharacteristic: CBMutableCharacteristic?
    private var txCharacteristic: CBMutableCharacteristic?
    private var pendingData: Data?
    private var wantsAdvertising = false
    private var methodChannel: FlutterMethodChannel?
    private var lastAddServiceError: String = ""
    private var didAddServiceCount = 0
    private var didStartAdvertisingCount = 0
    private var lastAdvertisingError: String = ""

    // インスタンスを静的プロパティで保持（ARC解放防止）
    private static var shared: BlePeripheralManager?

    // MARK: - Init
    static func register(with messenger: FlutterBinaryMessenger) {
        let instance = BlePeripheralManager()
        shared = instance  // ARC解放を防ぐ
        let channel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: messenger
        )
        instance.methodChannel = channel
        channel.setMethodCallHandler(instance.handle)
        instance.peripheralManager = CBPeripheralManager(
            delegate: instance,
            queue: DispatchQueue.main,
            options: [
                CBPeripheralManagerOptionShowPowerAlertKey: true,
            ]
        )
    }

    // MARK: - Method Channel Handler
    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAdvertising":
            wantsAdvertising = true
            if peripheralManager.state == .poweredOn {
                setupAndAdvertise()
            }
            result(nil)

        case "stopAdvertising":
            wantsAdvertising = false
            peripheralManager.stopAdvertising()
            peripheralManager.removeAllServices()
            rxCharacteristic = nil
            txCharacteristic = nil
            result(nil)

        case "updateData":
            guard let typed = call.arguments as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARG", message: "bytes required", details: nil))
                return
            }
            pendingData = typed.data
            if let char = rxCharacteristic, peripheralManager.state == .poweredOn {
                peripheralManager.updateValue(typed.data, for: char, onSubscribedCentrals: nil)
            }
            result(nil)

        case "getStatus":
            let stateNum = peripheralManager?.state.rawValue ?? -1
            let isAdv = peripheralManager?.isAdvertising ?? false
            result([
                "state": stateNum,
                "isAdvertising": isAdv,
                "wantsAdvertising": wantsAdvertising,
                "didAddServiceCount": didAddServiceCount,
                "didStartAdvertisingCount": didStartAdvertisingCount,
                "lastAddServiceError": lastAddServiceError,
                "lastAdvertisingError": lastAdvertisingError,
            ])

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Setup
    private func setupAndAdvertise() {
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        rxCharacteristic = nil
        txCharacteristic = nil

        // RX: Centralへ通知する Characteristic (Notify + Read)
        let rxChar = CBMutableCharacteristic(
            type: BlePeripheralManager.rxCharUUID,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        rxCharacteristic = rxChar

        // TX: Centralから書き込まれる Characteristic (Write)
        let txChar = CBMutableCharacteristic(
            type: BlePeripheralManager.txCharUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        txCharacteristic = txChar

        let service = CBMutableService(type: BlePeripheralManager.serviceUUID, primary: true)
        service.characteristics = [rxChar, txChar]
        peripheralManager.add(service)
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BlePeripheralManager: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn && wantsAdvertising {
            setupAndAdvertise()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
            for service in services where service.uuid == BlePeripheralManager.serviceUUID {
                if let chars = service.characteristics as? [CBMutableCharacteristic] {
                    rxCharacteristic = chars.first { $0.uuid == BlePeripheralManager.rxCharUUID }
                    txCharacteristic = chars.first { $0.uuid == BlePeripheralManager.txCharUUID }
                }
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        didAddServiceCount += 1
        if let e = error {
            lastAddServiceError = e.localizedDescription
            print("BlePeripheral: add(service)失敗 \(e.localizedDescription)")
            return
        }
        lastAddServiceError = ""
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BlePeripheralManager.serviceUUID],
            CBAdvertisementDataLocalNameKey: "GapLess"
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        didStartAdvertisingCount += 1
        if let e = error {
            lastAdvertisingError = e.localizedDescription
            print("BlePeripheral: アドバタイズ開始失敗 \(e.localizedDescription)")
        } else {
            lastAdvertisingError = ""
            print("BlePeripheral: アドバタイズ中 (GapLess UUID)")
        }
    }

    // Central が RX Char を Read 要求
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == BlePeripheralManager.rxCharUUID else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        request.value = pendingData ?? Data()
        peripheral.respond(to: request, withResult: .success)
    }

    // Central が TX Char に Write → Flutter へ転送
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == BlePeripheralManager.txCharUUID,
                  let data = request.value else { continue }
            peripheral.respond(to: request, withResult: .success)
            // Dart 側に渡す
            let bytes = FlutterStandardTypedData(bytes: data)
            methodChannel?.invokeMethod("onDataReceived", arguments: bytes)
        }
    }

    // Central が RX Char を Notify 購読 → 最新データを即送信
    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        if let char = rxCharacteristic, let data = pendingData {
            peripheral.updateValue(data, for: char, onSubscribedCentrals: [central])
        }
    }
}
