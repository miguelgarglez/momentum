import { Detail, LocalStorage, PopToRootType, popToRoot, showHUD, showToast, Toast } from "@raycast/api";
import { useEffect } from "react";
import { resolveConflicts } from "./commands/resolveConflictsService";
import { copy } from "./copy";

const TOKEN_KEY = "momentum.token";

export default function Command() {
  useEffect(() => {
    void run();
  }, []);

  async function run() {
    try {
      const token = (await LocalStorage.getItem<string>(TOKEN_KEY)) ?? null;
      if (!token) {
        await showToast({
          style: Toast.Style.Failure,
          title: copy.pairingRequiredTitle,
          message: copy.pairFirstFromListProjects,
        });
        await popToRoot({ clearSearchBar: true });
        return;
      }

      const result = await resolveConflicts(token);
      if (result.kind === "unauthorized") {
        await LocalStorage.removeItem(TOKEN_KEY);
        await showToast({
          style: Toast.Style.Failure,
          title: copy.invalidTokenTitle,
          message: copy.pairAgainFromListProjects,
        });
        await popToRoot({ clearSearchBar: true });
        return;
      }
      if (result.kind === "error") {
        throw new Error(result.message);
      }
      if (result.kind === "opened") {
        await showHUD(`✓ Opening resolution (${result.conflictsCount})`, {
          clearRootSearch: true,
          popToRootType: PopToRootType.Immediate,
        });
        await popToRoot({ clearSearchBar: true });
        return;
      }

      await showToast({
        style: Toast.Style.Success,
        title: "No pending conflicts",
        message: "Everything is up to date.",
      });
      await popToRoot({ clearSearchBar: true });
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't resolve conflicts",
        message: error instanceof Error ? error.message : copy.unknownError,
      });
      await popToRoot({ clearSearchBar: true });
    }
  }

  return <Detail isLoading markdown="Checking pending conflicts..." />;
}
