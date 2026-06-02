import Foundation
import HealthKit

// MARK: - HealthKit Manager

final class HealthKitManager {

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let identifiers: [HKQuantityTypeIdentifier] = [
            .bodyMass,
            .bodyFatPercentage,
            .leanBodyMass,
            .bodyMassIndex
        ]
        for id in identifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        return types
    }

    // MARK: - Permission

    func requestPermissions() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Import

    struct BodyDataResult {
        var weight: [(date: Date, kg: Double)] = []
        var bodyFat: [(date: Date, pct: Double)] = []
        var leanMass: [(date: Date, kg: Double)] = []
        var bmi: [(date: Date, val: Double)] = []
    }

    func importBodyData(daysBack: Int = 365) async -> BodyDataResult {
        guard HKHealthStore.isHealthDataAvailable() else { return BodyDataResult() }

        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: endDate) else {
            return BodyDataResult()
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        async let weight = fetchQuantitySamples(
            identifier: .bodyMass,
            unit: HKUnit.gramUnit(with: .kilo),
            predicate: predicate
        )
        async let bodyFat = fetchQuantitySamples(
            identifier: .bodyFatPercentage,
            unit: HKUnit.percent(),
            predicate: predicate
        )
        async let leanMass = fetchQuantitySamples(
            identifier: .leanBodyMass,
            unit: HKUnit.gramUnit(with: .kilo),
            predicate: predicate
        )
        async let bmi = fetchQuantitySamples(
            identifier: .bodyMassIndex,
            unit: HKUnit.count(),
            predicate: predicate
        )

        let (w, bf, lm, b) = await (weight, bodyFat, leanMass, bmi)
        return BodyDataResult(weight: w, bodyFat: bf, leanMass: lm, bmi: b)
    }

    // MARK: - Private

    private func fetchQuantitySamples(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate
    ) async -> [(date: Date, value: Double)] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard error == nil,
                      let quantitySamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let result = quantitySamples.map { sample in
                    (date: sample.startDate, value: sample.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }
}
