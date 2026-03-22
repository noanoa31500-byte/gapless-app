import CoreBluetooth
import Flutter

// ============================================================================
// BlePeripheralManager — CoreBluetooth ペリフェラルモード
// ============================================================================
// flutter_blue_plus はiOSでペリフェラルAPIを提供しないため、
// ネイティブ実装でアドバタイズ + Characteristic 更新を行う。
//
// Service UUID  : 6E400001-B5A3-F393-E0A9-E50E24DCCA9E (Nordic UART)
// TX Char UUID  : 6E400003-B5A3-F393-E0A9-E50E24DCCA9E (Read + Notify)
//
// Flutter → Native:
//   startAdvertising()         : アドバタイズ開始
//   stopAdvertising()          : アドバタイズ停止
//   updateData(FlutterStandardTypedData) : Characteristic値を更新して通知
// ============================================================================

class BlePeripheralManager: NSObject {

    // MARK: - Constants
    static let methodChannelName = "gapless/ble_peripheral"
    static let serviceUUID  = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let txCharUUID   = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    // MARK: - Internals
    private var peripheralManager: CBPeripheralManager!
    private var txCharacteristic: CBMutableCharacteristic?
    private var pendingData: Data?
    private var wantsAdvertising = false

    // MARK: - Init
    static func register(with messenger: FlutterBinaryMessenger) {
        let instance = BlePeripheralManager()
        let channel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler(instance.handle)
        // Peripheral manager は DispatchQueue.main で作成
        instance.peripheralManager = CBPeripheralManager(
            delegate: instance,
            queue: DispatchQueue.main,
            options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
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
            txCharacteristic = nil
            result(nil)

        case "updateData":
            guard let typed = call.arguments as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARG", message: "bytes required", details: nil))
                return
            }
            pendingData = typed.data
            if let char = txCharacteristic, peripheralManager.state == .poweredOn {
                peripheralManager.updateValue(typed.data, for: char, onSubscribedCentrals: nil)
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Setup
    private func setupAndAdvertise() {
        // 既存サービスをクリアして再登録
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        txCharacteristic = nil

        let char = CBMutableCharacteristic(
            type: BlePeripheralManager.txCharUUID,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        txCharacteristic = char

        let service = CBMutableService(type: BlePeripheralManager.serviceUUID, primary: true)
        service.characteristics = [char]
        peripheralManager.add(service)
        // 広告はdidAdd:error:コールバック後に開始
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BlePeripheralManager: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn && wantsAdvertising {
            setupAndAdvertise()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            print("BlePeripheral: サービス追加失敗 \(error!.localizedDescription)")
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BlePeripheralManager.serviceUUID],
            CBAdvertisementDataLocalNameKey: "GapLess"
        ])
        print("BlePeripheral: アドバタイズ開始")
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let e = error {
            print("BlePeripheral: アドバタイズ開始失敗 \(e.localizedDescription)")
        } else {
            print("BlePeripheral: アドバタイズ中")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == BlePeripheralManager.txCharUUID else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        if let data = pendingData {
            request.value = data
            peripheral.respond(to: request, withResult: .success)
        } else {
            peripheral.respond(to: request, withResult: .unlikelyError)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        // セントラルがNotifyを購読 → 最新データを即送信
        if let char = txCharacteristic, let data = pendingData {
            peripheral.updateValue(data, for: char, onSubscribedCentrals: nil)
        }
    }
}
