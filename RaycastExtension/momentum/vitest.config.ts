import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    clearMocks: true,
    restoreMocks: true,
    unstubGlobals: true,
  },
  resolve: {
    alias: {
      "@raycast/api": path.resolve(__dirname, "src/__tests__/raycast-api.stub.ts"),
    },
  },
});
