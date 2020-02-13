//
//  SimulatorsController.swift
//  ControlRoom
//
//  Created by Dave DeLong on 2/12/20.
//  Copyright © 2020 Paul Hudson. All rights reserved.
//

import Combine
import Foundation
import SwiftUI

private enum SimCtl {

    /// Handles decoding the device list from simctl
    struct DeviceList: Decodable {
        var devices: [String: [Simulator]]
    }

    struct Simulator: Decodable {
        let name: String
        let udid: String
        let deviceTypeIdentifier: String
        let dataPath: String
    }

    struct DeviceTypeList: Decodable {
        let devicetypes: [DeviceType]
    }

    struct DeviceType: Decodable {
        let bundlePath: String
        let name: String
        let identifier: String

        var modelTypeIdentifier: TypeIdentifier? {
            guard let bundle = Bundle(path: bundlePath) else { return nil }
            guard let plist = bundle.url(forResource: "profile", withExtension: "plist") else { return nil }
            guard let contents = NSDictionary(contentsOf: plist) else { return nil }
            guard let modelIdentifier = contents.object(forKey: "modelIdentifier") as? String else { return nil }

            return TypeIdentifier(modelIdentifier: modelIdentifier)
        }
    }

}

class SimulatorsController: ObservableObject {

    /// Tracks the state of fetching simulator data from simctl
    enum LoadingStatus {
        /// Loading is in progress
        case loading

        /// Loading succeeded
        case success

        /// Loading failed
        case failed
    }

    private var allSimulators: [Simulator] = []

    @Published var loadingStatus: LoadingStatus = .loading
    @Published var simulators: [Simulator] = []

    var filterText = "" {
        willSet { objectWillChange.send() }
        didSet { filterSimulators() }
    }

    var selectedSimulator: Simulator? {
        willSet { objectWillChange.send() }
    }

    init() {
        loadSimulators()
    }

    private func loadSimulators() {
        loadingStatus = .loading

        Command.simctl("list", "devices", "available", "-j") { result in
            switch result {
            case .success(let data):
                let list = try? JSONDecoder().decode(SimCtl.DeviceList.self, from: data)
                let parsed = list?.devices.values.flatMap { $0 }
                self.loadDeviceTypes(parsedSimulators: parsed)
            case .failure:
                self.loadDeviceTypes(parsedSimulators: nil)
            }
        }
    }

    private func loadDeviceTypes(parsedSimulators: [SimCtl.Simulator]?) {
        Command.simctl("list", "devicetypes", "-j") { result in
            switch result {
            case .success(let data):
                let list = try? JSONDecoder().decode(SimCtl.DeviceTypeList.self, from: data)
                self.merge(parsedSimulators: parsedSimulators, deviceTypes: list?.devicetypes)
            case .failure:
                self.merge(parsedSimulators: parsedSimulators, deviceTypes: nil)
            }
        }
    }

    private func merge(parsedSimulators: [SimCtl.Simulator]?, deviceTypes: [SimCtl.DeviceType]?) {
        let rawTypes = deviceTypes ?? []
        let typesByIdentifier = Dictionary(grouping: rawTypes, by: { $0.identifier }).compactMapValues({ $0.first })

        let merged = parsedSimulators?.map { sim -> Simulator in
            let deviceType = typesByIdentifier[sim.deviceTypeIdentifier]
            return Simulator(name: sim.name, udid: sim.udid, typeIdentifier: deviceType?.modelTypeIdentifier ?? .anyDevice)
        }

        handleParsedSimulators(merged)
    }

    private func handleParsedSimulators(_ newSimulators: [Simulator]?) {
        objectWillChange.send()

        if let new = newSimulators {
            allSimulators = [.default] + new
            filterSimulators()
            loadingStatus = .success
        } else {
            loadingStatus = .failed
        }
    }

    private func filterSimulators() {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            simulators = allSimulators.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        } else {
            simulators = allSimulators
        }

        if let current = selectedSimulator {
            if simulators.firstIndex(of: current) == nil {
                // the current simulator is not in the list of filtered simulators
                // deselect it
                selectedSimulator = nil
            }
        }

        if selectedSimulator == nil {
            selectedSimulator = simulators.first
        }
    }

}
