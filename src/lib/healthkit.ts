import { Capacitor } from '@capacitor/core'

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

export function isHealthKitAvailable(): boolean {
  return Capacitor.isNativePlatform() && Capacitor.getPlatform() === 'ios'
}

export async function requestHealthKitPermissions(): Promise<boolean> {
  try {
    const { CapacitorHealthkit } = await import('@perfood/capacitor-healthkit')
    await CapacitorHealthkit.requestAuthorization({
      all: [],
      read: ['bodyMass', 'bodyFatPercentage', 'leanBodyMass', 'bodyMassIndex'],
      write: [],
    })
    return true
  } catch (e) {
    // UNIMPLEMENTED = native plugin not registered in Xcode yet; suppress noisy log
    if ((e as { code?: string })?.code !== 'UNIMPLEMENTED') {
      console.error('HealthKit permission error:', e)
    }
    return false
  }
}

export async function importFromHealthKit(daysBack = 365): Promise<HealthImportResult> {
  const { CapacitorHealthkit } = await import('@perfood/capacitor-healthkit')
  const endDate = new Date().toISOString()
  const startDate = new Date(Date.now() - daysBack * 24 * 60 * 60 * 1000).toISOString()

  function toDateKey(d: string) { return d.slice(0, 10) }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  function extract(output: any): HealthSample[] {
    return (output.resultData ?? []).map((s: { startDate: string; value: number }) => ({
      date: toDateKey(s.startDate),
      value: Math.round(s.value * 100) / 100,
    }))
  }

  const [weight, bodyFat, leanMass, bmi] = await Promise.all([
    CapacitorHealthkit.queryHKitSampleType({ sampleName: 'bodyMass', startDate, endDate, limit: 0 }),
    CapacitorHealthkit.queryHKitSampleType({ sampleName: 'bodyFatPercentage', startDate, endDate, limit: 0 }),
    CapacitorHealthkit.queryHKitSampleType({ sampleName: 'leanBodyMass', startDate, endDate, limit: 0 }),
    CapacitorHealthkit.queryHKitSampleType({ sampleName: 'bodyMassIndex', startDate, endDate, limit: 0 }),
  ])

  return {
    weight: extract(weight),
    bodyFat: extract(bodyFat),
    leanMass: extract(leanMass),
    bmi: extract(bmi),
  }
}
