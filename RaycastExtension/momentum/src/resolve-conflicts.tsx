import { Detail, LocalStorage, PopToRootType, popToRoot, showHUD, showToast, Toast } from "@raycast/api";
import { useEffect } from "react";
import { resolveConflicts } from "./commands/resolveConflictsService";

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
          title: "Emparejamiento requerido",
          message: "Empareja primero la extensión desde List projects.",
        });
        await popToRoot({ clearSearchBar: true });
        return;
      }

      const result = await resolveConflicts(token);
      if (result.kind === "unauthorized") {
        await LocalStorage.removeItem(TOKEN_KEY);
        await showToast({
          style: Toast.Style.Failure,
          title: "Token inválido",
          message: "Empareja de nuevo desde List projects.",
        });
        await popToRoot({ clearSearchBar: true });
        return;
      }
      if (result.kind === "error") {
        throw new Error(result.message);
      }
      if (result.kind === "opened") {
        await showHUD(`✓ Abriendo resolución (${result.conflictsCount})`, {
          clearRootSearch: true,
          popToRootType: PopToRootType.Immediate,
        });
        await popToRoot({ clearSearchBar: true });
        return;
      }

      await showToast({
        style: Toast.Style.Success,
        title: "No hay conflictos pendientes",
        message: "Todo en orden.",
      });
      await popToRoot({ clearSearchBar: true });
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "No pudimos resolver conflictos",
        message: error instanceof Error ? error.message : "Error desconocido",
      });
      await popToRoot({ clearSearchBar: true });
    }
  }

  return <Detail isLoading markdown="Comprobando conflictos pendientes…" />;
}
