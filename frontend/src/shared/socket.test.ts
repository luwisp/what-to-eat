import { it, expect, vi } from "vitest";
vi.mock("./api", () => ({
  ensureVisitor: vi.fn().mockResolvedValue(undefined),
}));
import { connectRoom } from "./socket";
class FakeSocket {
  static OPEN = 1;
  static instances: FakeSocket[] = [];
  readyState = 1;
  closed = false;
  sent: string[] = [];
  onopen: (() => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  constructor(_url: string) {
    FakeSocket.instances.push(this);
  }
  send(value: string) {
    this.sent.push(value);
  }
  close() {
    this.closed = true;
  }
}
it("reconnect fetches a fresh snapshot, never replays old commands or lets an old socket close the new one", async () => {
  vi.useFakeTimers();
  vi.stubGlobal("WebSocket", FakeSocket);
  vi.stubGlobal("location", { protocol: "http:", host: "dining.test" });
  const states: unknown[] = [];
  const connection = connectRoom(
    "A3F9",
    (s) => states.push(s),
    () => {},
  );
  try {
    await Promise.resolve();
    await Promise.resolve();
    const old = FakeSocket.instances.at(-1)!;
    old.onopen?.();
    old.onmessage?.({
      data: JSON.stringify({
        type: "room_state",
        payload: { stateVersion: 1 },
      }),
    });
    const sent = connection.send("update_preferences", { expectedVersion: 1 });
    const rejected = expect(sent).rejects.toThrow("连接已断开");
    old.onclose?.();
    await rejected;
    await vi.advanceTimersByTimeAsync(501);
    const fresh = FakeSocket.instances.at(-1)!;
    expect(fresh).not.toBe(old);
    fresh.onopen?.();
    fresh.onmessage?.({
      data: JSON.stringify({
        type: "room_state",
        payload: { stateVersion: 2 },
      }),
    });
    expect(fresh.sent.map((x) => JSON.parse(x).type)).toEqual(["join_room"]);
    old.onerror?.();
    expect(fresh.closed).toBe(false);
    expect(states).toEqual([{ stateVersion: 1 }, { stateVersion: 2 }]);
  } finally {
    connection.close();
    vi.unstubAllGlobals();
    vi.useRealTimers();
  }
});
