// Copyright 2025 Radim Simanek
// License: MIT
// https://github.com/Rad1m

import SwiftUI
import UniformTypeIdentifiers
import Foundation
import HealthKit

// HealthKit Units Helper
struct HealthKitUnits {
    static func unit(for dataType: String) -> HKUnit {
        switch dataType {
        case "HKQuantityTypeIdentifierActiveEnergyBurned":
            return .kilocalorie()
        case "HKQuantityTypeIdentifierStepCount",
             "HKQuantityTypeIdentifierFlightsClimbed",
             "HKCategoryTypeIdentifierAppleStandHour",
             "HKQuantityTypeIdentifierNumberOfAlcoholicBeverages":
            return .count()
        case "HKQuantityTypeIdentifierDistanceWalkingRunning":
            return .meter()
        case "HKQuantityTypeIdentifierDietaryEnergyConsumed":
            return .kilocalorie()
        case "HKQuantityTypeIdentifierDietaryCaffeine":
            return HKUnit.gramUnit(with: .milli)
        case "HKQuantityTypeIdentifierTimeInDaylight":
            return .hour()
        default:
            return .count() // Fallback unit
        }
    }
}

// Main ContentView
struct ContentView: View {
    private let relevantDataTypes: [String: String] = [
        "HKCategoryTypeIdentifierSleepAnalysis": "Sleep Analysis",
        "HKQuantityTypeIdentifierActiveEnergyBurned": "Active Energy Burned",
        "HKQuantityTypeIdentifierStepCount": "Step Count",
        "HKQuantityTypeIdentifierDistanceWalkingRunning": "Distance Walking/Running",
        "HKQuantityTypeIdentifierFlightsClimbed": "Flights Climbed",
        "HKQuantityTypeIdentifierDietaryEnergyConsumed": "Dietary Energy Consumed",
        "HKQuantityTypeIdentifierDietaryCaffeine": "Dietary Caffeine",
        "HKQuantityTypeIdentifierNumberOfAlcoholicBeverages": "Alcoholic Beverages",
        "HKQuantityTypeIdentifierTimeInDaylight": "Time in Daylight",
        "HKCategoryTypeIdentifierAppleStandHour": "Apple Stand Hour"
    ]

    @State private var isFileImporterPresented = false
    @State private var selectedFileURL: URL? = nil
    @State private var availableDataTypes: [String] = []
    @State private var selectedDataType: String = ""
    @State private var isImportConfirmationPresented = false
    @State private var unsupportedTypeAlertPresented = false
    @State private var isSuccessAlertPresented = false

    private let healthStore = HKHealthStore()

