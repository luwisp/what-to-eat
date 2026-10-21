<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import QRCode from "qrcode";
import type {
  RoomSnapshot,
  Preferences,
  MenuSnapshot,
  RecommendationItem,
} from "../../shared/contracts";
import { api, getMenu, money, priceFen, copyJson } from "../../shared/api";
import { connectRoom, type RoomConnection } from "../../shared/socket";
import {
  loadDraft,
  saveDraft,
  hasDraft,
  emptyPreferences,
  type DraftKey,
} from "../menu/drafts";
import ModalSheet from "../../shared/ModalSheet.vue";
import AppIcon from "../../shared/AppIcon.vue";
import PreferencesForm from "../../shared/PreferencesForm.vue";
const aiEnabled = ref(false);
const route = useRoute(),
  router = useRouter(),
  state = ref<RoomSnapshot>(),
  status = ref("正在连接"),
  error = ref(""),
  notice = ref(""),
  prefs = ref(emptyPreferences()),
  menu = ref<MenuSnapshot>(),
  invite = ref(false),
  qr = ref(""),
  people = ref(4),
  budget = ref(""),
  busy = ref(false),
  companion = ref(false),
  companionId = ref(""),
  companionName = ref(""),
  companionPrefs = ref(emptyPreferences()),
  chatText = ref("");
let connection: RoomConnection | undefined,
  key: DraftKey | undefined,
  initialized = "";
const resultView = computed(() => route.path.endsWith("/result"));
const pendingRecommendation = ref(false),
  copied = ref(false);
const working = computed(
  () => pendingRecommendation.value || !!state.value?.job,
);
const menuLink = computed(() =>
  state.value
    ? `/r/${state.value.restaurantCode}/menu?room=${route.params.code}`
    : "",
);
const editing = computed(() => route.path.endsWith("/preferences"));
const host = computed(
  () => state.value?.self?.id === state.value?.session.hostParticipantId,
);
const submitted = computed(
  () => state.value?.members.filter((p) => p.submitted).length ?? 0,
);
const result = computed(() => state.value?.recommendation);
const editingVersion = ref(0);
const editingResult = ref(false),
  editedItems = ref<RecommendationItem[]>([]),
  addItem = ref("");
