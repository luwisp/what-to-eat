import type { RoomSnapshot } from "./contracts";
import { ensureVisitor } from "./api";
export interface RoomConnection {
  send(type: string, payload: Record<string, unknown>): Promise<void>;
  close(): void;
}
export function connectRoom(
  code: string,
  onState: (state: RoomSnapshot) => void,
  onStatus: (value: string) => void,
): RoomConnection {
  let socket: WebSocket | undefined,
    closed = false,
    ready = false,
    attempt = 0,
    generation = 0,
    timer: ReturnType<typeof setTimeout> | undefined;
  const pending = new Map<
    string,
    {
      resolve: () => void;
      reject: (reason: Error) => void;
      timer: ReturnType<typeof setTimeout>;
    }
  >();
  const rejectAll = () => {
    for (const p of pending.values()) {
      clearTimeout(p.timer);
      p.reject(new Error("连接已断开，请确认最新状态后重试"));
    }
    pending.clear();
  };
  async function open() {
    const current = ++generation;
    ready = false;
    onStatus(attempt ? "正在重连" : "正在连接");
    try {
      await ensureVisitor();
      if (closed || current !== generation) return;
      const transport = new WebSocket(
        `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws`,
      );
      socket = transport;
      transport.onopen = () => {
        if (current !== generation || closed) return;
        transport.send(
          JSON.stringify({
            type: "join_room",
            requestId: "join-" + crypto.randomUUID(),
            payload: { code },
          }),
        );
      };
      transport.onmessage = (event) => {
        if (current !== generation || closed) return;
        try {
          const m = JSON.parse(String(event.data));
          if (m.type === "room_state") {
            onState(m.payload);
            ready = true;
            attempt = 0;
            onStatus("已连接");
          }
          const p = pending.get(m.requestId);
          if (p) {
            clearTimeout(p.timer);
            pending.delete(m.requestId);
            m.type === "error"
              ? p.reject(new Error(m.payload.message))
              : p.resolve();
          }
          if (m.type === "error" && !p) onStatus(m.payload.message);
        } catch {
          onStatus("收到无效服务消息");
        }
      };
      transport.onclose = () => {
        if (current !== generation) return;
        ready = false;
        rejectAll();
        if (!closed) {
          onStatus("连接断开，正在恢复");
          timer = setTimeout(open, Math.min(15000, 500 * 2 ** attempt++));
        }
      };
      transport.onerror = () => {
        if (current === generation) transport.close();
      };
    } catch {
      if (!closed) {
        onStatus("服务不可用，正在重试");
        timer = setTimeout(open, Math.min(15000, 500 * 2 ** attempt++));
      }
    }
  }
  void open();
  return {
    send(type, payload) {
      if (!ready || socket?.readyState !== WebSocket.OPEN)
        return Promise.reject(new Error("请等待房间状态恢复后再操作"));
      const requestId = crypto.randomUUID();
      return new Promise<void>((resolve, reject) => {
        const expiry = setTimeout(() => {
          pending.delete(requestId);
          reject(new Error("操作未确认，请查看最新状态后重试"));
        }, 35000);
        pending.set(requestId, { resolve, reject, timer: expiry });
        socket!.send(JSON.stringify({ type, requestId, payload }));
      });
    },
    close() {
      closed = true;
      generation++;
      clearTimeout(timer);
      rejectAll();
      socket?.close();
    },
  };
}
