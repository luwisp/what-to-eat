import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "e2e",
  timeout: 30000,
  fullyParallel: false,
  use: {
    baseURL: "http://127.0.0.1:4173",
    headless: true,
    trace: "retain-on-failure",
  },
  webServer: [
    {
      command:
        "HUAIWEI_PORT=8089 HUAIWEI_PUBLIC_BASE_URL=http://127.0.0.1:4173 bash ../scripts/cj.sh exec target/integration/dining-server",
      url: "http://127.0.0.1:8089/health",
      reuseExistingServer: false,
      timeout: 30000,
    },
    {
      command:
        "HUAIWEI_API_ORIGIN=http://127.0.0.1:8089 npm run dev -- --port 4173",
      url: "http://127.0.0.1:4173",
      reuseExistingServer: false,
      timeout: 30000,
    },
  ],
});
