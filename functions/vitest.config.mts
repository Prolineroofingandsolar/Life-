import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    // The rules tests share one emulator instance and clear the database
    // between cases, so they must not run concurrently with each other.
    fileParallelism: false,
    testTimeout: 20_000,
    hookTimeout: 60_000,
  },
})
