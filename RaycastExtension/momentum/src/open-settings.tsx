import { closeMainWindow, showToast, Toast } from "@raycast/api";
import { openMomentumSettings } from "./momentum";

export default async function Command() {
  await closeMainWindow();
  await showToast({ style: Toast.Style.Animated, title: "Abriendo ajustes…" });
  await openMomentumSettings();
}
