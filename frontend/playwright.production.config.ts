import { defineConfig } from "@playwright/test";
export default defineConfig({
  outputDir: "test-results-full",
  testDir: "e2e-production",
  timeout: 40000,
  workers: 1,
  use: {
    baseURL: "http://127.0.0.1:4175",
    headless: true,
    trace: "retain-on-failure",
  },
  webServer: [
    {
      command: "bash ../tests/run-full-app.sh",
      url: "http://127.0.0.1:8095/health",
      timeout: 30000,
    },
    {
      command:
        "HUAIWEI_API_ORIGIN=http://127.0.0.1:8095 npm run dev -- --port 4175",
      url: "http://127.0.0.1:4175",
      timeout: 30000,
    },
  ],
});
