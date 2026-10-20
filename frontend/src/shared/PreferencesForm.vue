<script setup lang="ts">
import { ref, computed } from "vue";
import type { Preferences, MenuSnapshot } from "./contracts";
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
const props = defineProps<{
  defaultsOnly?: boolean;
  menu?: MenuSnapshot;
  menuLink?: string;
}>();
const ingredientSearch = ref("");
const showAllIngredients = ref(false);
const shownIngredients = computed(() =>
  showAllIngredients.value || ingredientSearch.value
    ? ingredients.value
    : ingredients.value.slice(0, 12),
);
const selectedDishes = computed(
  () =>
    props.menu?.dishes.filter((d) =>
      prefs.value.wantedDishIds.includes(d.id),
    ) ?? [],
);
const selectedMeals = computed(
  () =>
    props.menu?.setMeals.filter((d) =>
      prefs.value.wantedSetMealIds.includes(d.id),
    ) ?? [],
);
const allergySummary = computed(() =>
  prefs.value.allergens.length
    ? prefs.value.allergens.join("、")
    : "有食物过敏？",
);
function removeDish(id: string, meal = false) {
  const key = meal ? "wantedSetMealIds" : "wantedDishIds";
  prefs.value = {
    ...prefs.value,
    [key]: prefs.value[key].filter((x) => x !== id),
  };
}
const ingredients = computed(() =>
  [
    ...new Set(
      props.menu?.dishes
        .filter((d) => d.available)
        .flatMap((d) => d.ingredients) ?? [],
    ),
  ]
    .filter(
      (i) =>
        ![
          "unknown",
          "水",
          "盐",
          "食盐",
          "白砂糖",
          "白糖",
          "味精",
          "鸡精",
          "配料包",
          "调料包",
        ].includes(i),
    )
    .filter((i) => i.includes(ingredientSearch.value)),
);
function toggle(
  key: "allergens" | "avoidFoods" | "tastePreferences" | "wantedIngredients",
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
  <div class="preferences preferences-simple">
    <fieldset>
      <legend>食量</legend>
      <select v-model="prefs.appetite" aria-label="食量">
        <option value="small">小</option>
        <option value="normal">正常</option>
        <option value="large">大</option>
        <option value="extraLarge">特别大</option>
      </select>
    </fieldset>
    <fieldset>
      <legend>口味</legend>
      <div class="chips">
        <button
          v-for="v in ['清淡', '咸鲜', '酸甜']"
          :key="v"
          type="button"
          :aria-pressed="prefs.tastePreferences.includes(v)"
          @click="toggle('tastePreferences', v)"
        >
          {{ v }}
        </button>
      </div>
      <select v-model="prefs.maxSpiceLevel" aria-label="接受辣度">
        <option :value="null">辣度都可以</option>
        <option
          v-for="(label, i) in ['不辣', '微辣', '中辣', '重辣']"
          :key="i"
          :value="i"
        >
          {{ i === 0 ? "不吃辣" : "最多" + label }}
        </option>
      </select>
      <div class="chips diet-options">
        <button
          v-for="option in dietOptions"
          :key="option.value"
          type="button"
          :aria-pressed="prefs.dietMode === option.value"
          @click="prefs.dietMode = option.value"
        >
          {{ option.label }}
        </button>
      </div>
    </fieldset>
    <fieldset>
      <legend>想吃</legend>
      <div class="chips">
        <button
          v-for="v in props.defaultsOnly
            ? ['鱼', '鸡肉', '蔬菜', '汤']
            : ['鱼', '鸡肉', '蔬菜', '汤', '面条', '馄饨', '米饭']"
          :key="v"
          type="button"
          :aria-pressed="prefs.tastePreferences.includes(v)"
          @click="toggle('tastePreferences', v)"
        >
          {{ v }}
        </button>
      </div>
      <template v-if="!props.defaultsOnly">
        <div
          v-if="selectedDishes.length || selectedMeals.length"
          class="chips selected-wishes"
        >
          <button
            v-for="d in selectedDishes"
            :key="d.id"
            type="button"
            aria-pressed="true"
            :aria-label="'移除想吃' + d.name"
            @click="removeDish(d.id)"
          >
            {{ d.name }} ×
          </button>
          <button
            v-for="d in selectedMeals"
            :key="d.id"
            type="button"
            aria-pressed="true"
            :aria-label="'移除想吃' + d.name"
            @click="removeDish(d.id, true)"
          >
            {{ d.name }} ×
          </button>
        </div>
        <RouterLink v-if="menuLink" :to="menuLink" class="menu-wish-link"
          >看菜单，选想吃的菜 →</RouterLink
        >
        <details v-if="props.menu" class="ingredient-picker">
          <summary>
            按食材选<span v-if="prefs.wantedIngredients.length">
              · {{ prefs.wantedIngredients.join("、") }}</span
            >
          </summary>
          <div class="chips" v-if="prefs.wantedIngredients.length">
            <button
              v-for="i in prefs.wantedIngredients"
              :key="i"
              type="button"
              aria-pressed="true"
              @click="toggle('wantedIngredients', i)"
            >
              {{ i }} ×
            </button>
          </div>
          <input
            v-model="ingredientSearch"
            aria-label="搜索本店食材"
            placeholder="搜索食材"
          />
          <div class="chips ingredient-options">
            <button
              v-for="i in shownIngredients"
              :key="i"
              type="button"
              :aria-pressed="prefs.wantedIngredients.includes(i)"
              @click="toggle('wantedIngredients', i)"
            >
              {{ i }}
            </button>
          </div>
          <button
            v-if="ingredients.length > 12 && !ingredientSearch"
            class="preference-more"
            type="button"
            @click="showAllIngredients = !showAllIngredients"
          >
            {{ showAllIngredients ? "收起" : "更多食材" }}
          </button>
        </details>
      </template>
    </fieldset>
    <fieldset>
      <legend>不吃</legend>
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

    <details class="allergy-picker" :open="prefs.allergens.length > 0">
      <summary>
        过敏<span class="allergy-summary">{{ allergySummary }}</span>
      </summary>
      <fieldset class="allergen-field">
        <legend>
          过敏<span v-if="prefs.allergens.length">
            · 已选{{ prefs.allergens.length }}项</span
          >
        </legend>
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
      </fieldset>
    </details>
    <label v-if="!props.defaultsOnly" class="preference-note"
      >还有想说的？<textarea
        v-model="prefs.note"
        maxlength="200"
        placeholder="例如：今天不吃米饭，想来一道鱼。"
      />
    </label>
  </div>
</template>
