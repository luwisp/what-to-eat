<script setup lang="ts">
import { ref, watch, nextTick, onBeforeUnmount } from "vue";
const open = defineModel<boolean>({ required: true });
defineProps<{ title: string; wide?: boolean }>();
const dialog = ref<HTMLDialogElement>();
watch(
  open,
  async (value) => {
    await nextTick();
    if (value && !dialog.value?.open) dialog.value?.showModal();
    else if (!value) dialog.value?.close();
  },
  { immediate: true },
);
onBeforeUnmount(() => dialog.value?.close());
</script>
<template>
  <Teleport to="body">
    <dialog
      ref="dialog"
      class="modal-shell"
      :class="{ 'modal-wide': wide }"
      :aria-label="title"
      @cancel.prevent="open = false"
      @click="
        (e) => {
          if (e.target === dialog) open = false;
        }
      "
    >
      <header class="modal-heading">
        <h2>{{ title }}</h2>
        <button
          type="button"
          :aria-label="'关闭' + title"
          @click="open = false"
        >
          ×
        </button>
      </header>
      <slot v-if="open" />
    </dialog>
  </Teleport>
</template>