    var body: some View {
        VStack(spacing: 20) {
            FileSelectorButton(isFileImporterPresented: $isFileImporterPresented)
            SelectedFileView(fileName: selectedFileURL?.lastPathComponent)
            AnalyzeButton(action: analyzeFile)
            if !availableDataTypes.isEmpty {
                DataTypePicker(availableDataTypes: availableDataTypes,
                               relevantDataTypes: relevantDataTypes,
                               selectedDataType: $selectedDataType)
            }
            ImportDataButton(action: requestHealthAccessAndImport)
        }
        .padding()
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.xml],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .alert(isPresented: $isImportConfirmationPresented) {
            Alert(
                title: Text("Start Import"),
                message: Text("Would you like to start import for \(selectedDataType)?"),
                primaryButton: .default(Text("Yes"), action: importData),
                secondaryButton: .cancel()
            )
        }
        .alert("Unsupported Data Type", isPresented: $unsupportedTypeAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The selected data type \(selectedDataType) is not supported for writing to Apple Health.")
        }
        .alert("Success", isPresented: $isSuccessAlertPresented) {
            Button("OK") {}
        } message: {
            Text("Data for \(selectedDataType) has been successfully imported to Apple Health.")
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            selectedFileURL = urls.first
            print("Selected file: \(selectedFileURL?.lastPathComponent ?? "None")")
        case .failure(let error):
            print("Failed to select file: \(error.localizedDescription)")
        }
    }

    private func analyzeFile() {
        guard let fileURL = selectedFileURL else {
            print("No file selected to analyze.")
            return
        }

        do {
            let xmlData = try Data(contentsOf: fileURL)
            let parser = XMLParser(data: xmlData)
            let delegate = HealthDataXMLParserDelegate()
            parser.delegate = delegate

            if parser.parse() {
                availableDataTypes = Array(delegate.dataTypes).filter { relevantDataTypes.keys.contains($0) }.sorted()
                selectedDataType = availableDataTypes.first ?? ""
                print("Available writable data types: \(availableDataTypes)")
            } else {
                print("Failed to parse XML file.")
            }
        } catch {
            print("Error reading file: \(error.localizedDescription)")
        }
    }

    private func requestHealthAccessAndImport() {
        guard !selectedDataType.isEmpty else {
            print("No data type selected.")
            return
        }

        let sampleType: HKSampleType?
        if selectedDataType == "HKCategoryTypeIdentifierSleepAnalysis" {
            sampleType = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)
        } else {
            sampleType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: selectedDataType))
        }
        guard let sampleType = sampleType else {
            unsupportedTypeAlertPresented = true
            print("Unsupported data type: \(selectedDataType)")
            return
        }

        healthStore.requestAuthorization(toShare: Set([sampleType]), read: []) { success, error in
            if success {
                print("Access granted for \(selectedDataType)")
                DispatchQueue.main.async {
                    isImportConfirmationPresented = true
                }
            } else {
                print("Authorization failed: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }

    private func importData() {
        let unit = HealthKitUnits.unit(for: selectedDataType)
        let calendar = Calendar.current
        let now = Date()

        if selectedDataType == "HKCategoryTypeIdentifierSleepAnalysis" {
            guard let sampleType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
                print("Invalid data type: \(selectedDataType)")
                return
            }

            let sleepPhases: [HKCategoryValueSleepAnalysis] = [
                .inBed, .awake, .asleepCore, .asleepDeep, .asleepREM
            ]

            let samples: [HKCategorySample] = (0..<90).compactMap { dayOffset in
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { return nil }
                let phase = sleepPhases.randomElement() ?? .asleepCore
                return HKCategorySample(type: sampleType, value: phase.rawValue, start: date, end: date.addingTimeInterval(8 * 60 * 60)) // 8 hours of sleep
            }
            healthStore.save(samples) { success, error in
                if success {
                    print("Data successfully imported to Apple Health. Number of data points: \(samples.count)")
                    DispatchQueue.main.async {
                        isSuccessAlertPresented = true
                    }
                } else {
                    print("Failed to import data: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
            return
        }

        guard let sampleType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: selectedDataType)) else {
            print("Invalid data type: \(selectedDataType)")
            return
        }

        let samples: [HKQuantitySample] = (0..<90).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { return nil }
            let quantity = HKQuantity(unit: unit, doubleValue: Double.random(in: 1...100))
            return HKQuantitySample(type: sampleType, quantity: quantity, start: date, end: date)
        }

        healthStore.save(samples) { success, error in
            if success {
                print("Data successfully imported to Apple Health. Number of data points: \(samples.count)")
                DispatchQueue.main.async {
                    isSuccessAlertPresented = true
                }
            } else {
                print("Failed to import data: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
}

// Subviews
struct FileSelectorButton: View {
    @Binding var isFileImporterPresented: Bool

    var body: some View {
        Button(action: {
            isFileImporterPresented = true
        }) {
            Text("Select File")
                .font(.title2)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
    }
}

struct SelectedFileView: View {
    var fileName: String?

    var body: some View {
        Text(fileName != nil ? "Selected File: \(fileName!)" : "No file selected")
            .font(.body)
            .padding()
    }
}

struct AnalyzeButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Analyze File")
                .font(.title2)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
    }
}

struct DataTypePicker: View {
    var availableDataTypes: [String]
    var relevantDataTypes: [String: String]
    @Binding var selectedDataType: String

    var body: some View {
        VStack {
            Text("Select a Data Type:")
                .font(.headline)
                .padding(.top)

            Picker("Select Data Type", selection: $selectedDataType) {
                ForEach(availableDataTypes, id: \.self) { dataType in
                    if let readableName = relevantDataTypes[dataType] {
                        Text(readableName).tag(dataType)
                    }
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding()
        }
    }
}

struct ImportDataButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Import Data")
                .font(.title2)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
    }
}

// XML Parser Delegate
class HealthDataXMLParserDelegate: NSObject, XMLParserDelegate {
    var dataTypes: Set<String> = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "Record", let type = attributeDict["type"] {
            dataTypes.insert(type)
        }
    }
}

// Main App Entry
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
