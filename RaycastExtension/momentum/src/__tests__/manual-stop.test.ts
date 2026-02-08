import { describe, expect, it, vi } from "vitest";
import { stopManualTracking } from "../commands/manualStopService";

function jsonResponse(status: number, payload: unknown) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("manualStopService", () => {
  it("returns unsupported when capabilities report unsupported command", async () => {
    const postCommand = vi.fn();
    const supportsCommand = vi.fn().mockResolvedValue("unsupported");

    const result = await stopManualTracking("token", postCommand as never, supportsCommand as never);

    expect(result).toEqual({ kind: "unsupported" });
    expect(postCommand).not.toHaveBeenCalled();
  });

  it("maps unauthorized", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(401, { ok: false, error: "Unauthorized" }),
      payload: { ok: false, error: "Unauthorized" },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await stopManualTracking("token", postCommand as never, supportsCommand as never);

    expect(result).toEqual({ kind: "unauthorized" });
  });

  it("maps unsupported action response", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(422, { ok: false, error: "UnsupportedAction" }),
      payload: { ok: false, error: "UnsupportedAction" },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await stopManualTracking("token", postCommand as never, supportsCommand as never);

    expect(result).toEqual({ kind: "unsupported" });
  });

  it("returns ok when tracking was active", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(200, { ok: true, data: { wasActive: true } }),
      payload: { ok: true, data: { wasActive: true } },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await stopManualTracking("token", postCommand as never, supportsCommand as never);

    expect(result).toEqual({ kind: "ok", wasActive: true });
  });

  it("returns ok when tracking was already stopped", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(200, { ok: true, data: { wasActive: false } }),
      payload: { ok: true, data: { wasActive: false } },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await stopManualTracking("token", postCommand as never, supportsCommand as never);

    expect(result).toEqual({ kind: "ok", wasActive: false });
  });

  it("maps generic error with fallback message", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(500, { ok: false }),
      payload: { ok: false },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await stopManualTracking("token", postCommand as never, supportsCommand as never);

    expect(result).toEqual({ kind: "error", message: "Couldn't stop manual tracking." });
  });
});
