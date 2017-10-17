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
//    var activePeripheral: CBPeripheral?
    var connectedPeripherals = [CBPeripheral]()
    
    var wantedPeripheralName: String?
    
    var peripheralsWithWantedServices: [CBPeripheral]!
    var wantedServices: [CBUUID]?
    var maxPeripheralCount: Int?
    
    var characteristicsForService: [CBUUID : [CBUUID]]?
    var handlerForCharacteristic: [CBUUID : (CBCharacteristic) throws -> Void]!
    
    // Methods for handling the discovery of Peripherals, Services and Characteristics.
    var discoveredPeripheralsHandler: ((CBPeripheral)->Void)?
    var discoveredServicesHandler: (([CBService]?)->Void)?
    var discoveredCharacteristicsHandler: (([CBCharacteristic]?)->Void)?
    
    // Called when a peripheral is connected.
    var connectedPeripheralHandler: ((CBPeripheral)->Void)?
    var disconnectedPeripheralHandler: ((CBPeripheral)->Void)?
    
    // Map of characteristic uuid to handler.
    var characteristicHandlers: [CBUUID : (CBCharacteristic) throws -> Void]!
    
    
    public static let sharedInstance : BluetoothIO = {
        
        let instance = BluetoothIO()
        return instance
    }()

    // Call first to set up.
    
//    public func set(characteristicsForService: [CBUUID : [CBUUID]], handlerForCharacteristic: [CBUUID : (CBCharacteristic) throws -> Void] ) {
//
//        self.characteristicsForService = characteristicsForService
//        self.handlerForCharacteristic = handlerForCharacteristic
//    }

    public func set(handlerForCharacteristic: [CBUUID : (CBCharacteristic) throws -> Void] ) {
        // FIXME: make this so that we can add rather than replace.
//        if self.handlerForCharacteristic != nil {
//            self.handlerForCharacteristic.merge(handlerForCharacteristic, uniquingKeysWith: <#T##((CBCharacteristic) throws -> Void, (CBCharacteristic) throws -> Void) throws -> (CBCharacteristic) throws -> Void#>)
//        }
        self.handlerForCharacteristic = handlerForCharacteristic
    }

    public func discoverPeripherals(name: String? = nil, serviceIds: [CBUUID]?, maxPeripheralCount: Int? = nil, handler: @escaping (CBPeripheral)->Void) {
        
        peripheralsWithWantedServices = []
        
        wantedPeripheralName = name
        wantedServices = serviceIds

        self.maxPeripheralCount = maxPeripheralCount
        
        discoveredPeripheralsHandler = handler
        
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }
    
    public func discoverServices(wantedServices: [CBUUID]? = nil, for peripheral: CBPeripheral, handler: @escaping ([CBService]?)->Void) {
        
        discoveredServicesHandler = handler
        
        peripheral.discoverServices(wantedServices)
        
    }
    
    public func discoverCharacteristics(wanted: [CBUUID]? = nil, for service: CBService, handler: @escaping ([CBCharacteristic]?)->Void) {
        discoveredCharacteristicsHandler = handler
    
        if let wanted = wanted { characteristicsForService = [service.uuid : wanted] }
        
        print("btio: discoverCharacteristics called.")
        // peripheral.discoverCharacteristics(wantedCharacteristics, for: service)
        service.peripheral.discoverCharacteristics(wanted, for: service)
    }
//    public func register(handlers: [CBUUID : (CBCharacteristic) throws -> Void]) {
//        characteristicHandlers = handlers
//    }
    
    public func connect(peripherals: [CBPeripheral], handler: @escaping (CBPeripheral)->Void) {
        
        connectedPeripheralHandler = handler
        
        for peripheral in peripherals {
            centralManager.connect(peripheral, options: nil)
        }
    }
    
//    public func start(_ peripheralName: String, services: [CBUUID], characteristics: [CBUUID : [CBUUID]], handlers: [CBUUID : (CBCharacteristic) throws -> Void] ) {
//
//        wantedPeripheralName = peripheralName
//        wantedServices = services
//
//        peripheralsWithWantedServices = []
//
//        characteristicsForService = characteristics
//        handlerForCharacteristic = handlers
//
//        centralManager = CBCentralManager(delegate: self, queue: nil)
//    }
    
    public func stop() {
        
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        
//        guard let ap = activePeripheral else { return }
        for cp in connectedPeripherals {
            
            /// For each service go through each characteristic and disable notification if active.
            _ = cp.services?.map { service in
                service.characteristics?.map { char in
                    guard char.isNotifying == true else { return }
                    cp.setNotifyValue(false, for: char)
                }
            }
            print("Cancelling peripheral connection to \(cp)")
            centralManager.cancelPeripheralConnection(cp)
        }
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
        
//        guard wantedServices != nil else {
//            print("No wanted services.")
//            return
//        }
        
        central.scanForPeripherals(withServices: wantedServices, options: nil)
        
        print("Searching for BLE devices with services \(String(describing: wantedServices))...")
        
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("centralManager: didDiscover called.")
        
        if let peripheralName = advertisementData[CBAdvertisementDataLocalNameKey] {
            print("centralManager: Peripheral name is \(peripheralName)")
        }
        
        print("centralManager: Peripheral name2 is \(String(describing: peripheral.name)) and id is \(peripheral.identifier)")
        

        // TODO: look for CBAdvertisementDataServiceUUIDsKey match as well.
        /// See if the device name matches what we're looking for.
        
        //activePeripheral = nil
        var activePeripheral: CBPeripheral?
        
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
         
            print("centralManager: peripheral provides the following service uuids: \(uuidsOfRemotePeripheral)")
            guard let wantedServices = wantedServices else { return }
            // If any of the wanted services are found in the current peripheral's services, keep it.
            for uuid in wantedServices {
                if uuidsOfRemotePeripheral.contains(uuid) {
                    activePeripheral = peripheral
                    break
                }
            }
        }
        
        // Current assumption is that there is only one peripheral with our requested service uuids.
        // This means we just choose the first match.
        if let activePeripheral = activePeripheral {
            print("db: activePeripheral id: \(activePeripheral.identifier)")
            
            activePeripheral.delegate = self
            
            if peripheralsWithWantedServices.contains(peripheral) == false {
                
                peripheralsWithWantedServices.append(peripheral)
                
                discoveredPeripheralsHandler?(peripheral)
            }
            
            // Stop scanning when we've reached the max count.
            if let maxCount = maxPeripheralCount, peripheralsWithWantedServices.count >= maxCount {
                print("Stopping scan for peripherals.")
                centralManager.stopScan()
                
            }
        }
    }
    
    /** Called on successful connection with peripheral. */
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        print("Central manager did connect to peripheral \(peripheral).")
        print("Discovering services \(String(describing: wantedServices))...")
        
        connectedPeripherals.append(peripheral)
        connectedPeripheralHandler?(peripheral)
        
        /// Request enumeration of peripheral services.
        //teotemp peripheral.discoverServices(wantedServices)
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        print("Disconnected peripheral \(peripheral)")
        
        disconnectedPeripheralHandler?(peripheral)
        
        /// It's now safe to free the peripheral and manager
        if let idx = connectedPeripherals.index(of: peripheral) {
            connectedPeripherals.remove(at: idx)
        }
        
        if connectedPeripherals.count == 0 {
            centralManager = nil
        }
    }
    
}

