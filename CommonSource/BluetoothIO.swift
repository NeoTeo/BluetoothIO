//
//  BluetoothIO.swift
//  ProtoMetronomCentral
//
//  Created by Teo Sartori on 20/09/2017.
//  Copyright © 2017 Matteo Sartori. All rights reserved.
//

import Foundation
import CoreBluetooth

/** Pass in:
 Peripheral name
 uuids for service and characteristics of interest
 handler for received data
 
 Peripheral
 service
 characteristic
 characteristic
 service
 characteristic
 
 the handler could, async'ly, add new data to a a queue that the main app
 can dequeue and deal with. Or just deal with it there...but that gives less
 control (eg. to discard all but last item in queue)
 
 Each service can have multiple characteristics so we need to associate them.
 We should bundle a characteristic and its handler when we pass it to this so
 that we can call the correct handler.
 
 The handler has to know which service a particular characteristic comes from.
 Because each service has its own characteristics it should be associated with
 Service->characteristic1->handler1
 characteristic2->handler2
 */

// TODO: Need to enable discovery by uuid, not just name.
// TODO: Need to distinguish between a characteristic that has a fixed value and request it
// and one that is dynamic and handle updates.

open class BluetoothIO : NSObject {
    
    var centralManager: CBCentralManager!
    var activePeripheral: CBPeripheral?
    
    var wantedPeripheralName: String?
    
    var peripheralsWithWantedServices: [CBPeripheral]!
    var wantedServices: [CBUUID]!
    
    var characteristicsForService: [CBUUID : [CBUUID]]!
    var handlerForCharacteristic: [CBUUID : (CBCharacteristic) throws -> Void]!
    
    open static let sharedInstance : BluetoothIO = {
        
        let instance = BluetoothIO()
        return instance
    }()
    
    public func start(_ peripheralName: String, services: [CBUUID], characteristics: [CBUUID : [CBUUID]], handlers: [CBUUID : (CBCharacteristic) throws -> Void] ) {
        
        wantedPeripheralName = peripheralName
        wantedServices = services
        
        peripheralsWithWantedServices = []
        
        characteristicsForService = characteristics
        handlerForCharacteristic = handlers
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    public func stop() {
        
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        
        guard let ap = activePeripheral else { return }
        
        /// For each service go through each characteristic and disable notification if active.
        _ = ap.services?.map { service in
            service.characteristics?.map { char in
                guard char.isNotifying == true else { return }
                ap.setNotifyValue(false, for: char)
            }
        }
        print("Cancelling peripheral connection to \(ap)")
        centralManager.cancelPeripheralConnection(ap)
        
    }
    
    public func pause() {
        
    }
    
    public func resume() {
        
    }
    
    override fileprivate init() {
        
    }
}

extension BluetoothIO : CBCentralManagerDelegate {
    
    /** Scan for Bluetooth Low Energy devices. */
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        guard central.state == .poweredOn else {
            
            print("Bluetooth is off or not initialized.")
            return
        }
        central.scanForPeripherals(withServices: wantedServices, options: nil)
        
        print("Searching for BLE devices with services \(String(describing: wantedServices))...")
        
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("centralManager: didDiscover called.")
        
        // TODO: look for CBAdvertisementDataServiceUUIDsKey match as well.
        /// See if the device name matches what we're looking for.
        
        activePeripheral = nil
        
        if let wantedPeripheralName = wantedPeripheralName,
            let foundPeripheralName = advertisementData[CBAdvertisementDataLocalNameKey],
            foundPeripheralName as? String == wantedPeripheralName {

            activePeripheral = peripheral
            print("\(foundPeripheralName) device found.")
        } else {
            
            /// No name or name match so check peripheral's service UUIDs against wanted service uuids
            guard let uuidsOfRemotePeripheral = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] else {
                print("Peripheral has no service ids. Ignoring.")
                return
            }
            
            // If any of the wanted services are found in the current peripheral's services, keep it.
            for uuid in wantedServices {
                if uuidsOfRemotePeripheral.contains(uuid) {
                    peripheralsWithWantedServices.append(peripheral)
                    activePeripheral = peripheral
                    break
                }
            }
        }
        
        // Current assumption is that there is only one peripheral with our requested service uuids.
        // This means we just choose the last match.
        // FIXME: Don't rely on that assumption. Have a (eg. user) resolution if there are multiples.
        if let activePeripheral = activePeripheral {
            print("db: activePeripheral id: \(activePeripheral.identifier)")
            /// Stop scanning for more devices.
            centralManager.stopScan()
            
            activePeripheral.delegate = self
            centralManager.connect(activePeripheral, options: nil)
        }
    }
    
    /** Called on successful connection with peripheral. */
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        print("Discovering services \(String(describing: wantedServices))...")
        
        /// Request enumeration of peripheral services.
        peripheral.discoverServices(wantedServices)
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        print("Disconnected")
        /// It's now safe to free the peripheral and manager
        activePeripheral = nil
        centralManager = nil
    }
    
}

extension BluetoothIO : CBPeripheralDelegate {
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        
        guard wantedServices != nil else {
            print("No services to look for! Exiting")
            return
        }
        print("Evaluating service.")
        
        for service in peripheral.services! {
            if wantedServices!.contains(service.uuid) {
                
                let wantedCharacteristics = characteristicsForService[service.uuid]
                /// Request enumeration of service characteristics.
                peripheral.discoverCharacteristics(wantedCharacteristics, for: service)
                
            } else {
                print("Found other service uuid \(service.uuid)")
            }
        }
    }
    
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        guard let wantedCharacteristics = characteristicsForService[service.uuid] else {
            print("No characteristics to look for! Exiting.")
            return
        }
        
        print("Enabling sensors.")
        
        for characteristic in service.characteristics! {
            if wantedCharacteristics.contains(characteristic.uuid) {
                if characteristic.properties.contains(.notify) {
                    print("This characteristic will notify of updates.")
                    activePeripheral?.setNotifyValue(true, for: characteristic)
                }
                if characteristic.properties.contains(.read) {
                    print("This characteristic can be read.")
                    activePeripheral?.readValue(for: characteristic)
                }
                //                activePeripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        print("did update value for \(characteristic.uuid).")
        
        /// This is where we would pass the characteristic to the handler.
        if let handler = handlerForCharacteristic[characteristic.uuid] {
            do { try handler(characteristic) } catch {
                print("Error: ", error, "in characteristic handler.")
            }
        }
    }
}


