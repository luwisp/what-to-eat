<script setup lang="ts">
import { ref, onBeforeUnmount } from "vue";
import { api } from "./api";
import AppIcon from "./AppIcon.vue";
const imageUrl = defineModel<string>({ required: true });
const props = withDefaults(defineProps<{ label?: string }>(), {
  label: "菜品图片",
});
const emit = defineEmits<{ uploading: [value: boolean] }>();
let active = true;
onBeforeUnmount(() => {
  active = false;
  emit("uploading", false);
});
const busy = ref(false),
  error = ref("");
async function upload(file?: File) {
  if (!file || busy.value) return;
  error.value = "";
  if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
    error.value = "请选择JPG、PNG或WebP图片";
    return;
  }
  if (file.size > 10 * 1024 * 1024) {
    error.value = "请选择10MB以内的图片";
    return;
  }
  busy.value = true;
  emit("uploading", true);
  let bitmap: ImageBitmap | undefined;
  try {
    bitmap = await createImageBitmap(file);
    const ratio = Math.min(1, 1600 / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * ratio));
    canvas.height = Math.max(1, Math.round(bitmap.height * ratio));
    const context = canvas.getContext("2d");
    if (!context) throw new Error("无法读取图片，请换一张重试");
    context.fillStyle = "#fff";
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    const data = canvas.toDataURL("image/jpeg", 0.85).split(",")[1];
    if (!data || data.length > 2800000)
      throw new Error("图片内容较大，请缩小后重试");
    const result = await api<{ imageUrl: string }>(
      "/api/merchant/images",
      "POST",
      { data },
    );
    if (active) imageUrl.value = result.imageUrl;
  } catch (e) {
    error.value =
      e instanceof Error ? e.message : "上传失败，请换一张有效图片重试";
  } finally {
    bitmap?.close();
    busy.value = false;
    if (active) emit("uploading", false);
  }
}
function choose(event: Event) {
  const input = event.target as HTMLInputElement;
  void upload(input.files?.[0]);
  input.value = "";
}
</script>
<template>
  <div class="image-upload">
    <span class="image-upload-label">{{ props.label }}</span>
    <label
      class="image-upload-box"
      :class="{ uploading: busy }"
      @dragover.prevent
      @drop.prevent="upload($event.dataTransfer?.files[0])"
    >
      <img v-if="imageUrl" :src="imageUrl" :alt="props.label + '预览'" />
      <AppIcon v-else name="image" :size="28" />
      <span>{{
        busy ? "正在上传…" : imageUrl ? "更换图片" : "点击或拖入图片"
      }}</span>
      <input
        type="file"
        accept="image/jpeg,image/png,image/webp"
        :aria-label="'上传' + props.label"
        :disabled="busy"
        @change="choose"
      />
    </label>
    <small>JPG、PNG、WebP，自动压缩</small>
    <button
      v-if="imageUrl"
      type="button"
      class="image-remove"
      :disabled="busy"
      @click="imageUrl = ''"
    >
      移除图片
    </button>
    <p v-if="error" class="error" role="alert">{{ error }}</p>
  </div>
</template>
