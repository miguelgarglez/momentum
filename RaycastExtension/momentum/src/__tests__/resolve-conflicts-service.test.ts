import { describe, expect, it, vi } from "vitest";
import { resolveConflicts } from "../commands/resolveConflictsService";

function jsonResponse(status: number, payload: unknown) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("resolveConflictsService", () => {
  it("returns opened when there are conflicts", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(200, { ok: true, data: { conflictsCount: 3, opened: true } }),
      payload: { ok: true, data: { conflictsCount: 3, opened: true } },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await resolveConflicts("token", postCommand as never, supportsCommand as never);
    expect(result).toEqual({ kind: "opened", conflictsCount: 3 });
  });

  it("returns no-conflicts when count is zero", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(200, { ok: true, data: { conflictsCount: 0, opened: false } }),
      payload: { ok: true, data: { conflictsCount: 0, opened: false } },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await resolveConflicts("token", postCommand as never, supportsCommand as never);
    expect(result).toEqual({ kind: "no-conflicts" });
  });

  it("maps unauthorized", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(401, { ok: false, error: "Unauthorized" }),
      payload: { ok: false, error: "Unauthorized" },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await resolveConflicts("token", postCommand as never, supportsCommand as never);
    expect(result).toEqual({ kind: "unauthorized" });
  });

  it("maps generic error with fallback message", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(500, { ok: false }),
      payload: { ok: false },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await resolveConflicts("token", postCommand as never, supportsCommand as never);
    expect(result).toEqual({ kind: "error", message: "No pudimos comprobar los conflictos pendientes." });
  });

  it("returns error when capabilities report unsupported command", async () => {
    const postCommand = vi.fn();
    const supportsCommand = vi.fn().mockResolvedValue("unsupported");

    const result = await resolveConflicts("token", postCommand as never, supportsCommand as never);
    expect(result).toEqual({
      kind: "error",
      message: "Tu versión de Momentum no soporta resolución de conflictos desde Raycast.",
    });
    expect(postCommand).not.toHaveBeenCalled();
  });
});
