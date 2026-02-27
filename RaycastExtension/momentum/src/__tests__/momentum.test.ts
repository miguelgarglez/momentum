import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { copy } from "../copy";
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

function mockMissingMomentumInstall() {
  execFileMock.mockImplementation(
    (file: string, _args: string[], cb: (error: Error | null, stdout?: string) => void) => {
      if (file === "/usr/bin/osascript") {
        cb(null, "");
        return;
      }
      cb(new Error("not installed"), "");
    },
  );
}

describe("momentum transport", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    execFileMock.mockImplementation(
      (_file: string, _args: string[], cb: (error: Error | null, stdout?: string) => void) => {
        cb(new Error("exec not mocked"), "");
      },
    );
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

  it("retries commands after integration recovers", async () => {
    let commandCalls = 0;
    const fetchMock = vi.fn().mockImplementation((url: string) => {
      if (url.includes("/v1/commands")) {
        commandCalls += 1;
        if (commandCalls <= 2) {
          return Promise.reject(new Error("offline"));
        }
        return Promise.resolve(jsonResponse(200, { ok: true, data: { recovered: true } }));
      }

      if (url.includes("/health")) {
        return Promise.resolve(jsonResponse(200, { ok: true, data: { apiVersion: 1 } }));
      }

      return Promise.resolve(jsonResponse(503, { ok: false }));
    });
    vi.stubGlobal("fetch", fetchMock);

    const { postMomentumCommand } = await import("../momentum");
    const result = await postMomentumCommand<{ recovered: boolean }>("token-4", {
      action: "projects.list",
      apiVersion: 1,
    });

    expect(result.payload.data?.recovered).toBe(true);
    expect(commandCalls).toBe(3);
  });

  it("throws a prerequisite error when Momentum is not installed", async () => {
    const fetchMock = vi.fn().mockRejectedValue(new Error("offline"));
    vi.stubGlobal("fetch", fetchMock);
    mockMissingMomentumInstall();

    const { postMomentumCommand } = await import("../momentum");

    await expect(postMomentumCommand("token-5", { action: "manual.start", apiVersion: 1 })).rejects.toThrow(
      copy.momentumNotInstalledMessage,
    );
  });

  it("openMomentumApp does not launch process when app endpoint already succeeds", async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(200, { ok: true, data: {} }));
    vi.stubGlobal("fetch", fetchMock);

    const { openMomentumApp } = await import("../momentum");
    await openMomentumApp();

    expect(execFileMock).not.toHaveBeenCalled();
    expect(showToast).not.toHaveBeenCalled();
  });

  it("openMomentumApp shows prerequisite toast when app is missing", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(503, { ok: false }))
      .mockResolvedValueOnce(jsonResponse(503, { ok: false }));
    vi.stubGlobal("fetch", fetchMock);
    mockMissingMomentumInstall();

    const { openMomentumApp } = await import("../momentum");
    await openMomentumApp();

    expect(showToast).toHaveBeenCalledWith(
      expect.objectContaining({
        title: copy.momentumRequiredTitle,
        message: copy.momentumNotInstalledMessage,
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

  it("confirmPairing falls back to secondary port", async () => {
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce(new Error("offline"))
      .mockResolvedValueOnce(jsonResponse(200, { ok: true, data: { token: "token-fallback" } }));
    vi.stubGlobal("fetch", fetchMock);

    const { confirmPairing } = await import("../momentum");
    const token = await confirmPairing("1234");

    expect(token).toBe("token-fallback");
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect((fetchMock.mock.calls[1] as [string])[0]).toContain("http://127.0.0.1:51638/v1/pairing/confirm");
  });

  it("confirmPairing exposes backend message on invalid code", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(401, { ok: false, message: "Invalid or expired code." }))
      .mockResolvedValueOnce(jsonResponse(401, { ok: false, message: "Invalid or expired code." }));
    vi.stubGlobal("fetch", fetchMock);

    const { confirmPairing } = await import("../momentum");
    await expect(confirmPairing("0000")).rejects.toThrow("Invalid or expired code.");
  });

  it("confirmPairing reports prerequisite when app is missing", async () => {
    const fetchMock = vi.fn().mockRejectedValue(new Error("offline"));
    vi.stubGlobal("fetch", fetchMock);
    mockMissingMomentumInstall();

    const { confirmPairing } = await import("../momentum");
    await expect(confirmPairing("1234")).rejects.toThrow(copy.momentumNotInstalledMessage);
  });
});
