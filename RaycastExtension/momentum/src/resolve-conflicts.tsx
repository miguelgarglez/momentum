import { Detail, LocalStorage, PopToRootType, popToRoot, showHUD, showToast, Toast } from "@raycast/api";
import { useEffect } from "react";
import { postMomentumCommand } from "./momentum";

const TOKEN_KEY = "momentum.token";

type ConflictsOpenResponse = {
  conflictsCount: number;
  opened: boolean;
};

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

      const { response, payload } = await postMomentumCommand<ConflictsOpenResponse>(token, {
        action: "conflicts.open",
        present: true,
        apiVersion: 1,
      });
      if (!response.ok || !payload.ok) {
        if (response.status === 401) {
          await LocalStorage.removeItem(TOKEN_KEY);
          await showToast({
            style: Toast.Style.Failure,
            title: "Token inválido",
            message: "Empareja de nuevo desde List projects.",
          });
          await popToRoot({ clearSearchBar: true });
          return;
        }
        throw new Error(payload.message ?? "No pudimos comprobar los conflictos pendientes.");
      }

      const conflictsCount = payload.data?.conflictsCount ?? 0;
      if (conflictsCount > 0) {
        await showHUD(`✓ Abriendo resolución (${conflictsCount})`, {
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
