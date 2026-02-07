import { LocalStorage, PopToRootType, popToRoot, showHUD, showToast, Toast } from "@raycast/api";
import { isCommandSupported, postMomentumCommand } from "./momentum";
import { copy } from "./copy";

const TOKEN_KEY = "momentum.token";

type ManualStopResponse = {
  wasActive: boolean;
};

export default async function Command() {
  const token = (await LocalStorage.getItem<string>(TOKEN_KEY)) ?? null;
  if (!token) {
    await showToast({
      style: Toast.Style.Failure,
      title: copy.pairingRequiredTitle,
      message: copy.pairFirstFromListProjects,
    });
    return;
  }

  try {
    const support = await isCommandSupported("manual.stop");
    if (support === "unsupported") {
      await showToast({
        style: Toast.Style.Failure,
        title: copy.unsupportedCommandTitle,
        message: copy.unsupportedManualStopMessage,
      });
      return;
    }

    const { response, payload } = await postMomentumCommand<ManualStopResponse>(token, {
      action: "manual.stop",
      apiVersion: 1,
    });

    if (!response.ok || !payload.ok) {
      if (response.status === 401) {
        await LocalStorage.removeItem(TOKEN_KEY);
        await showToast({
          style: Toast.Style.Failure,
          title: copy.invalidTokenTitle,
          message: copy.pairAgainFromListProjects,
        });
        return;
      }
      if (payload.error === "UnsupportedAction") {
        throw new Error(copy.unsupportedAppCommandMessage);
      }
      throw new Error(payload.message ?? "Couldn't stop manual tracking.");
    }

    const wasActive = payload.data?.wasActive ?? false;
    if (wasActive) {
      await showHUD("✓ Manual tracking stopped", {
        clearRootSearch: true,
        popToRootType: PopToRootType.Immediate,
      });
      return;
    }

    await showToast({
      style: Toast.Style.Success,
      title: "Manual tracking was already stopped",
    });
    await popToRoot({ clearSearchBar: true });
  } catch (error) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Couldn't stop manual tracking",
      message: error instanceof Error ? error.message : copy.unknownError,
    });
  }
}
