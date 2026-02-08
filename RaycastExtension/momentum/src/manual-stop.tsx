import {
  Detail,
  LocalStorage,
  PopToRootType,
  closeMainWindow,
  popToRoot,
  showHUD,
  showToast,
  Toast,
} from "@raycast/api";
import { useEffect, useState } from "react";
import { stopManualTracking } from "./commands/manualStopService";
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

  async function closeCommandWindow() {
    await popToRoot({ clearSearchBar: true });
    await closeMainWindow({ clearRootSearch: true });
  }

  async function runWithToken(token: string) {
    setIsLoading(true);

    try {
      const result = await stopManualTracking(token);

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

      if (result.kind === "unsupported") {
        await showToast({
          style: Toast.Style.Failure,
          title: copy.unsupportedCommandTitle,
          message: copy.unsupportedManualStopMessage,
        });
        await closeCommandWindow();
        return;
      }

      if (result.kind === "error") {
        throw new Error(result.message);
      }

      if (result.wasActive) {
        await showHUD("✓ Manual tracking stopped", {
          clearRootSearch: true,
          popToRootType: PopToRootType.Immediate,
        });
        await closeMainWindow({ clearRootSearch: true });
        return;
      }

      await showToast({
        style: Toast.Style.Success,
        title: "Manual tracking was already stopped",
      });
      await closeCommandWindow();
    } catch (stopError) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't stop manual tracking",
        message: stopError instanceof Error ? stopError.message : copy.unknownError,
      });
      await closeCommandWindow();
    } finally {
      setIsLoading(false);
    }
  }

  if (pairingRequired) {
    return <PairingForm onPaired={handlePaired} error={pairingError} />;
  }

  return <Detail isLoading={isLoading} markdown="Stopping manual tracking..." />;
}
