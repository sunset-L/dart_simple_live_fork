import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  build: {
    rolldownOptions: {
      output: {
        codeSplitting: {
          groups: [
            {
              name: "react-vendor",
              test: /node_modules[\\/](?:react|react-dom|scheduler)[\\/]/,
              priority: 30,
            },
            {
              name: "lucide-icons",
              test: /node_modules[\\/]lucide-react[\\/]/,
              entriesAware: true,
              entriesAwareMergeThreshold: 8 * 1024,
              priority: 20,
            },
          ],
        },
      },
    },
  },
  server: {
    port: 5173,
    watch: {
      usePolling: process.platform === "win32",
      interval: 300,
    },
    proxy: {
      "/api": { target: `http://127.0.0.1:${process.env.PORT || "23236"}` },
      "/ws": {
        target: `ws://127.0.0.1:${process.env.PORT || "23236"}`,
        ws: true,
      },
    },
  },
});
