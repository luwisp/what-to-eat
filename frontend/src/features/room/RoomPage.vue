<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import QRCode from "qrcode";
import type {
  RoomSnapshot,
  Preferences,
  MenuSnapshot,
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
import PreferencesForm from "../../shared/PreferencesForm.vue";
const suggestions = ref<{ prefs: Preferences; message: string } | null>(null);
const route = useRoute(),
  router = useRouter(),
  state = ref<RoomSnapshot>(),
  status = ref("正在连接"),
  error = ref(""),
  notice = ref(""),
  nickname = ref(""),
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
const editing = computed(() => route.path.endsWith("/preferences"));
const host = computed(
  () => state.value?.self?.id === state.value?.session.hostParticipantId,
);
const submitted = computed(
  () => state.value?.members.filter((p) => p.submitted).length ?? 0,
);
const result = computed(() => state.value?.recommendation);
const inviteLink = computed(
  () => location.origin + "/s/" + String(route.params.code),
);
onMounted(() => {
  connection = connectRoom(
    String(route.params.code),
    (s) => {
      state.value = s;
      people.value = s.session.people;
      budget.value =
        s.session.budgetPerPersonFen === null
          ? ""
          : String(s.session.budgetPerPersonFen / 100);
      if (s.self && initialized !== s.self.id) {
        initialized = s.self.id;
        nickname.value = s.self.nickname;
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
      expectedVersion: state.value?.stateVersion,
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
  if (nickname.value.trim() && nickname.value !== state.value?.self?.nickname) {
    await send("join_room", {
      code: String(route.params.code),
      nickname: nickname.value,
    });
    if (error.value) return;
  }
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
async function interpret() {
  error.value = "";
  try {
    suggestions.value = await api("/api/preferences/interpret", "POST", {
      prefs: copyJson(prefs.value),
      note: prefs.value.note,
    });
  } catch (e) {
    error.value = (e as Error).message;
  }
}
function copyInvite() {
  void navigator.clipboard.writeText(inviteLink.value).catch(() => {
    error.value = "请复制上方链接";
  });
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
  <section>
    <p class="eyebrow">同一桌，一起选 · {{ status }}</p>
    <div class="row between">
      <h1>聚餐局 {{ route.params.code }}</h1>
      <button @click="invite = !invite">邀请同行人</button>
    </div>
    <p>
      {{ submitted }} 人已填写 / 声明 {{ state?.session.people ?? "—" }} 人 ·
      已登记 {{ state?.members.length ?? 0 }} 人
    </p>
    <div v-if="invite" class="card">
      <h2>邀请不需要等你填完</h2>
      <p>
        聚餐局码：<strong>{{ route.params.code }}</strong>
      </p>
      <input :value="inviteLink" readonly aria-label="邀请链接" /><button
        @click="copyInvite"
      >
        复制链接</button
      ><img v-if="qr" :src="qr" alt="聚餐局邀请二维码" class="qr" />
    </div>
    <nav class="chips">
      <RouterLink :to="`/s/${route.params.code}`">聚餐概览</RouterLink
      ><RouterLink :to="`/s/${route.params.code}/preferences`"
        >我的要求</RouterLink
      ><RouterLink
        v-if="state"
        :to="`/r/${state.restaurantCode}/menu?room=${route.params.code}`"
        >看菜单 / 标记想吃</RouterLink
      ><RouterLink
        :to="`/account?returnTo=${encodeURIComponent(route.fullPath)}`"
        >账号与默认设置</RouterLink
      >
    </nav>
    <p v-if="error" role="alert" class="error">{{ error }}</p>
    <p v-if="notice" role="status" class="notice">{{ notice }}</p>
    <p v-if="state?.recommendationInvalid && result" class="notice">
      需求或菜单已变化，原方案已失效，请重新推荐。
    </p>
    <div v-if="editing" class="card">
      <h2>先填自己的想法</h2>
      <p class="hint">
        {{
          state?.self?.submitted
            ? "之前提交的要求仍有效；再次保存后更新。"
            : "只有点“提交本局要求”才算已填写，默认设置与草稿不会自动提交。"
        }}
      </p>
      <label>本局昵称<input v-model="nickname" maxlength="40" /></label
      ><PreferencesForm v-model="prefs" /><button
        type="button"
        :disabled="!prefs.note.trim()"
        @click="interpret"
      >
        整理文字里的要求
      </button>
      <div v-if="suggestions" class="notice">
        <p>{{ suggestions.message }}</p>
        <p>
          过敏：{{
            suggestions.prefs.allergens.join("、") || "无新增"
          }}；不吃：{{ suggestions.prefs.avoidFoods.join("、") || "无新增" }}
        </p>
        <button
          @click="
            prefs = suggestions.prefs;
            suggestions = null;
          "
        >
          应用到表单（仍需提交）</button
        ><button @click="suggestions = null">不用这些建议</button>
      </div>
      <p v-if="prefs.wantedDishIds.length || prefs.wantedSetMealIds.length">
        已标记 {{ prefs.wantedDishIds.length }} 道菜、{{
          prefs.wantedSetMealIds.length
        }}
        个套餐。
        <RouterLink
          v-if="state"
          :to="`/r/${state.restaurantCode}/menu?room=${route.params.code}`"
          >继续看菜单</RouterLink
        >
      </p>
      <div class="row">
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
          提交本局要求
        </button>
      </div>
    </div>
    <template v-else
      ><div class="grid">
        <div class="card">
          <h2>大家的填写情况</h2>
          <ul class="members">
            <li v-for="m in state?.members" :key="m.id">
              <span
                >{{ m.nickname }}
                <small v-if="m.id === state?.self?.id">你</small
                ><small v-if="m.source === 'companion'">代填</small></span
              ><span>{{ m.submitted ? "已提交" : "还没提交" }}</span
              ><template v-if="m.filledByParticipantId === state?.self?.id"
                ><button @click="editCompanion(m.id)">修改</button
                ><button @click="send('remove_companion', { id: m.id })">
                  删除
                </button></template
              >
            </li>
          </ul>
          <button
            @click="editCompanion()"
            :disabled="state?.session.state === 'closed'"
          >
            补充一位不方便填写的同行人
          </button>
        </div>
        <form v-if="host" class="card" @submit.prevent="updateSession">
          <h2>本桌安排</h2>
          <label
            >人数<input
              v-model.number="people"
              type="number"
              :min="state?.members.length ?? 1"
              max="100" /></label
          ><label
            >人均预算（元，可不填）<input
              v-model="budget"
              inputmode="decimal" /></label
          ><button :disabled="busy || state?.session.state === 'closed'">
            保存人数和预算
          </button>
        </form>
      </div>
      <div class="row">
        <button
          class="primary"
          :disabled="
            busy ||
            !submitted ||
            !!state?.job ||
            state?.session.state === 'closed'
          "
          @click="send('request_recommendation')"
        >
          {{ state?.job ? "正在推荐…" : "看看怎么点" }}</button
        ><RouterLink
          v-if="!state?.self?.submitted"
          :to="`/s/${route.params.code}/preferences`"
          >填写我的要求 →</RouterLink
        >
      </div>
      <article v-if="result" class="card result">
        <div class="row between">
          <h2>这一桌的推荐</h2>
          <strong>{{ money(result.draft.totalFen) }}</strong>
        </div>
        <p v-if="result.mode === 'rules'" class="notice">已切换规则推荐</p>
        <p v-if="result.draft.budgetWarning" class="notice">
          {{ result.draft.budgetWarning }}
        </p>
        <ul>
          <li
            v-for="item in result.draft.items"
            :key="`${item.itemType}:${item.itemId}`"
          >
            {{ item.name }} × {{ item.quantity }}
            <small
              >{{ item.itemType === "setMeal" ? "套餐售价" : "单点" }}
              {{ money(item.unitPriceFen) }}</small
            >
          </li>
        </ul>
        <details>
          <summary>套餐展开后的实际菜品与份数</summary>
          <p v-for="d in result.draft.expandedDishes" :key="d.dish.id">
            {{ d.dish.name }} × {{ d.quantity
            }}<span v-if="d.dish.ingredients.some((i) => i === 'unknown')">
              · 其余食材不详</span
            >
          </p>
        </details>
        <h3>适合自己的菜</h3>
        <p>
          {{
            mine.map((d) => d.dish.name).join("、") ||
            "当前没有已确定适合你的菜"
          }}
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
        <div class="row">
          <button
            :disabled="
              busy ||
              state?.recommendationInvalid ||
              state?.session.state === 'closed'
            "
            @click="send('request_recommendation', { adjustment: 'addSoup' })"
          >
            再加一道汤</button
          ><button
            v-if="host && result.canConfirm && !state?.recommendationInvalid"
            class="primary"
            @click="
              send('confirm_recommendation', {
                id: result.id,
                version: state?.stateVersion,
              })
            "
          >
            确认这桌方案</button
          ><button
            v-if="host && state?.session.state === 'closed'"
            @click="send('reopen_recommendation')"
          >
            重开同一聚餐局
          </button>
        </div>
        <p v-if="state?.session.state === 'closed'">
          本桌已确认，修改前请发起人重开。
        </p>
        <div class="chat-history">
          <p v-for="m in state?.messages" :key="m.id">
            <strong>{{ m.role === "agent" ? "点菜助手" : "同行人" }}：</strong
            >{{ m.content }}
          </p>
        </div>
        <form @submit.prevent="send('chat_message', { text: chatText })">
          <label
            >对话调整<textarea
              v-model="chatText"
              :disabled="result.mode !== 'ai'"
              maxlength="200"
              :placeholder="
                result.mode === 'ai'
                  ? '例如：再清淡一点'
                  : '规则模式下暂不提供自由对话，可使用上方快捷操作'
              "
            /></label
          ><button :disabled="result.mode !== 'ai' || !chatText.trim() || busy">
            发送调整
          </button>
        </form>
      </article></template
    >
    <div v-if="companion" class="card">
      <h2>{{ companionId ? "修改" : "补充" }}同行人的要求</h2>
      <label
        >昵称（可不填）<input v-model="companionName" maxlength="40" /></label
      ><PreferencesForm v-model="companionPrefs" />
      <div class="row">
        <button @click="companion = false">取消</button
        ><button class="primary" @click="saveCompanion">保存同行人要求</button>
      </div>
    </div>
  </section>
</template>
