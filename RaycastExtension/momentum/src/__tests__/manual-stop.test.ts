import { beforeEach, describe, expect, it, vi } from "vitest";
import { LocalStorage, popToRoot, showHUD, showToast } from "./raycast-api.stub";

const postMomentumCommandMock = vi.fn();
const isCommandSupportedMock = vi.fn();

vi.mock("../momentum", () => ({
  postMomentumCommand: postMomentumCommandMock,
  isCommandSupported: isCommandSupportedMock,
}));

function jsonResponse(status: number, payload: unknown) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("manual-stop command", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    LocalStorage.getItem.mockReset();
    LocalStorage.removeItem.mockReset();
    showToast.mockReset();
    showHUD.mockReset();
    popToRoot.mockReset();
    isCommandSupportedMock.mockResolvedValue("supported");
  });

  it("shows pairing-required toast when no token exists", async () => {
    LocalStorage.getItem.mockResolvedValue(null);

    const command = (await import("../manual-stop")).default;
    await command();

    expect(postMomentumCommandMock).not.toHaveBeenCalled();
    expect(showToast).toHaveBeenCalledWith(
      expect.objectContaining({
        title: "Pairing Required",
      }),
    );
  });

  it("shows HUD when manual tracking was active", async () => {
    LocalStorage.getItem.mockResolvedValue("token-1");
    postMomentumCommandMock.mockResolvedValue({
      response: jsonResponse(200, { ok: true, data: { wasActive: true } }),
      payload: { ok: true, data: { wasActive: true } },
    });

    const command = (await import("../manual-stop")).default;
    await command();

    expect(showHUD).toHaveBeenCalledWith(
      "✓ Manual tracking stopped",
      expect.objectContaining({
        clearRootSearch: true,
      }),
    );
    expect(popToRoot).not.toHaveBeenCalled();
  });

  it("shows toast and returns to root when tracking was already stopped", async () => {
    LocalStorage.getItem.mockResolvedValue("token-2");
    postMomentumCommandMock.mockResolvedValue({
      response: jsonResponse(200, { ok: true, data: { wasActive: false } }),
      payload: { ok: true, data: { wasActive: false } },
    });

    const command = (await import("../manual-stop")).default;
    await command();

    expect(showToast).toHaveBeenCalledWith(
      expect.objectContaining({
        title: "Manual tracking was already stopped",
      }),
    );
    expect(popToRoot).toHaveBeenCalledWith({ clearSearchBar: true });
  });

  it("cleans token and shows invalid-token toast on 401", async () => {
    LocalStorage.getItem.mockResolvedValue("token-3");
    postMomentumCommandMock.mockResolvedValue({
      response: jsonResponse(401, { ok: false, error: "Unauthorized" }),
      payload: { ok: false, error: "Unauthorized" },
    });

    const command = (await import("../manual-stop")).default;
    await command();

    expect(LocalStorage.removeItem).toHaveBeenCalledWith("momentum.token");
    expect(showToast).toHaveBeenCalledWith(
      expect.objectContaining({
        title: "Invalid Token",
      }),
    );
  });

  it("shows failure toast when command is unsupported", async () => {
    isCommandSupportedMock.mockResolvedValue("unsupported");
    LocalStorage.getItem.mockResolvedValue("token-x");

    const command = (await import("../manual-stop")).default;
    await command();

    expect(postMomentumCommandMock).not.toHaveBeenCalled();
    expect(showToast).toHaveBeenCalledWith(
      expect.objectContaining({
        title: "Command Not Supported",
      }),
    );
  });

  it("shows failure toast when backend reports unsupported action", async () => {
    LocalStorage.getItem.mockResolvedValue("token-4");
    postMomentumCommandMock.mockResolvedValue({
      response: jsonResponse(422, { ok: false, error: "UnsupportedAction" }),
      payload: { ok: false, error: "UnsupportedAction" },
    });

    const command = (await import("../manual-stop")).default;
    await command();

    expect(showToast).toHaveBeenCalledWith(
      expect.objectContaining({
        title: "Couldn't stop manual tracking",
      }),
    );
  });
});
