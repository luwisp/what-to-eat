<script setup lang="ts">
import { ref, onMounted, computed } from "vue";
import AppIcon from "../../shared/AppIcon.vue";
import ImageUpload from "../../shared/ImageUpload.vue";
import ModalSheet from "../../shared/ModalSheet.vue";
import QRCode from "qrcode";
import type {
  AccountView,
  Restaurant,
  RestaurantEntry,
  MenuSnapshot,
  Dish,
  DishInput,
  SetMeal,
  SetMealInput,
} from "../../shared/contracts";
import {
  api,
  loadAccount,
  getMenu,
  money,
  priceFen,
  copyJson,
} from "../../shared/api";
const account = ref<AccountView | null>(null),
  login = ref(""),
  password = ref(""),
  registering = ref(false),
  error = ref(""),
  notice = ref(""),
  restaurant = ref<Restaurant>(),
  entry = ref<RestaurantEntry>(),
  menu = ref<MenuSnapshot>(),
  name = ref(""),
  description = ref(""),
  qr = ref(""),
  busy = ref(false),
  tab = ref("dishes");
const dishEmpty = (): DishInput => ({
  name: "",
  description: "",
  taste: "",
  cookingMethod: "",
  priceFen: 0,
  imageUrl: "",
  category: "hot",
  ingredients: [],
  spiceLevel: 0,
  available: true,
  isSignature: false,
});
const dish = ref<DishInput>(dishEmpty()),
  dishId = ref(""),
  dishPrice = ref(""),
  ingredientText = ref(""),
  unknown = ref(false),
  showDish = ref(false),
  imageBusy = ref(false),
  singleServing = ref(true),
  primaryText = ref(""),
  vegetable = ref(false);
const meal = ref<SetMealInput>({
    name: "",
    imageUrl: "",
    components: [],
    priceFen: 0,
  }),
  mealId = ref(""),
  mealPrice = ref(""),
  showMeal = ref(false);
const category = ref("all"),
  search = ref("");
