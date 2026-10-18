import { BrowserQRCodeReader } from "@zxing/browser";
export async function scanCode(
  video: HTMLVideoElement,
  signal: AbortSignal,
): Promise<string> {
  const reader = new BrowserQRCodeReader();
  let stop = () => {};
  const cleanup = () => {
    stop();
    for (const track of (video.srcObject as MediaStream | null)?.getTracks() ??
      [])
      track.stop();
    video.srcObject = null;
  };
  return new Promise<string>((resolve, reject) => {
    signal.addEventListener(
      "abort",
      () => {
        cleanup();
        reject(new Error("已停止扫码"));
      },
      { once: true },
    );
    reader
      .decodeFromVideoDevice(undefined, video, (result, _error, controls) => {
        stop = () => controls.stop();
        if (result) {
          cleanup();
          resolve(result.getText());
        }
      })
      .then((controls) => {
        stop = () => controls.stop();
        if (signal.aborted) cleanup();
      })
      .catch((error) => {
        cleanup();
        reject(error);
      });
  });
}
