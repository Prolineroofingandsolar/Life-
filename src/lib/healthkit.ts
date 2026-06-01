import { CapacitorHealthkit } from '@perfood/capacitor-healthkit'
import type { OtherData, QueryOutput } from '@perfood/capacitor-healthkit'

const READ_PERMISSIONS = ['bodyMass', 'bodyFatPercentage', 'leanBodyMass', 'bodyMassIndex']

export interface HealthSample {
  date: string // YYYY-MM-DD
  value: number
}

export interface HealthImportResult {
  weight: HealthSample[]
  bodyFat: HealthSample[]
  leanMass: HealthSample[]
  bmi: HealthSample[]
}

function toDateKey(dateString: string): string {
  return dateString.slice(0, 10)
}

function extractSamples(output: QueryOutput<OtherData>): HealthSample[] {
  return (output.resultData ?? []).map((s) => ({
    date: toDateKey(s.startDate),
    value: Math.round(s.value * 100) / 100,
  }))
}

export async function requestHealthKitPermissions(): Promise<boolean> {
  try {
    await CapacitorHealthkit.requestAuthorization({ all: [], read: READ_PERMISSIONS, write: [] })
    return true
  } catch {
    return false
  }
}

export async function importFromHealthKit(daysBack = 365): Promise<HealthImportResult> {
  const endDate = new Date().toISOString()
  const startDate = new Date(Date.now() - daysBack * 24 * 60 * 60 * 1000).toISOString()

  const [weight, bodyFat, leanMass, bmi] = await Promise.all([
    CapacitorHealthkit.queryHKitSampleType<OtherData>({
      sampleName: 'bodyMass',
      startDate,
      endDate,
      limit: 0,
    }),
    CapacitorHealthkit.queryHKitSampleType<OtherData>({
      sampleName: 'bodyFatPercentage',
      startDate,
      endDate,
      limit: 0,
    }),
    CapacitorHealthkit.queryHKitSampleType<OtherData>({
      sampleName: 'leanBodyMass',
      startDate,
      endDate,
      limit: 0,
    }),
    CapacitorHealthkit.queryHKitSampleType<OtherData>({
      sampleName: 'bodyMassIndex',
      startDate,
      endDate,
      limit: 0,
    }),
  ])

  return {
    weight: extractSamples(weight),
    bodyFat: extractSamples(bodyFat),
    leanMass: extractSamples(leanMass),
    bmi: extractSamples(bmi),
  }
}

export function isHealthKitAvailable(): boolean {
  try {
    // CapacitorHealthkit is only functional on native iOS
    return (window as unknown as { Capacitor?: { isNativePlatform?: () => boolean } }).Capacitor?.isNativePlatform?.() ?? false
  } catch {
    return false
  }
}
