import { describe, expect, it, vi } from "vitest";
import {
  loadManualStartProjects,
  openManualStartForm,
  startManualTrackingExisting,
} from "../commands/manualStartService";

function jsonResponse(status: number, payload: unknown) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("manualStartService", () => {
  it("loads projects successfully", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(200, {
        ok: true,
        data: [{ id: "p1", name: "Project 1", colorHex: "#fff", iconName: "bolt" }],
      }),
      payload: { ok: true, data: [{ id: "p1", name: "Project 1", colorHex: "#fff", iconName: "bolt" }] },
    });

    const result = await loadManualStartProjects("token", postCommand as never);

    expect(result.kind).toBe("ok");
    if (result.kind === "ok") {
      expect(result.projects).toHaveLength(1);
      expect(result.projects[0].name).toBe("Project 1");
    }
  });

  it("maps unauthorized when loading projects", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(401, { ok: false, error: "Unauthorized" }),
      payload: { ok: false, error: "Unauthorized" },
    });

    const result = await loadManualStartProjects("token", postCommand as never);
    expect(result).toEqual({ kind: "unauthorized" });
  });

  it("maps unsupported action when starting manual existing", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(422, { ok: false, error: "UnsupportedAction" }),
      payload: { ok: false, error: "UnsupportedAction" },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await startManualTrackingExisting(
      "token",
      "project-id",
      "Project 1",
      postCommand as never,
      supportsCommand as never,
    );
    expect(result).toEqual({ kind: "unsupported" });
  });

  it("returns project payload when starting manual existing succeeds", async () => {
    const project = { id: "p1", name: "Project 1", colorHex: "#123", iconName: "bolt" };
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(200, { ok: true, data: { project } }),
      payload: { ok: true, data: { project } },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await startManualTrackingExisting(
      "token",
      "p1",
      "Project 1",
      postCommand as never,
      supportsCommand as never,
    );
    expect(result).toEqual({ kind: "ok", project });
  });

  it("maps unauthorized for open manual form", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(401, { ok: false, error: "Unauthorized" }),
      payload: { ok: false, error: "Unauthorized" },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await openManualStartForm("token", postCommand as never, supportsCommand as never);
    expect(result).toEqual({ kind: "unauthorized" });
  });

  it("returns ok for open manual form success", async () => {
    const postCommand = vi.fn().mockResolvedValue({
      response: jsonResponse(200, { ok: true, data: {} }),
      payload: { ok: true, data: {} },
    });
    const supportsCommand = vi.fn().mockResolvedValue("supported");

    const result = await openManualStartForm("token", postCommand as never, supportsCommand as never);
    expect(result).toEqual({ kind: "ok" });
  });

  it("maps unsupported when capability check reports unsupported", async () => {
    const postCommand = vi.fn();
    const supportsCommand = vi.fn().mockResolvedValue("unsupported");

    const result = await startManualTrackingExisting(
      "token",
      "project-id",
      "Project 1",
      postCommand as never,
      supportsCommand as never,
    );

    expect(result).toEqual({ kind: "unsupported" });
    expect(postCommand).not.toHaveBeenCalled();
  });
});
