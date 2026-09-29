# flutter_blue_plus_ohos

## 简介

flutter_blue_plus_ohos 是 Flutter 的蓝牙插件，支持蓝牙设备的扫描、连接、数据读写及状态监测。它简化了蓝牙通信的开发流程，适用于智能家居、健康监测等应用场景。

## 构建

```
拉取代码后进入到
cd ./example 执行 flutter build hap 可在example下编译出对应的har包
```

## 使用说明

1. 获取蓝牙关闭状态

```
// Note: The platform is initialized on the first call to any FlutterBluePlus method.
if (await FlutterBluePlus.isSupported == false) {
    print("Bluetooth not supported by this device");
    return;
}

// handle bluetooth on & off
// note: for iOS the initial state is typically BluetoothAdapterState.unknown
// note: if you have permissions issues you will get stuck at BluetoothAdapterState.unauthorized
var subscription = FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
    print(state);
    if (state == BluetoothAdapterState.on) {
        // usually start scanning, connecting, etc
    } else {
        // show an error to the user, etc
    }
});

// turn on bluetooth ourself if we can
// for iOS, the user controls bluetooth enable/disable
if (Platform.isAndroid||Platform.operatingSystem == 'ohos') {
    await FlutterBluePlus.turnOn();
}

// cancel to prevent duplicate listeners
subscription.cancel();
```

2. 扫描设备

```
// listen to scan results
// Note: `onScanResults` only returns live scan results, i.e. during scanning. Use
//  `scanResults` if you want live scan results *or* the results from a previous scan.
var subscription = FlutterBluePlus.onScanResults.listen((results) {
        if (results.isNotEmpty) {
            ScanResult r = results.last; // the most recently found device
            print('${r.device.remoteId}: "${r.advertisementData.advName}" found!');
        }
    },
    onError: (e) => print(e),
);

// cleanup: cancel subscription when scanning stops
FlutterBluePlus.cancelWhenScanComplete(subscription);

// Wait for Bluetooth enabled & permission granted
// In your real app you should use `FlutterBluePlus.adapterState.listen` to handle all states
await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;

// Start scanning w/ timeout
// Optional: use `stopScan()` as an alternative to timeout
await FlutterBluePlus.startScan(
  withServices:[Guid("180D")], // match any of the specified services
  withNames:["Bluno"], // *or* any of the specified names
  timeout: Duration(seconds:15));

// wait for scanning to stop
await FlutterBluePlus.isScanning.where((val) => val == false).first;
```

3. 连接到设备

```
// listen for disconnection
var subscription = device.connectionState.listen((BluetoothConnectionState state) async {
    if (state == BluetoothConnectionState.disconnected) {
        // 1. typically, start a periodic timer that tries to
        //    reconnect, or just call connect() again right now
        // 2. you must always re-discover services after disconnection!
        print("${device.disconnectReason?.code} ${device.disconnectReason?.description}");
    }
});

// cleanup: cancel subscription when disconnected
//   - [delayed] This option is only meant for `connectionState` subscriptions.
//     When `true`, we cancel after a small delay. This ensures the `connectionState`
//     listener receives the `disconnected` event.
//   - [next] if true, the the stream will be canceled only on the *next* disconnection,
//     not the current disconnection. This is useful if you setup your subscriptions
//     before you connect.
device.cancelWhenDisconnected(subscription, delayed:true, next:true);

// Connect to the device
await device.connect();

// Disconnect from device
await device.disconnect();

// cancel to prevent duplicate listeners
subscription.cancel();
```

4. MTU

```
   final subscription = device.mtu.listen((int mtu) {
    // iOS: initial value is always 23, but iOS will quickly negotiate a higher value
    print("mtu $mtu");
});

// cleanup: cancel subscription when disconnected
device.cancelWhenDisconnected(subscription);

// You can also manually change the mtu yourself.
if (Platform.isAndroid||Platform.operatingSystem == 'ohos') {
    await device.requestMtu(512);
}
```

5. 发现服务

```
   // Note: You must call discoverServices after every re-connection!
   // Note(OHOS): 服务发现由系统异步推送，discoverServices 内部会等待
   //   OnDiscoveredServices 事件后返回；若服务变更会收到 OnServicesReset，
   //   需重新调用 discoverServices。
List<BluetoothService> services = await device.discoverServices();
services.forEach((service) {
    // do something with service
});
```

6. 写入特性

```
// Writes to a characteristic
// Note(OHOS): 无响应写 (withoutResponse:true) 单次最大可写字节数为 MTU-3；
//   allowLongWrite 在 OHOS 上同样受 512 字节属性上限约束。
await c.write([0x12, 0x34]);
allowLongWrite：要写入大型特征（最多 512 字节），而不考虑 mtu，请使用：allowLongWrite
await c.write(data, allowLongWrite:true);
```

7. 订阅特征

```
        final subscription = characteristic.onValueReceived.listen((value) {
    // onValueReceived is updated:
    //   - anytime read() is called
    //   - anytime a notification arrives (if subscribed)
});

// cleanup: cancel subscription when disconnected
device.cancelWhenDisconnected(subscription);

// subscribe
// Note: If a characteristic supports both **notifications** and **indications**,
// it will default to **notifications**. This matches how CoreBluetooth works on iOS.
// Note(OHOS): setNotifyValue 通过向 CCCD(0x2902) 描述符写入使能值实现，
//   完成以 OnDescriptorWritten 事件为准。
await characteristic.setNotifyValue(true);
```

8. 读取和写入描述符

```
            // Reads all descriptors
            // Note(OHOS): 描述符读写同样以 OnDescriptorRead/OnDescriptorWritten 事件完成。
var descriptors = characteristic.descriptors;
for(BluetoothDescriptor d in descriptors) {
    List<int> value = await d.read();
    print(value);
}

// Writes to a descriptor
await d.write([0x12, 0x34])

```

9. 获取互联设备

```
List<BluetoothDevice> devs = FlutterBluePlus.connectedDevices;
for (var d in devs) {
    print(d);
}

```


## 约束与限制

- DevEco Studio Next版本：5.0.3.404

- sdk：API12
