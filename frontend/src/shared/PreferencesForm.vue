<script setup lang="ts">
import { ref, computed, nextTick } from "vue";
import type { Preferences, MenuSnapshot } from "./contracts";
const prefs = defineModel<Preferences>({ required: true });
const otherAvoid = ref(""),
  otherAllergen = ref(""),
  otherUsual = ref("");
const emit = defineEmits<{ selectMenu: [] }>();
function addUsual() {
  const value = otherUsual.value.trim();
  if (value && !prefs.value.tastePreferences.includes(value))
    prefs.value = {
      ...prefs.value,
      tastePreferences: [...prefs.value.tastePreferences, value],
    };
  otherUsual.value = "";
  addingUsual.value = false;
}
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
  menuPicker?: boolean;
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

const appetiteValues = ["small", "normal", "large", "extraLarge"];
const appetiteLabels = ["小", "正常", "大", "特别大"];
const appetiteIndex = computed({
  get: () => Math.max(0, appetiteValues.indexOf(prefs.value.appetite)),
  set: (v: number) => {
    prefs.value.appetite = appetiteValues[v] ?? "normal";
  },
});
const spiceLabels = ["不吃辣", "微辣", "中辣", "重辣", "都可以"];
const spiceIndex = computed({
  get: () => prefs.value.maxSpiceLevel ?? 4,
  set: (v: number) => {
    prefs.value.maxSpiceLevel = v === 4 ? null : v;
  },
});
const usualOptions = ["鱼", "鸡肉", "蔬菜", "汤"];
const customUsual = computed(() =>
  prefs.value.tastePreferences.filter(
    (v) => ![...usualOptions, "清淡", "咸鲜", "酸甜"].includes(v),
  ),
);
const addingUsual = ref(false);
const usualInput = ref<HTMLInputElement>();
async function showUsual() {
  addingUsual.value = true;
  await nextTick();
  usualInput.value?.focus();
}
const addingAvoid = ref(false),
  addingAllergen = ref(false);
const avoidInput = ref<HTMLInputElement>(),
  allergenInput = ref<HTMLInputElement>();
