<script setup lang="ts">
const props = defineProps<{
  quantity: number;
  name: string;
  increaseDisabled?: boolean;
}>();
const emit = defineEmits<{ change: [quantity: number] }>();
function input(event: Event) {
  const value = Number((event.target as HTMLInputElement).value);
  if (Number.isInteger(value) && value >= 0 && value <= 100)
    emit("change", value);
  else (event.target as HTMLInputElement).value = String(props.quantity);
}
</script>
<template>
  <div class="quantity-control">
    <button
      type="button"
      :aria-label="'减少' + name"
      :disabled="quantity === 0"
      @click="emit('change', quantity - 1)"
    >
      −</button
    ><input
      type="number"
      min="0"
      max="100"
      :aria-label="name + '份数'"
      :value="quantity"
      @change="input"
    /><button
      type="button"
      :aria-label="'增加' + name"
      :disabled="increaseDisabled || quantity >= 100"
      @click="emit('change', quantity + 1)"
    >
      ＋
    </button>
  </div>
</template>