function startResultEdit() {
  editingVersion.value = state.value?.stateVersion ?? 0;
  editedItems.value = copyJson(result.value?.draft.items ?? []);
  editingResult.value = true;
}
function appendItem() {
  const d = menu.value?.dishes.find((d) => d.id === addItem.value);
  const m = menu.value?.setMeals.find((m) => m.id === addItem.value);
  if (!d && !m) return;
  const kind = d ? "dish" : "setMeal";
  const existing = editedItems.value.find(
    (i) => i.itemType === kind && i.itemId === addItem.value,
  );
  if (existing) existing.quantity++;
  else
    editedItems.value.push({
      itemType: kind,
      itemId: addItem.value,
      quantity: 1,
      name: (d ?? m)!.name,
      unitPriceFen: (d ?? m)!.priceFen,
    });
  addItem.value = "";
}
function itemDescription(item: RecommendationItem): string {
  if (item.itemType !== "dish") return "";
  return (
    menu.value?.dishes.find((d) => d.id === item.itemId)?.description.trim() ??
    ""
  );
}
async function saveResultEdit() {
  await send("edit_recommendation", {
    expectedVersion: editingVersion.value,
    items: editedItems.value.map((i) => ({
      itemType: i.itemType,
      itemId: i.itemId,
      quantity: Number(i.quantity),
    })),
  });
  if (!error.value) editingResult.value = false;
}
const inviteLink = computed(
  () => location.origin + "/s/" + String(route.params.code),
);
onMounted(() => {
  void api<{ aiEnabled: boolean }>("/api/capabilities")
    .then((c) => (aiEnabled.value = c.aiEnabled))
    .catch(() => {});
  connection = connectRoom(
    String(route.params.code),
    (s) => {
      const wasWorking = working.value;
      state.value = s;
      if (wasWorking && !s.job) {
        pendingRecommendation.value = false;
        if (s.recommendation && !s.recommendationInvalid && !editing.value)
          void router.push(`/s/${route.params.code}/result`);
        else if (!s.recommendation || s.recommendationInvalid)
          error.value = "这次没能完成搭配，请再试一次。";
      }
      people.value = s.session.people;
      budget.value =
        s.session.budgetPerPersonFen === null
          ? ""
          : String(s.session.budgetPerPersonFen / 100);
      if (s.self && initialized !== s.self.id) {
        initialized = s.self.id;
        key = `room:${s.session.roomCode}:${s.self.id}`;
        prefs.value = hasDraft(key) ? loadDraft(key) : copyJson(s.self.draft);
        if (!hasDraft(key) && hasDraft(`restaurant:${s.restaurantCode}`)) {
          const restaurant = loadDraft(`restaurant:${s.restaurantCode}`);
          prefs.value.wantedDishIds = restaurant.wantedDishIds;
          prefs.value.wantedSetMealIds = restaurant.wantedSetMealIds;
        }
        saveDraft(key, prefs.value);
        void getMenu(s.restaurantCode)
          .then((m) => {
            menu.value = m;
          })
          .catch(() => {});
      }
    },
    (s) => {
      status.value = s;
      if (
        ![
          "已连接",
          "正在连接",
          "正在重连",
          "连接断开，正在恢复",
          "服务不可用，正在重试",
        ].includes(s)
      ) {
        pendingRecommendation.value = false;
        error.value = s;
      }
    },
  );
  void QRCode.toDataURL(inviteLink.value, { width: 240, margin: 1 }).then(
    (v) => {
      qr.value = v;
    },
  );
});
onUnmounted(() => connection?.close());
watch(
  () => state.value?.menuVersion,
  () => {
    const s = state.value;
    if (!s) return;
    void getMenu(s.restaurantCode)
      .then((m) => {
        if (m.menuVersion === state.value?.menuVersion) menu.value = m;
      })
      .catch(() => {});
  },
);
watch(
  prefs,
  (v) => {
    if (key) saveDraft(key, v);
  },
  { deep: true },
);
async function send(type: string, payload: Record<string, unknown> = {}) {
  error.value = "";
  busy.value = true;
  try {
    await connection?.send(type, {
      ...payload,
      expectedVersion: payload.expectedVersion ?? state.value?.stateVersion,
    });
  } catch (e) {
    error.value = (e as Error).message;
  } finally {
    busy.value = false;
  }
}
async function save(submit: boolean) {
  notice.value = "";
  const wishes =
    prefs.value.wantedDishIds.length + prefs.value.wantedSetMealIds.length;
  await send("update_preferences", { prefs: copyJson(prefs.value), submit });
  if (!error.value && state.value?.self) {
    prefs.value = copyJson(state.value.self.draft);
    if (
      prefs.value.wantedDishIds.length + prefs.value.wantedSetMealIds.length <
      wishes
    )
      notice.value = "已取消与当前限制冲突或已不可售的愿望；其余要求已保留";
  }
  if (!error.value && submit) void router.push(`/s/${route.params.code}`);
}
async function updateSession() {
  try {
    await send("update_session", {
      people: people.value,
      budgetPerPersonFen: budget.value ? priceFen(budget.value) : null,
    });
  } catch (e) {
    error.value = (e as Error).message;
  }
}
function editCompanion(id = "") {
  const member = state.value?.members.find((m) => m.id === id);
  companionId.value = id;
  companionName.value = member?.nickname ?? "";
  companionPrefs.value = member?.preferences
    ? copyJson(member.preferences)
    : emptyPreferences();
  companion.value = true;
}
async function saveCompanion() {
  await send(companionId.value ? "update_companion" : "add_companion", {
    id: companionId.value,
    prefs: copyJson(companionPrefs.value),
    nickname: companionName.value,
  });
  if (!error.value) companion.value = false;
}
async function copyInvite() {
  try {
    await navigator.clipboard.writeText(inviteLink.value);
    copied.value = true;
  } catch {
    const input = document.querySelector<HTMLInputElement>(
      '[aria-label="邀请链接"]',
    );
    input?.focus();
    input?.select();
  }
}
async function requestRecommendation(adjustment?: string) {
  if (working.value) return;
  pendingRecommendation.value = true;
  await send("request_recommendation", adjustment ? { adjustment } : {});
  if (error.value) pendingRecommendation.value = false;
}
async function reopen() {
  await send("reopen_recommendation");
  if (!error.value) void router.push(`/s/${route.params.code}`);
}
async function sendChat() {
  if (working.value || !chatText.value.trim()) return;
  pendingRecommendation.value = true;
  await send("chat_message", { text: chatText.value.trim() });
  if (error.value) pendingRecommendation.value = false;
  else chatText.value = "";
}
function itemImage(item: RecommendationItem): string {
  return (
    (item.itemType === "dish"
      ? menu.value?.dishes.find((d) => d.id === item.itemId)
      : menu.value?.setMeals.find((d) => d.id === item.itemId)
    )?.imageUrl ?? ""
  );
}
const mine = computed(
  () =>
    result.value?.draft.expandedDishes.filter((d) =>
      result.value?.draft.fits.some(
        (f) =>
          f.dishId === d.dish.id &&
          f.memberId === state.value?.self?.id &&
          f.status === "fit",
      ),
    ) ?? [],
);
</script>
<template>
  <section class="room-page room-flow">
    <header class="room-heading">
      <div>
        <RouterLink
          v-if="editing || resultView"
          class="quiet-link"
          :to="`/s/${route.params.code}`"
          >← 返回这一桌</RouterLink
        >
        <h1>
          {{
            editing
              ? "我的用餐要求"
              : resultView
                ? "这桌这样点"
                : (menu?.restaurant.name ?? "一起吃")
          }}
        </h1>
        <p class="room-caption">
          聚餐码 {{ route.params.code
          }}<span v-if="state"> · {{ state.session.people }} 人</span>
        </p>
      </div>
      <div v-if="!editing" class="room-tools">
        <RouterLink
          v-if="menuLink"
          :to="menuLink"
          class="button"
          aria-label="看菜单"
          >看菜单</RouterLink
        ><button
          @click="
            invite = true;
            copied = false;
          "
          aria-haspopup="dialog"
        >
          邀请同行人
        </button>
      </div>
    </header>
    <p
      v-if="status !== '已连接' && state"
      class="connection-status"
      role="status"
    >
      {{ status }}
    </p>
    <p v-if="error" role="alert" class="error">
      {{ error }} <RouterLink v-if="!state" to="/">回首页重新输入</RouterLink>
    </p>
    <p v-if="notice" role="status" class="notice">{{ notice }}</p>
    <div v-if="working" class="working-panel" role="status" aria-live="polite">
      <span class="working-orbit"><AppIcon name="dish" :size="30" /></span>
      <div>
        <strong>{{
          aiEnabled ? "点菜员正在为这一桌搭配" : "正在搭配这一桌的菜"
        }}</strong>
        <p>
          结合大家的要求，核对菜品、份数和预算<span class="typing-dots"
            ><i></i><i></i><i></i
          ></span>
        </p>
      </div>
    </div>
    <div v-if="editing" class="card preferences-card">
      <PreferencesForm v-model="prefs" :menu="menu" :menu-link="menuLink" />
      <div class="row preferences-actions">
        <button
          :disabled="busy || state?.session.state === 'closed'"
          @click="save(false)"
        >
          只存草稿</button
        ><button
          class="primary"
          :disabled="busy || state?.session.state === 'closed'"
          @click="save(true)"
        >
          {{ busy ? "正在保存…" : "提交本局要求" }}
        </button>
      </div>
    </div>
    <template v-else-if="!resultView && state">
      <p v-if="state.session.state === 'closed'" class="notice">
        本桌已确认，可以查看已搭配的菜。
      </p>
      <section class="card member-card">
        <div class="section-heading">
          <h2>这一桌的人</h2>
          <span>{{ submitted }} / {{ state.session.people }} 人已填写</span>
        </div>
        <ul class="dining-members">
          <li v-for="m in state.members" :key="m.id">
            <span class="member-avatar"
              ><AppIcon
                :name="m.id === state.self?.id ? 'user' : 'group'"
                :size="20"
            /></span>
            <div class="member-copy">
              <strong
                >{{ m.id === state.self?.id ? "我" : m.nickname
                }}<small v-if="m.source === 'companion'">代填</small></strong
              ><span>{{ m.submitted ? "已填写" : "还没填写" }}</span>
            </div>
            <RouterLink
              v-if="m.id === state.self?.id"
              :to="`/s/${route.params.code}/preferences`"
              class="member-edit"
              :aria-label="m.submitted ? '编辑我的要求' : '填写我的要求'"
              >{{ m.submitted ? "编辑" : "填写" }}
              <AppIcon name="arrow" :size="14"
            /></RouterLink>
            <div
              v-else-if="m.filledByParticipantId === state.self?.id"
              class="member-controls"
            >
              <button
                :aria-label="'修改' + m.nickname + '的要求'"
                @click="editCompanion(m.id)"
              >
                编辑</button
              ><button
                :aria-label="'删除' + m.nickname"
                :disabled="busy || state.session.state === 'closed'"
                @click="send('remove_companion', { id: m.id })"
              >
                移除
              </button>
            </div>
          </li>
        </ul>
        <button
          class="add-member"
          @click="editCompanion()"
          :disabled="state.session.state === 'closed'"
        >
          ＋ 帮同行人填写
        </button>
      </section>
      <details v-if="host" class="table-settings card">
        <summary>
          <span
            >{{ state.session.people }} 人用餐 ·
            {{
              state.session.budgetPerPersonFen === null
                ? "预算不限"
                : "人均 " + money(state.session.budgetPerPersonFen)
            }}</span
          ><span class="quiet-link">设置 ⌄</span>
        </summary>
        <form @submit.prevent="updateSession">
          <div class="row">
            <label
              >人数<input
                v-model.number="people"
                type="number"
                :min="state.members.length"
                max="100" /></label
            ><label
              >人均预算（元，可不填）<input
                v-model="budget"
                inputmode="decimal"
            /></label>
          </div>
          <button :disabled="busy || state.session.state === 'closed'">
            保存人数和预算
          </button>
        </form>
      </details>
      <RouterLink
        v-if="result"
        class="existing-result card"
        :to="`/s/${route.params.code}/result`"
        ><AppIcon name="dish" /><span
          ><strong>{{
            state.recommendationInvalid ? "上次方案需要更新" : "看看已搭配的菜"
          }}</strong
          ><small
            >{{ result.draft.items.length }} 项 ·
            {{ money(result.draft.totalFen) }}</small
          ></span
        ><AppIcon name="arrow" :size="18"
      /></RouterLink>
      <div class="lobby-action">
        <button
          v-if="state.session.state !== 'closed'"
          class="primary"
          :disabled="busy || !submitted || working"
          @click="requestRecommendation()"
        >
          <span v-if="working" class="button-spinner"></span
          >{{
            working ? "正在搭配…" : result ? "重新搭配这一桌" : "看看怎么点"
          }}
        </button>
        <p v-if="!submitted">从成员列表填写要求，就可以开始搭配了</p>
      </div>
    </template>
    <article v-else-if="resultView && result" class="result result-page">
      <p v-if="state?.recommendationInvalid" class="notice">
        大家的要求或菜单变了，这份方案需要重新搭配。<button
          :disabled="working"
          @click="requestRecommendation()"
        >
          重新搭配
        </button>
      </p>
      <div class="result-total">
        <div>
          <span
            >{{ result.draft.items.length }} 项 · 人均约
            {{
              money(
                Math.ceil(result.draft.totalFen / (state?.session.people || 1)),
              )
            }}</span
          ><strong>{{ money(result.draft.totalFen) }}</strong>
        </div>
        <span
          :class="[
            'result-badge',
            { partial: result.draft.mealStatus === 'partial' },
          ]"
          >{{
            result.draft.mealStatus === "partial"
              ? "还有需要补齐的地方"
              : "饭菜已配齐"
          }}</span
        >
      </div>
      <ul class="result-dishes">
        <li
          v-for="item in result.draft.items"
          :key="`${item.itemType}:${item.itemId}`"
          class="result-dish"
        >
          <img
            v-if="itemImage(item)"
            :src="itemImage(item)"
            :alt="item.name"
            loading="lazy"
          />
          <div v-else class="result-dish-placeholder">
            <AppIcon name="dish" :size="34" />
          </div>
          <div class="result-dish-copy">
            <h2>{{ item.name }}</h2>
            <span v-if="itemDescription(item)" class="dish-description">{{
              itemDescription(item)
            }}</span
            ><span v-if="item.itemType === 'setMeal'" class="hint">套餐</span>
            <div class="result-dish-bottom">
              <strong>{{ money(item.unitPriceFen * item.quantity) }}</strong
              ><span>× {{ item.quantity }}</span>
            </div>
          </div>
        </li>
      </ul>
      <div class="result-edit-toolbar">
        <button
          v-if="state?.session.state !== 'closed'"
          :disabled="working || state?.recommendationInvalid"
          @click="startResultEdit"
        >
          修改这桌方案</button
        ><button
          :disabled="
            working ||
            state?.recommendationInvalid ||
            state?.session.state === 'closed'
          "
          @click="requestRecommendation('addSoup')"
        >
          再加一道汤
        </button>
      </div>
      <div v-if="editingResult" class="result-editor">
        <h3>保留、删菜或调整份数</h3>
        <div
          v-for="(i, index) in editedItems"
          :key="`${i.itemType}:${i.itemId}`"
          class="row"
        >
          <span>{{ i.name }}</span
          ><label
            >份数<input
              v-model.number="i.quantity"
              type="number"
              min="1"
              max="100" /></label
          ><button @click="editedItems.splice(index, 1)">
            移除 {{ i.name }}
          </button>
        </div>
        <div class="row">
          <select v-model="addItem" aria-label="添加菜品或套餐">
            <option value="">选择要添加或替换的菜品</option>
            <option
              v-for="d in menu?.dishes.filter((d) => d.available)"
              :key="d.id"
              :value="d.id"
            >
              {{ d.name }} · {{ money(d.priceFen) }}
            </option>
            <option v-for="m in menu?.setMeals" :key="m.id" :value="m.id">
              套餐：{{ m.name }}
            </option></select
          ><button :disabled="!addItem" @click="appendItem">加入方案</button>
        </div>
        <p class="hint">
          保存时重新计算价格、个人适配和饭菜缺口；不会自动补回你移除的条目。
        </p>
        <div class="row">
          <button @click="editingResult = false">取消修改</button
          ><button class="primary" :disabled="busy" @click="saveResultEdit">
            保存并重新校验
          </button>
        </div>
      </div>

      <details class="result-details">
        <summary>看看每个人怎么吃</summary>
        <p v-for="m in result.draft.mealMembers" :key="m.memberId">
          <strong>{{
            state?.members.find((p) => p.id === m.memberId)?.nickname
          }}</strong>
          · 热菜 {{ m.halfDishAllocated / 2 }} / {{ m.halfDishNeed / 2 }} 份 ·
          {{
            m.stapleOptOut
              ? "不要主食"
              : (menu?.dishes.find((d) => d.id === m.stapleDishId)?.name ??
                "主食待补充")
          }}
        </p>
        <p>
          适合我的菜：{{
            mine.map((d) => d.dish.name).join("、") || "目前没有确定适配的菜"
          }}
        </p>
        <p class="hint">
          热菜 {{ result.draft.estimatedHotSupply }} /
          {{ result.draft.estimatedHotNeed }} 份
        </p>
        <p
          v-if="result.draft.uncoveredIds.includes(state?.self?.id ?? '')"
          class="error"
        >
          还没有适合你的非汤、主食或饮品菜；食材不完整的菜暂不计入覆盖。
        </p>
        <p
          v-if="result.draft.undercoveredIds.includes(state?.self?.id ?? '')"
          class="notice"
        >
          目前只有 1 道适合的菜，选择较少。
        </p>
        <p v-for="notice in result.draft.notices" :key="notice" class="hint">
          {{ notice }}
        </p>
        <details v-if="result.draft.unmetWishes.length">
          <summary>没有满足的想吃愿望</summary>
          <p v-for="(wish, i) in result.draft.unmetWishes" :key="i">
            {{
              menu?.dishes.find((d) => d.id === wish.itemId)?.name ??
              menu?.setMeals.find((m) => m.id === wish.itemId)?.name ??
              wish.itemId
            }}：{{ wish.reason }}
          </p>
        </details>
        <p v-if="submitted < (state?.session.people ?? 0)" class="hint">
          成员尚未填齐，方案已保留；填写齐全后再确认整桌方案。
        </p>

        <p v-if="result.draft.budgetWarning" class="notice">
          {{ result.draft.budgetWarning }}
        </p>
      </details>
      <details
        v-if="result.draft.items.some((i) => i.itemType === 'setMeal')"
        class="result-details"
      >
        <summary>套餐里有哪些菜</summary>
        <p v-for="d in result.draft.expandedDishes" :key="d.dish.id">
          {{ d.dish.name }} × {{ d.quantity
          }}<span v-if="d.dish.ingredients.includes('unknown')">
            · 其余食材不详</span
          >
        </p>
      </details>
      <section class="dining-assistant card">
        <div class="assistant-title">
          <span class="assistant-avatar"
            ><AppIcon name="dish" :size="22"
          /></span>
          <div>
            <strong>点菜员</strong
            ><small>{{
              aiEnabled ? "一起商量，点得更合口味" : "基础搭配 · 可手动调整"
            }}</small>
          </div>
        </div>
        <div class="chat-history">
          <p
            v-for="m in state?.messages"
            :key="m.id"
            :class="m.role === 'agent' ? 'assistant-message' : 'guest-message'"
          >
            <span>{{ m.content }}</span>
          </p>
        </div>
        <div v-if="working" class="assistant-message" role="status">
          正在想怎么搭配<span class="typing-dots"><i></i><i></i><i></i></span>
        </div>
        <form
          v-if="aiEnabled && state?.session.state !== 'closed'"
          class="assistant-input"
          @submit.prevent="sendChat"
        >
          <input
            v-model="chatText"
            aria-label="和点菜员说说"
            maxlength="200"
            placeholder="想换哪道？或者再清淡一点…"
            :disabled="working"
          /><button
            type="submit"
            class="primary"
            :disabled="working || !chatText.trim()"
          >
            发送
          </button>
        </form>
      </section>
      <div class="result-actions">
        <button
          v-if="
            host &&
            result.canConfirm &&
            !state?.recommendationInvalid &&
            state?.session.state !== 'closed'
          "
          class="primary"
          :disabled="working"
          @click="
            send('confirm_recommendation', {
              id: result.id,
              version: state?.stateVersion,
            })
          "
        >
          确认这桌方案</button
        ><template v-if="state?.session.state === 'closed'"
          ><p>本桌已确认</p>
          <button v-if="host" @click="reopen">重开同一聚餐局</button></template
        >
      </div>
    </article>
    <div v-else-if="resultView && state" class="entry-empty card">
      <AppIcon name="dish" :size="40" />
      <h2>还没开始搭配</h2>
      <RouterLink :to="`/s/${route.params.code}`">返回这一桌</RouterLink>
    </div>
    <ModalSheet v-model="invite" title="邀请同行人"
      ><div class="invitation-content">
        <p>扫码加入这一桌</p>
        <img v-if="qr" :src="qr" alt="聚餐局邀请二维码" class="qr" /><strong
          class="invite-code"
          >{{ route.params.code }}</strong
        ><small>也可以在首页输入聚餐码</small>
      </div>
      <div class="invite-copy">
        <input :value="inviteLink" readonly aria-label="邀请链接" /><button
          @click="copyInvite"
        >
          {{ copied ? "已复制" : "复制链接" }}
        </button>
      </div></ModalSheet
    >
    <ModalSheet
      v-model="companion"
      :title="companionId ? '编辑同行人的要求' : '帮同行人填写'"
      ><label class="companion-name"
        >称呼<input
          v-model="companionName"
          maxlength="40"
          placeholder="同行人" /></label
      ><PreferencesForm v-model="companionPrefs" :menu="menu" />
      <div class="modal-actions">
        <button @click="companion = false">取消</button
        ><button class="primary" :disabled="busy" @click="saveCompanion">
          保存同行人要求
        </button>
      </div></ModalSheet
    >
  </section>
</template>