async function showAdd(allergy = false) {
  if (allergy) addingAllergen.value = true;
  else addingAvoid.value = true;
  await nextTick();
  (allergy ? allergenInput : avoidInput).value?.focus();
}
const avoidOptions = ["香菜", "葱", "蒜", "羊肉", "牛肉", "猪肉", "内脏"];
const allergenOptions = [
  "花生",
  "鱼",
  "虾蟹",
  "贝类",
  "鸡蛋",
  "奶",
  "大豆",
  "小麦",
  "芝麻",
];
</script>
<template>
  <div class="preferences preferences-compact">
    <div class="preference-range">
      <div class="preference-label">
        <span>食量</span
        ><span class="range-value">{{ appetiteLabels[appetiteIndex] }}</span>
      </div>
      <input
        v-model.number="appetiteIndex"
        type="range"
        min="0"
        max="3"
        step="1"
        aria-label="食量"
        :aria-valuetext="appetiteLabels[appetiteIndex]"
        :style="{ '--range-fill': (appetiteIndex / 3) * 100 + '%' }"
      />
      <div class="range-labels">
        <span v-for="v in appetiteLabels" :key="v">{{ v }}</span>
      </div>
    </div>
    <div class="preference-range">
      <div class="preference-label">
        <span>能吃多辣</span
        ><span class="range-value">{{ spiceLabels[spiceIndex] }}</span>
      </div>
      <input
        v-model.number="spiceIndex"
        type="range"
        min="0"
        max="4"
        step="1"
        aria-label="接受辣度"
        :aria-valuetext="spiceLabels[spiceIndex]"
        :style="{ '--range-fill': (spiceIndex / 4) * 100 + '%' }"
      />
      <div class="range-labels">
        <span v-for="v in spiceLabels" :key="v">{{ v }}</span>
      </div>
    </div>
    <div class="preference-inline">
      <span class="preference-label">口味</span>
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
        <select v-model="prefs.dietMode" aria-label="饮食方式">
          <option
            v-for="option in dietOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
      </div>
    </div>
    <div class="preference-block">
      <span class="preference-label">{{
        props.defaultsOnly ? "常吃" : "想吃"
      }}</span>
      <div class="chips wish-options">
        <button
          v-for="v in props.defaultsOnly
            ? [...usualOptions, ...customUsual]
            : [
                ...new Set([
                  '鱼',
                  '鸡肉',
                  '蔬菜',
                  '汤',
                  '面条',
                  '馄饨',
                  '米饭',
                  ...customUsual,
                ]),
              ]"
          :key="v"
          type="button"
          :aria-pressed="prefs.tastePreferences.includes(v)"
          @click="toggle('tastePreferences', v)"
        >
          {{ v }}
        </button>
        <template v-if="props.defaultsOnly">
          <form
            v-if="addingUsual"
            class="inline-add"
            @submit.prevent="addUsual"
          >
            <input
              ref="usualInput"
              v-model="otherUsual"
              aria-label="其他常吃的食物"
              placeholder="食物名"
              maxlength="50"
            />
            <button type="submit" aria-label="添加常吃的食物">✓</button>
            <button
              type="button"
              aria-label="取消添加常吃的食物"
              @click="addingUsual = false"
            >
              ×
            </button>
          </form>
          <button v-else class="add-chip" type="button" @click="showUsual">
            ＋ 添加常吃
          </button>
        </template>
        <template v-if="!props.defaultsOnly">
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
          <button
            v-if="menuPicker"
            class="add-chip"
            type="button"
            @click="emit('selectMenu')"
          >
            ＋ 菜单选菜
          </button>
          <RouterLink
            v-else-if="menuLink"
            :to="menuLink"
            class="add-chip"
            aria-label="看菜单，选想吃的菜 →"
            >＋ 菜单选菜</RouterLink
          >
        </template>
      </div>
      <details
        v-if="!props.defaultsOnly && props.menu"
        class="ingredient-picker"
      >
        <summary>
          按食材选<span v-if="prefs.wantedIngredients.length">
            · {{ prefs.wantedIngredients.join("、") }}</span
          >
        </summary>
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
        <div
          v-if="
            prefs.wantedIngredients.some((i) => !shownIngredients.includes(i))
          "
          class="chips"
        >
          <button
            v-for="i in prefs.wantedIngredients.filter(
              (i) => !shownIngredients.includes(i),
            )"
            :key="i"
            type="button"
            aria-pressed="true"
            @click="toggle('wantedIngredients', i)"
          >
            {{ i }} ×
          </button>
        </div>
        <button
          v-if="ingredients.length > 12 && !ingredientSearch"
          type="button"
          class="preference-more"
          @click="showAllIngredients = !showAllIngredients"
        >
          {{ showAllIngredients ? "收起" : "更多食材" }}
        </button>
      </details>
    </div>
    <div class="preference-block">
      <span class="preference-label">不吃</span>
      <div class="chips">
        <button
          v-for="v in [
            ...avoidOptions,
            ...prefs.avoidFoods.filter((v) => !avoidOptions.includes(v)),
          ]"
          :key="v"
          type="button"
          :aria-pressed="prefs.avoidFoods.includes(v)"
          @click="toggle('avoidFoods', v)"
        >
          {{ v }}
        </button>
        <form
          v-if="addingAvoid"
          class="inline-add"
          @submit.prevent="
            add('avoidFoods');
            addingAvoid = false;
          "
        >
          <input
            ref="avoidInput"
            v-model="otherAvoid"
            aria-label="其他不吃的食物"
            placeholder="食物名"
            maxlength="50"
          /><button type="submit" aria-label="添加不吃的食物">✓</button
          ><button
            type="button"
            aria-label="取消添加不吃的食物"
            @click="addingAvoid = false"
          >
            ×
          </button>
        </form>
        <button v-else class="add-chip" type="button" @click="showAdd()">
          ＋ 其他
        </button>
      </div>
    </div>
    <details class="allergy-picker" :open="prefs.allergens.length > 0">
      <summary>
        {{
          prefs.allergens.length ? "过敏 · " + allergySummary : "有食物过敏？"
        }}
      </summary>
      <div class="chips">
        <button
          v-for="v in [
            ...allergenOptions,
            ...prefs.allergens.filter((v) => !allergenOptions.includes(v)),
          ]"
          :key="v"
          type="button"
          :aria-pressed="prefs.allergens.includes(v)"
          @click="toggle('allergens', v)"
        >
          {{ v }}
        </button>
        <form
          v-if="addingAllergen"
          class="inline-add"
          @submit.prevent="
            add('allergens');
            addingAllergen = false;
          "
        >
          <input
            ref="allergenInput"
            v-model="otherAllergen"
            aria-label="其他过敏食物"
            placeholder="过敏食物"
            maxlength="50"
          /><button type="submit" aria-label="添加过敏食物">✓</button
          ><button
            type="button"
            aria-label="取消添加过敏食物"
            @click="addingAllergen = false"
          >
            ×
          </button>
        </form>
        <button v-else type="button" class="add-chip" @click="showAdd(true)">
          ＋ 其他过敏
        </button>
      </div>
    </details>
    <textarea
      v-if="!props.defaultsOnly"
      v-model="prefs.note"
      class="preference-note"
      aria-label="还有想说的？"
      maxlength="200"
      placeholder="还有想说的？比如今天想清淡点，大家一起少点一道菜…"
    />
  </div>
</template>