extension BluetoothIO : CBPeripheralDelegate {
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
//        guard wantedServices != nil else {
//            print("No services to look for! Exiting")
//            return
//        }
        print("Evaluating service.")

        guard let services = peripheral.services else {
            print("Peripheral \(peripheral.identifier) has no services. Returning.")
            return
        }
        
        var matchingServices: [CBService]?
        
        for service in services {
            // Skip if we are looking for specific services and this service is not one of them.
            if let wantedServices = wantedServices,
                wantedServices.contains(service.uuid) == false { continue }
            
            matchingServices = matchingServices ?? [CBService]()
            matchingServices!.append(service)
            //teotemp let wantedCharacteristics = characteristicsForService?[service.uuid]
            /// Request enumeration of service characteristics.
            //teotemp peripheral.discoverCharacteristics(wantedCharacteristics, for: service)
        }
        
        discoveredServicesHandler?(matchingServices)
    }
    
    // FIXME: rewrite this to return the discovered characteristics rather than just calling them.
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        print(">>>>>>")
        print("didDiscoverCharacteristicsFor \(service.uuid)")
        
        guard error == nil else {
            print("There was an error discovering characteristics: \(String(describing: error))")
            return
        }
        let wantedCharacteristics = characteristicsForService?[service.uuid]
//        guard let wantedCharacteristics = characteristicsForService?[service.uuid] else {
//            print("No characteristics to look for! Exiting.")
//            return
//        }
        
        guard let foundCharacteristics = service.characteristics else {
            print("The service \(service.uuid) contained no characteristics.")
            return
        }
        
        print("Enabling sensors. There are \(foundCharacteristics.count) characteristics")

        var matchingCharacteristics: [CBCharacteristic]?
        
        for characteristic in foundCharacteristics {
            print("Found characteristic uuid \(characteristic.uuid)")

            // Request further descriptor for this characteristic.
            // This should be called only when specifically requesting info.
//teotest            peripheral.discoverDescriptors(for: characteristic)
            // Skip if we are looking for specific services and this service is not one of them.
//            if let wantedServices = wantedServices,
//                wantedServices.contains(service.uuid) == false { continue }
            
            if let wantedCharacteristics = wantedCharacteristics,
                wantedCharacteristics.contains(characteristic.uuid) == false { continue }
        
            matchingCharacteristics = matchingCharacteristics ?? [CBCharacteristic]()
            matchingCharacteristics?.append(characteristic)
            
            if characteristic.properties.contains(.notify) {
                print("This characteristic will notify of updates.")
                //peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.read) {
                
                print("This characteristic can be read.")
                //peripheral.readValue(for: characteristic)
            }
            if characteristic.properties.contains(.write) {
                print("This characteristic can be written to.")
            }
        }
        
        discoveredCharacteristicsHandler?(matchingCharacteristics)
        print("<<<<<<")
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        print("Peripheral \(peripheral) did update value for \(characteristic.uuid).")
        
        /// This is where we would pass the characteristic to the handler.
        do { try handlerForCharacteristic[characteristic.uuid]?(characteristic) } catch {
            print("Error: ", error, "in characteristic handler.")
        }
        
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("There was an error writing to the characteristic \(characteristic): \(String(describing: error))")
            return
        }
        
        do { try handlerForCharacteristic[characteristic.uuid]?(characteristic) }
        catch {
            print("Error: ", error, "in characteristic write handler.")
        }
        
    }
    
    // MARK: descriptor discovery and updating methods. Currently for debugging only.
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
            print("The characteristic \(characteristic) descriptors are \(String(describing: characteristic.descriptors))")
        guard let tors = characteristic.descriptors else { return }
        for desc in tors {
            peripheral.readValue(for: desc)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        print("The descriptor \(descriptor.description) for characteristic \(descriptor.characteristic) value was \(String(describing: descriptor.value))")
    }
}


