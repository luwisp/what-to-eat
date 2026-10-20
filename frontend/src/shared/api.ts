import type {
  MenuSnapshot,
  RoomSnapshot,
  CreateSessionInput,
  UserDefaultSettings,
  AccountView,
} from "./contracts";
export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}
export async function api<T>(
  path: string,
  method = "GET",
  body?: unknown,
): Promise<T> {
  const r = await fetch(path, {
    method,
    credentials: "same-origin",
    headers: body === undefined ? {} : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!r.ok) {
    const err = await r.json().catch(() => ({}));
    throw new ApiError(
      r.status,
      err.error?.code ?? "HTTP_ERROR",
      err.error?.message ?? "服务暂不可用，请重试",
    );
  }
  return r.status === 204 ? (undefined as T) : ((await r.json()) as T);
}
export const getMenu = (code: string) =>
  api<MenuSnapshot>(`/api/restaurants/${encodeURIComponent(code)}/menu`);
export const ensureVisitor = () => api<void>("/api/visitor/session", "POST");
export const createRoom = async (
  input: CreateSessionInput,
  requestId: string,
) => {
  await ensureVisitor();
  return api<RoomSnapshot>("/api/sessions", "POST", { ...input, requestId });
};
export const getRoom = (code: string) =>
  api<RoomSnapshot>(`/api/sessions/${encodeURIComponent(code)}`);
export async function loadAccount(
  kind: "user" | "merchant" = "user",
): Promise<AccountView | null> {
  try {
    return await api(`/api/${kind}/me`);
  } catch (e) {
    if (e instanceof ApiError && e.status === 401) return null;
    throw e;
  }
}
export const saveDefaults = (settings: UserDefaultSettings) =>
  api<UserDefaultSettings>(
    "/api/user/default-settings",
    "PUT",
    Object.fromEntries(
      [
        "appetite",
        "allergens",
        "avoidFoods",
        "dietMode",
        "maxSpiceLevel",
        "tastePreferences",
      ].map((k) => [k, settings[k as keyof UserDefaultSettings]]),
    ),
  );
export const money = (fen: number) => `¥${(fen / 100).toFixed(2)}`;
export function priceFen(value: string): number {
  if (!/^\d+(\.\d{1,2})?$/.test(value.trim()))
    throw new Error("价格须为非负金额，最多两位小数");
  const [yuan, cents = ""] = value.trim().split(".");
  const n = Number(yuan) * 100 + Number(cents.padEnd(2, "0"));
  if (!Number.isSafeInteger(n)) throw new Error("价格过大");
  return n;
}

export function copyJson<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}
