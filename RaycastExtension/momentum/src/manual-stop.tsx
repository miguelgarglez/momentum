import { LocalStorage, PopToRootType, popToRoot, showHUD, showToast, Toast } from "@raycast/api";
import { postMomentumCommand } from "./momentum";

const TOKEN_KEY = "momentum.token";

type ManualStopResponse = {
  wasActive: boolean;
};

export default async function Command() {
  const token = (await LocalStorage.getItem<string>(TOKEN_KEY)) ?? null;
  if (!token) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Emparejamiento requerido",
      message: "Empareja primero la extensión desde List projects.",
    });
    return;
  }

  try {
    const { response, payload } = await postMomentumCommand<ManualStopResponse>(token, {
      action: "manual.stop",
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
        return;
      }
      if (payload.error === "UnsupportedAction") {
        throw new Error(
          "La app abierta no soporta este comando. Cierra Momentum release, abre la versión dev y vuelve a emparejar.",
        );
      }
      throw new Error(payload.message ?? "No pudimos detener el tracking manual.");
    }

    const wasActive = payload.data?.wasActive ?? false;
    if (wasActive) {
      await showHUD("✓ Tracking manual detenido", {
        clearRootSearch: true,
        popToRootType: PopToRootType.Immediate,
      });
      return;
    }

    await showToast({
      style: Toast.Style.Success,
      title: "Tracking manual ya estaba detenido",
    });
    await popToRoot({ clearSearchBar: true });
  } catch (error) {
    await showToast({
      style: Toast.Style.Failure,
      title: "No pudimos detener tracking manual",
      message: error instanceof Error ? error.message : "Error desconocido",
    });
  }
}
