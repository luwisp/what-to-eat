import { describe, expect, it } from "vitest";
import { createRequestId } from "./requestId";

describe("request IDs", () => {
  it("uses randomUUID when the secure-context API is available", () => {
    expect(createRequestId({ randomUUID: () => "native-id" })).toBe(
      "native-id",
    );
  });

  it("creates a UUID with getRandomValues on an insecure HTTP origin", () => {
    expect(
      createRequestId({
        getRandomValues(values) {
          values.forEach((_, index) => (values[index] = index));
          return values;
        },
      }),
    ).toBe("00010203-0405-4607-8809-0a0b0c0d0e0f");
  });
});