const categoryLabels: Record<string, string> = {
  all: "全部",
  cold: "凉菜",
  hot: "热菜",
  soup: "汤",
  staple: "主食",
  side: "小吃",
  drink: "饮品",
};
const catalog = computed(
  () =>
    menu.value?.dishes.filter(
      (d) =>
        (category.value === "all" || d.category === category.value) &&
        [d.name, d.description, ...d.ingredients].some((v) =>
          v.includes(search.value.trim()),
        ),
    ) ?? [],
);
async function refresh() {
  account.value = await loadAccount("merchant");
  if (!account.value) return;
  try {
    const own = await api<{ restaurant: Restaurant; entry: RestaurantEntry }>(
      "/api/merchant/restaurant",
    );
    restaurant.value = own.restaurant;
    entry.value = own.entry;
    name.value = own.restaurant.name;
    description.value = own.restaurant.description;
    menu.value = await getMenu(own.restaurant.restaurantCode);
    qr.value = await QRCode.toDataURL(own.entry.link, {
      width: 280,
      margin: 1,
    });
  } catch (e) {
    if ((e as { status?: number }).status !== 404) throw e;
  }
}
onMounted(() =>
  refresh().catch((e) => {
    error.value = (e as Error).message;
  }),
);
async function action(work: () => Promise<void>) {
  busy.value = true;
  error.value = "";
  notice.value = "";
  try {
    await work();
  } catch (e) {
    error.value = (e as Error).message;
  } finally {
    busy.value = false;
  }
}
async function authenticate() {
  await action(async () => {
    if (registering.value) {
      await api("/api/merchant/register", "POST", {
        login: login.value,
        password: password.value,
      });
      registering.value = false;
      notice.value = "注册成功，请登录";
      password.value = "";
      return;
    }
    await api("/api/merchant/login", "POST", {
      login: login.value,
      password: password.value,
    });
    password.value = "";
    await refresh();
  });
}
async function saveRestaurant() {
  await action(async () => {
    await api("/api/merchant/restaurant", restaurant.value ? "PUT" : "POST", {
      name: name.value,
      description: description.value,
    });
    await refresh();
    notice.value = "餐馆资料已保存";
  });
}
function editDish(value?: Dish) {
  imageBusy.value = false;
  const fact = menu.value?.mealMetadata?.find((f) => f.dishId === value?.id);
  singleServing.value = fact?.stapleUnits === 1 || !value;
  primaryText.value = fact?.primaryIngredients.join("、") ?? "";
  vegetable.value = fact?.vegetable ?? false;
  dishId.value = value?.id ?? "";
  dish.value = value ? copyJson(value) : dishEmpty();
  if (fact?.role === "side") dish.value.category = "side";
  dishPrice.value = value ? String(value.priceFen / 100) : "";
  ingredientText.value =
    value?.ingredients.filter((i) => i !== "unknown").join("、") ?? "";
  unknown.value = value?.ingredients.includes("unknown") ?? false;
  showDish.value = true;
}
async function saveDish() {
  await action(async () => {
    const ingredients = ingredientText.value
      .split(/[、,，;；\n]/)
      .map((s) => s.trim())
      .filter(Boolean);
    if (unknown.value || !ingredients.length) ingredients.push("unknown");
    const payload = {
      ...dish.value,
      mealRole:
        ({ hot: "hotMain", cold: "coldMain" } as Record<string, string>)[
          dish.value.category
        ] ?? dish.value.category,
      singleServing: singleServing.value,
      primaryIngredients: primaryText.value
        .split(/[、,，]/)
        .map((s) => s.trim())
        .filter(Boolean),
      vegetable: vegetable.value,
      priceFen: priceFen(dishPrice.value),
      ingredients,
    };
    await api(
      "/api/merchant/dishes" +
        (dishId.value ? "/" + encodeURIComponent(dishId.value) : ""),
      dishId.value ? "PUT" : "POST",
      payload,
    );
    showDish.value = false;
    await refresh();
    notice.value = "菜品已保存";
  });
}
function editMeal(value?: SetMeal) {
  imageBusy.value = false;
  mealId.value = value?.id ?? "";
  meal.value = value
    ? copyJson(value)
    : { name: "", imageUrl: "", components: [], priceFen: 0 };
  mealPrice.value = value ? String(value.priceFen / 100) : "";
  showMeal.value = true;
}
async function saveMeal() {
  await action(async () => {
    if (
      !meal.value.components.length ||
      meal.value.components.some(
        (c) => !c.dishId || !Number.isInteger(c.quantity) || c.quantity <= 0,
      )
    )
      throw new Error("请选择套餐组分，份数须为正整数");
    await api(
      "/api/merchant/set-meals" +
        (mealId.value ? "/" + encodeURIComponent(mealId.value) : ""),
      mealId.value ? "PUT" : "POST",
      { ...meal.value, priceFen: priceFen(mealPrice.value) },
    );
    showMeal.value = false;
    await refresh();
    notice.value = "套餐已保存";
  });
}
async function remove(kind: "dishes" | "set-meals", id: string) {
  await action(async () => {
    await api(`/api/merchant/${kind}/${encodeURIComponent(id)}`, "DELETE");
    await refresh();
    notice.value = "已删除";
  });
}
async function logout() {
  await action(async () => {
    await api("/api/merchant/logout", "POST");
    account.value = null;
    restaurant.value = undefined;
    menu.value = undefined;
  });
}
</script>
<template>
  <div class="merchant-app">
    <header class="app-header">
      <a href="/admin/" class="brand"
        >聚小宝 · 餐馆工作台<span>JUXIAOBAO</span></a
      >
      <div class="row">
        <a href="/">用户端</a
        ><button v-if="account" @click="logout">退出商家账号</button>
      </div>
    </header>
    <main class="merchant-workspace">
      <p v-if="error && !showDish && !showMeal" class="error" role="alert">
        {{ error }}
      </p>
      <p v-if="notice" class="notice" role="status">{{ notice }}</p>
      <form v-if="!account" class="card narrow" @submit.prevent="authenticate">
        <h1>{{ registering ? "商家注册" : "商家登录" }}</h1>
        <p v-if="registering" class="hint">
          账号不能含空格；密码至少8字节，建议使用8位以上英文或数字。
        </p>
        <label
          >账号<input v-model="login" autocomplete="username" required /></label
        ><label
          >密码<input
            v-model="password"
            type="password"
            :autocomplete="registering ? 'new-password' : 'current-password'"
            :placeholder="registering ? '建议至少8位英文或数字' : '请输入密码'"
            required
        /></label>
        <div class="row">
          <button class="primary" :disabled="busy">
            {{ registering ? "注册" : "登录" }}</button
          ><button type="button" @click="registering = !registering">
            {{ registering ? "返回登录" : "注册商家账号" }}
          </button>
        </div>
      </form>
      <template v-else
        ><h1>{{ restaurant?.name ?? "创建你的餐馆" }}</h1>
        <details class="merchant-profile" :open="!restaurant">
          <summary>餐馆资料</summary>
          <form class="card" @submit.prevent="saveRestaurant">
            <label>餐馆名称<input v-model="name" required /></label
            ><label>简介<textarea v-model="description" /></label
            ><button class="primary" :disabled="busy">保存餐馆资料</button>
          </form>
        </details>
        <section v-if="restaurant">
          <nav class="chips">
            <button
              v-for="[value, label] in [
                ['dishes', '菜品'],
                ['meals', '固定套餐'],
                ['entry', '餐馆入口'],
              ]"
              :key="value"
              :aria-pressed="tab === value"
              @click="tab = value"
            >
              {{ label }}
            </button>
          </nav>
          <section v-if="tab === 'dishes'" class="merchant-catalog">
            <div class="catalog-toolbar">
              <div>
                <h2>本店菜单</h2>
                <span
                  >{{ menu?.dishes.length ?? 0 }} 道菜 ·
                  {{ menu?.dishes.filter((d) => d.available).length ?? 0 }}
                  道可售</span
                >
              </div>
              <input
                v-model="search"
                type="search"
                aria-label="搜索菜品"
                placeholder="搜索菜名或食材"
              /><button class="primary" @click="editDish()">＋ 新增菜品</button>
            </div>
            <div class="menu-layout">
              <nav class="category-rail" aria-label="菜品分类">
                <button
                  v-for="(label, value) in categoryLabels"
                  :key="value"
                  :aria-pressed="category === value"
                  @click="category = value"
                >
                  {{ label }}
                </button>
              </nav>
              <div class="menu-items">
                <div class="merchant-dish-grid">
                  <article
                    v-for="d in catalog"
                    :key="d.id"
                    class="menu-dish"
                    :class="{ unavailable: !d.available }"
                  >
                    <img
                      v-if="d.imageUrl"
                      :src="d.imageUrl"
                      :alt="d.name"
                      class="dish-thumb"
                      loading="lazy"
                    />
                    <div v-else class="dish-thumb dish-placeholder">
                      <AppIcon name="dish" :size="36" />
                    </div>
                    <div class="dish-info">
                      <div class="merchant-dish-title">
                        <h2>{{ d.name }}</h2>
                        <span
                          :class="['availability-tag', { off: !d.available }]"
                          >{{ d.available ? "可售" : "已下架" }}</span
                        >
                      </div>
                      <p v-if="d.description" class="dish-description">
                        {{ d.description }}
                      </p>
                      <div class="dish-tags">
                        <span v-if="d.isSignature" class="signature">招牌</span
                        ><span>{{
                          ["不辣", "微辣", "中辣", "重辣"][d.spiceLevel]
                        }}</span
                        ><span v-if="d.taste">{{ d.taste }}</span
                        ><span v-if="d.cookingMethod">{{
                          d.cookingMethod
                        }}</span>
                      </div>
                      <p class="ingredient-note">
                        {{
                          d.ingredients
                            .filter((i) => i !== "unknown")
                            .join("、")
                        }}<span v-if="d.ingredients.includes('unknown')">
                          · 其余食材不详</span
                        >
                      </p>
                      <div class="dish-bottom">
                        <strong class="price">{{ money(d.priceFen) }}</strong>
                        <div class="merchant-item-actions">
                          <button
                            :aria-label="'编辑 ' + d.name"
                            @click="editDish(d)"
                          >
                            编辑</button
                          ><button
                            :aria-label="'删除 ' + d.name"
                            @click="remove('dishes', d.id)"
                          >
                            <AppIcon name="trash" :size="16" />
                          </button>
                        </div>
                      </div>
                    </div>
                  </article>
                </div>
                <div v-if="!catalog.length" class="empty-category">
                  {{
                    search
                      ? "没有匹配的菜，换个词试试"
                      : "还没有菜品，添加第一道菜吧"
                  }}
                </div>
              </div>
            </div>
          </section>
          <template v-if="tab === 'meals'"
            ><button class="primary" @click="editMeal()">新增套餐</button>
            <div class="grid">
              <article class="card" v-for="m in menu?.setMeals" :key="m.id">
                <h2>{{ m.name }}</h2>
                <p>{{ money(m.priceFen) }} / 套</p>
                <p v-for="c in m.components" :key="c.dishId">
                  {{ menu?.dishes.find((d) => d.id === c.dishId)?.name }} ×
                  {{ c.quantity }}
                </p>
                <button @click="editMeal(m)">编辑套餐</button>
                <button @click="remove('set-meals', m.id)">删除套餐</button>
              </article>
            </div></template
          >
          <article v-if="tab === 'entry' && entry" class="card narrow">
            <h2>让客人扫码进店</h2>
            <p>
              餐馆码：<strong>{{ entry.restaurantCode }}</strong>
            </p>
            <a :href="entry.link">{{ entry.link }}</a
            ><img v-if="qr" :src="qr" class="qr" alt="餐馆入口二维码" /><a
              class="button"
              :href="qr"
              :download="`${entry.restaurantCode}.png`"
              >保存二维码</a
            >
            <p class="hint">此码进入餐馆；用餐时的邀请二维码由聚餐局生成。</p>
          </article>
          <ModalSheet
            v-model="showDish"
            :title="dishId ? '编辑菜品' : '新增菜品'"
            wide
            ><form class="merchant-editor" @submit.prevent="saveDish">
              <p v-if="error" class="error" role="alert">{{ error }}</p>
              <label v-if="dish.category === 'staple'" class="choice"
                ><input
                  v-model="singleServing"
                  type="checkbox"
                />已核对：这一份可作为一人的主食</label
              ><label
                >主料（可选，须出现在食材列表中）<input
                  v-model="primaryText"
                  placeholder="用顿号分隔" /></label
              ><label class="choice"
                ><input
                  v-model="vegetable"
                  type="checkbox"
                />蔬菜类正餐菜</label
              >

              <div class="grid">
                <label>名称<input v-model="dish.name" required /></label
                ><label
                  >当前价格（元）<input
                    v-model="dishPrice"
                    inputmode="decimal"
                    required /></label
                ><label>简介<textarea v-model="dish.description" /></label
                ><ImageUpload
                  v-model="dish.imageUrl"
                  label="菜品图片"
                  @uploading="imageBusy = $event"
                /><label
                  >口味<input
                    v-model="dish.taste"
                    placeholder="如清淡、咸鲜" /></label
                ><label
                  >烹饪方式<input
                    v-model="dish.cookingMethod"
                    placeholder="如蒸、炒、炖" /></label
                ><label
                  >分类<select v-model="dish.category">
                    <option
                      v-for="[value, label] in [
                        ['cold', '凉菜'],
                        ['hot', '热菜'],
                        ['soup', '汤'],
                        ['staple', '主食'],
                        ['side', '小吃'],
                        ['drink', '饮品'],
                      ]"
                      :key="value"
                      :value="value"
                    >
                      {{ label }}
                    </option>
                  </select></label
                ><label
                  >辣度<select v-model="dish.spiceLevel">
                    <option
                      v-for="(label, i) in ['不辣', '微辣', '中辣', '重辣']"
                      :key="i"
                      :value="i"
                    >
                      {{ label }}
                    </option>
                  </select></label
                >
              </div>
              <label
                >食材（含调料、汤底，用顿号或逗号分隔）<textarea
                  v-model="ingredientText"
                /></label
              ><label class="choice"
                ><input v-model="unknown" type="checkbox" />仍有不明食材</label
              >
              <p class="hint">
                已知食材会保留；没有已知食材时保存为“食材不详”。
              </p>
              <label class="choice"
                ><input
                  v-model="dish.available"
                  type="checkbox"
                />当前可售</label
              ><label class="choice"
                ><input
                  v-model="dish.isSignature"
                  type="checkbox"
                />招牌菜</label
              >
              <div class="row">
                <button type="button" @click="showDish = false">取消编辑</button
                ><button class="primary" :disabled="busy || imageBusy">
                  保存菜品
                </button>
              </div>
            </form></ModalSheet
          >
          <ModalSheet
            v-model="showMeal"
            :title="mealId ? '编辑套餐' : '新增套餐'"
            wide
            ><form class="merchant-editor" @submit.prevent="saveMeal">
              <p v-if="error" class="error" role="alert">{{ error }}</p>

              <label>套餐名字<input v-model="meal.name" required /></label
              ><ImageUpload
                v-model="meal.imageUrl"
                label="套餐图片"
                @uploading="imageBusy = $event"
              /><label
                >套餐价格（元）<input
                  v-model="mealPrice"
                  inputmode="decimal"
                  required
              /></label>
              <div
                v-for="(component, i) in meal.components"
                :key="i"
                class="row"
              >
                <label
                  >组分菜品<select v-model="component.dishId">
                    <option value="">选择本店菜品</option>
                    <option v-for="d in menu?.dishes" :key="d.id" :value="d.id">
                      {{ d.name }}{{ d.available ? "" : "（已下架）" }}
                    </option>
                  </select></label
                ><label
                  >份数<input
                    v-model.number="component.quantity"
                    type="number"
                    min="1"
                    step="1"
                    required /></label
                ><button type="button" @click="meal.components.splice(i, 1)">
                  移除组分
                </button>
              </div>
              <button
                type="button"
                @click="meal.components.push({ dishId: '', quantity: 1 })"
              >
                添加套餐组分
              </button>
              <div class="row">
                <button type="button" @click="showMeal = false">取消编辑</button
                ><button class="primary" :disabled="busy || imageBusy">
                  保存套餐
                </button>
              </div>
            </form></ModalSheet
          >
        </section></template
      >
    </main>
  </div>
</template>
