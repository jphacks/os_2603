import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { viteSingleFile } from "vite-plugin-singlefile";

// build 時は JS/CSS をすべて index.html にインライン化し、
// 1枚の自己完結HTMLにする（公開URLとして配りやすくするため）。
export default defineConfig({
  base: "./",
  plugins: [react(), viteSingleFile()],
  server: {
    host: true,
    port: 5173,
  },
});
