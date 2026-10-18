import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import process from "node:process";
const backend = process.env.HUAIWEI_API_ORIGIN ?? "http://127.0.0.1:8080";
export default defineConfig({
  plugins: [vue()],
  build: {
    outDir: "../web",
    emptyOutDir: true,
    rollupOptions: { input: { main: "index.html", admin: "admin/index.html" } },
  },
  server: {
    proxy: {
      "/api": backend,
      "/ws": { target: backend.replace("http", "ws"), ws: true },
    },
  },
});
