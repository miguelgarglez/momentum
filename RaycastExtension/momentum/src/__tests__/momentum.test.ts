import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { showToast } from "./raycast-api.stub";

const execFileMock = vi.fn();

vi.mock("child_process", () => ({
  execFile: execFileMock,
}));

function jsonResponse(status: number, payload: unknown) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("momentum transport", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("uses the primary port for commands when available", async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(200, { ok: true, data: { ok: true } }));
    vi.stubGlobal("fetch", fetchMock);

    const { postMomentumCommand } = await import("../momentum");
    const result = await postMomentumCommand<{ ok: boolean }>("token-1", { action: "projects.list", apiVersion: 1 });

    expect(result.response.status).toBe(200);
    expect(result.payload.ok).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toContain("http://127.0.0.1:51637/v1/commands");
    expect(init.headers).toMatchObject({
      Authorization: "Bearer token-1",
      "Content-Type": "application/json",
    });
  });

  it("falls back to secondary port when primary fails", async () => {
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce(new Error("offline"))
      .mockResolvedValueOnce(jsonResponse(200, { ok: true, data: { source: "secondary" } }));
    vi.stubGlobal("fetch", fetchMock);

    const { postMomentumCommand } = await import("../momentum");
    const result = await postMomentumCommand<{ source: string }>("token-2", { action: "projects.list", apiVersion: 1 });

    expect(result.response.status).toBe(200);
    expect(result.payload.data?.source).toBe("secondary");
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect((fetchMock.mock.calls[1] as [string])[0]).toContain("http://127.0.0.1:51638/v1/commands");
  });

  it("returns unauthorized fallback before unsupported-action fallback", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(401, { ok: false, error: "Unauthorized" }))
      .mockResolvedValueOnce(jsonResponse(422, { ok: false, error: "UnsupportedAction" }));
    vi.stubGlobal("fetch", fetchMock);

    const { postMomentumCommand } = await import("../momentum");
    const result = await postMomentumCommand("token-3", { action: "manual.start", apiVersion: 1 });

    expect(result.response.status).toBe(401);
    expect(result.payload.error).toBe("Unauthorized");
  });

  it("throws a transport error when all command attempts fail", async () => {
    const fetchMock = vi.fn().mockRejectedValue(new Error("offline"));
    vi.stubGlobal("fetch", fetchMock);

    const { postMomentumCommand } = await import("../momentum");

    await expect(postMomentumCommand("token-4", { action: "manual.start", apiVersion: 1 })).rejects.toThrow("offline");
  });

  it("openMomentumApp does not launch process when app endpoint already succeeds", async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(200, { ok: true, data: {} }));
    vi.stubGlobal("fetch", fetchMock);

    const { openMomentumApp } = await import("../momentum");
    await openMomentumApp();

    expect(execFileMock).not.toHaveBeenCalled();
    expect(showToast).not.toHaveBeenCalled();
  });

  it("openMomentumApp shows failure toast when process launch fails", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(503, { ok: false }))
      .mockResolvedValueOnce(jsonResponse(503, { ok: false }));
    vi.stubGlobal("fetch", fetchMock);

    execFileMock.mockImplementation((_file: string, _args: string[], cb: (error: Error | null) => void) => {
      cb(new Error("launch failed"));
    });

    const { openMomentumApp } = await import("../momentum");
    await openMomentumApp();

    expect(showToast).toHaveBeenCalledWith(
      expect.objectContaining({
        title: "No pudimos abrir Momentum",
      }),
    );
  });

  it("reads capabilities from health endpoint", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        ok: true,
        data: {
          apiVersion: 1,
          capabilities: {
            supportedCommandActions: ["projects.list", "manual.stop"],
            requiresPairing: true,
          },
        },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const { getMomentumCapabilities } = await import("../momentum");
    const capabilities = await getMomentumCapabilities({ force: true });

    expect(capabilities).toEqual({
      apiVersion: 1,
      supportedCommandActions: ["projects.list", "manual.stop"],
      requiresPairing: true,
    });
  });

  it("reports unsupported command from capabilities", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        ok: true,
        data: {
          apiVersion: 1,
          capabilities: {
            supportedCommandActions: ["projects.list"],
            requiresPairing: true,
          },
        },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const { isCommandSupported } = await import("../momentum");
    const support = await isCommandSupported("manual.stop", { force: true });
    expect(support).toBe("unsupported");
  });

  it("reports unknown support when app exposes no capabilities", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        ok: true,
        data: {
          apiVersion: 1,
        },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const { isCommandSupported } = await import("../momentum");
    const support = await isCommandSupported("manual.stop", { force: true });
    expect(support).toBe("unknown");
  });
});
