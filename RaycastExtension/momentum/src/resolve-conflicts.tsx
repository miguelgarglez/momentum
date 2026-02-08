import { Detail, LocalStorage, PopToRootType, popToRoot, showHUD, showToast, Toast } from "@raycast/api";
import { useEffect, useState } from "react";
import { resolveConflicts } from "./commands/resolveConflictsService";
import { PairingForm } from "./components/PairingForm";
import { copy } from "./copy";

const TOKEN_KEY = "momentum.token";

export default function Command() {
  const [isLoading, setIsLoading] = useState(true);
  const [pairingRequired, setPairingRequired] = useState(false);
  const [pairingError, setPairingError] = useState<string | null>(null);

  useEffect(() => {
    void bootstrap();
  }, []);

  async function bootstrap() {
    setIsLoading(true);
    const token = (await LocalStorage.getItem<string>(TOKEN_KEY)) ?? null;
    if (!token) {
      setPairingRequired(true);
      setIsLoading(false);
      return;
    }

    await runWithToken(token);
  }

  async function handlePaired(token: string) {
    await LocalStorage.setItem(TOKEN_KEY, token);
    setPairingRequired(false);
    setPairingError(null);
    await runWithToken(token);
  }

  async function runWithToken(token: string) {
    setIsLoading(true);
    try {
      const result = await resolveConflicts(token);
      if (result.kind === "unauthorized") {
        await LocalStorage.removeItem(TOKEN_KEY);
        setPairingRequired(true);
        setPairingError(copy.pairAgainFromListProjects);
        await showToast({
          style: Toast.Style.Failure,
          title: copy.invalidTokenTitle,
          message: copy.pairAgainFromListProjects,
        });
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
    } catch (runError) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't resolve conflicts",
        message: runError instanceof Error ? runError.message : copy.unknownError,
      });
      await popToRoot({ clearSearchBar: true });
    } finally {
      setIsLoading(false);
    }
  }

  if (pairingRequired) {
    return <PairingForm onPaired={handlePaired} error={pairingError} />;
  }

  return <Detail isLoading={isLoading} markdown="Checking pending conflicts..." />;
}
