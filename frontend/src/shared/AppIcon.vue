<script setup lang="ts">
withDefaults(defineProps<{ name: string; size?: number }>(), { size: 24 });
const paths: Record<string, string> = {
  chat: "M21 11a8 8 0 0 1-8 8H6l-4 3V11a9 9 0 0 1 19 0ZM7 10h10M7 14h6",
  image: "M3 3h18v18H3ZM3 16l5-5 4 4 3-3 6 6M15 7h.01",
  trash: "M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7",
  home: "M3 10 12 3l9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z",
  user: "M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0ZM4 21v-2a8 8 0 0 1 16 0v2",
  scan: "M8 3H4a1 1 0 0 0-1 1v4m13-5h4a1 1 0 0 1 1 1v4M3 16v4a1 1 0 0 0 1 1h4m8 0h4a1 1 0 0 0 1-1v-4M3 12h18M8 7v2m8-2v2M8 15v2m8-2v2",
  dish: "M3 13a9 9 0 0 1 18 0M2 16h20M6 20h12M12 3v1",
  group:
    "M15 7a3 3 0 1 1-6 0 3 3 0 0 1 6 0ZM6 21v-3a6 6 0 0 1 12 0v3M3 9a3 3 0 0 1 3-3m-5 14v-3a5 5 0 0 1 3-4M21 9a3 3 0 0 0-3-3m5 14v-3a5 5 0 0 0-3-4",
  store:
    "M4 10v11h16V10M3 3h18l1 7a3 3 0 0 1-5 2 3 3 0 0 1-5 0 3 3 0 0 1-5 0 3 3 0 0 1-5-2ZM9 21v-6h6v6",
  arrow: "m9 5 7 7-7 7",
  check: "m5 12 4 4L19 6",
  plus: "M12 5v14M5 12h14",
};
</script>
<template>
  <svg
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="1.8"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
    class="app-icon"
  >
    <path :d="paths[name] || paths.dish" />
  </svg>
</template>
