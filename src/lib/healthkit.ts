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

/**
 * Three possible outcomes from requesting HealthKit permission:
 *  - 'granted'     → user approved, safe to query
 *  - 'denied'      → user declined in the iOS permission dialog
 *  - 'unavailable' → the native plugin bridge isn't wired up in Xcode yet
 *                    (Capacitor returns code: 'UNIMPLEMENTED').
 *                    Fix: run `npx cap sync ios`, add the HealthKit capability
 *                    in Xcode, and add NSHealthShareUsageDescription to Info.plist.
 */
export type HealthKitPermResult = 'granted' | 'denied' | 'unavailable'

export function isHealthKitAvailable(): boolean {
  return Capacitor.isNativePlatform() && Capacitor.getPlatform() === 'ios'
}

export async function requestHealthKitPermissions(): Promise<HealthKitPermResult> {
  try {
    const { CapacitorHealthkit } = await import('@capacitor-community/health-kit')
    await CapacitorHealthkit.requestAuthorization({
      all: [],
      read: ['bodyMass', 'bodyFatPercentage', 'leanBodyMass', 'bodyMassIndex'],
      write: [],
    })
    return 'granted'
  } catch (e) {
    // Capacitor throws code:'UNIMPLEMENTED' when the Swift plugin files are
    // present in node_modules but haven't been synced into the Xcode project,
    // or when the HealthKit entitlement hasn't been enabled in Xcode.
    const code = (e as { code?: string })?.code
    if (code === 'UNIMPLEMENTED') {
      console.warn(
        '[HealthKit] Plugin not wired up. Run: npx cap sync ios\n' +
        'Then in Xcode → your target → Signing & Capabilities → add HealthKit.\n' +
        'Also add NSHealthShareUsageDescription to Info.plist.',
      )
      return 'unavailable'
    }
    console.error('HealthKit permission error:', e)
    return 'denied'
  }
}

export async function importFromHealthKit(daysBack = 365): Promise<HealthImportResult> {
  const { CapacitorHealthkit } = await import('@capacitor-community/health-kit')
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
