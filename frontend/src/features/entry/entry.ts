export function resolveEntry(
  value: string,
  origin: string,
): { kind: "restaurant" | "room" | "short"; code: string } | null {
  const text = value.trim();
  if (/^[A-Za-z0-9_-]{1,64}$/.test(text)) return { kind: "short", code: text };
  try {
    const url = new URL(text, origin);
    if (url.origin !== new URL(origin).origin || url.username || url.password)
      return null;
    const match = /^\/(r|s)\/([A-Za-z0-9_-]{1,64})\/?$/.exec(url.pathname);
    if (!match) return null;
    if (match[1] === "s" && !/^[a-z0-9]{4,16}$/i.test(match[2])) return null;
    return { kind: match[1] === "r" ? "restaurant" : "room", code: match[2] };
  } catch {
    return null;
  }
}
export function safeReturnTo(value: unknown): string {
  return typeof value === "string" &&
    value.startsWith("/") &&
    !value.startsWith("//") &&
    !value.includes("\\") &&
    !/[\x00-\x1f]/.test(value)
    ? value
    : "/";
}
