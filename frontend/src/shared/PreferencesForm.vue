<script setup lang="ts">
import { ref } from "vue";
import type { Preferences } from "./contracts";
const prefs = defineModel<Preferences>({ required: true });
const otherAvoid = ref(""),
  otherAllergen = ref("");
function add(key: "avoidFoods" | "allergens") {
  const source = key === "avoidFoods" ? otherAvoid : otherAllergen;
  const value = source.value.trim();
  if (value && !prefs.value[key].includes(value))
    prefs.value = { ...prefs.value, [key]: [...prefs.value[key], value] };
  source.value = "";
}
const dietOptions = [
  { value: "none", label: "无特殊要求" },
  { value: "ovoLacto", label: "蛋奶素" },
  { value: "plant", label: "纯植物" },
];
const props = defineProps<{ defaultsOnly?: boolean }>();
function toggle(
  key: "allergens" | "avoidFoods" | "tastePreferences",
  value: string,
) {
  const values = prefs.value[key];
  prefs.value = {
    ...prefs.value,
    [key]: values.includes(value)
      ? values.filter((v) => v !== value)
      : [...values, value],
  };
}
</script>
<template>
  <div class="preferences">
    <fieldset>
      <legend>饮食方式</legend>
      <label v-for="option in dietOptions" :key="option.value" class="choice"
        ><input v-model="prefs.dietMode" type="radio" :value="option.value" />{{
          option.label
        }}</label
      >
    </fieldset>
    <fieldset>
      <legend>接受辣度</legend>
      <select v-model="prefs.maxSpiceLevel" aria-label="接受辣度">
        <option :value="null">都可以</option>
        <option
          v-for="(label, i) in ['不辣', '微辣', '中辣', '重辣']"
          :key="i"
          :value="i"
        >
          最高{{ label }}
        </option>
      </select>
    </fieldset>
    <fieldset>
      <legend>明确不吃</legend>
      <div class="chips">
        <button
          v-for="value in ['香菜', '葱', '蒜', '羊肉', '牛肉', '猪肉', '内脏']"
          :key="value"
          type="button"
          :aria-pressed="prefs.avoidFoods.includes(value)"
          @click="toggle('avoidFoods', value)"
        >
          {{ value }}
        </button>
      </div>
      <div class="row">
        <input
          v-model="otherAvoid"
          aria-label="其他不吃的食物"
          placeholder="其他不吃的食物（可选）"
          maxlength="50"
        /><button type="button" @click="add('avoidFoods')">添加</button>
      </div>
      <div class="chips">
        <button
          v-for="value in prefs.avoidFoods.filter(
            (v) =>
              !['香菜', '葱', '蒜', '羊肉', '牛肉', '猪肉', '内脏'].includes(v),
          )"
          :key="value"
          type="button"
          aria-pressed="true"
          @click="toggle('avoidFoods', value)"
        >
          {{ value }} ×
        </button>
      </div>
    </fieldset>
    <details>
      <summary>
        食物过敏（单独记录）<span v-if="prefs.allergens.length">
          · 已选{{ prefs.allergens.length }}项</span
        >
      </summary>
      <div class="chips">
        <button
          v-for="value in [
            '花生',
            '鱼',
            '虾蟹',
            '贝类',
            '鸡蛋',
            '奶',
            '大豆',
            '小麦',
            '芝麻',
          ]"
          :key="value"
          type="button"
          :aria-pressed="prefs.allergens.includes(value)"
          @click="toggle('allergens', value)"
        >
          {{ value }}
        </button>
      </div>
      <div class="row">
        <input
          v-model="otherAllergen"
          aria-label="其他过敏食物"
          placeholder="其他过敏食物（可选）"
          maxlength="50"
        /><button type="button" @click="add('allergens')">添加</button>
      </div>
      <div class="chips">
        <button
          v-for="value in prefs.allergens.filter(
            (v) =>
              ![
                '花生',
                '鱼',
                '虾蟹',
                '贝类',
                '鸡蛋',
                '奶',
                '大豆',
                '小麦',
                '芝麻',
              ].includes(v),
          )"
          :key="value"
          type="button"
          aria-pressed="true"
          @click="toggle('allergens', value)"
        >
          {{ value }} ×
        </button>
      </div>
      <p class="hint">已提交的过敏项用于全桌食材过滤。</p>
    </details>
    <fieldset>
      <legend>口味偏好</legend>
      <div class="chips">
        <button
          v-for="value in ['清淡', '咸鲜', '酸甜', '鱼', '鸡肉', '蔬菜', '汤']"
          :key="value"
          type="button"
          :aria-pressed="prefs.tastePreferences.includes(value)"
          @click="toggle('tastePreferences', value)"
        >
          {{ value }}
        </button>
      </div>
    </fieldset>
    <template v-if="!props.defaultsOnly"
      ><label
        >还有想说的？<textarea
          v-model="prefs.note"
          maxlength="200"
          placeholder="例如：今天想吃清淡一点，可到菜单标记具体菜。"
        />
      </label>
      <p class="hint">
        {{ Array.from(prefs.note).length }} / 200字 · 文字不会覆盖已选限制
      </p></template
    >
  </div>
</template>
