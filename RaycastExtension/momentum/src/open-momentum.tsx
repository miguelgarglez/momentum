import { closeMainWindow } from "@raycast/api";
import { openMomentumApp } from "./momentum";

export default async function Command() {
  await closeMainWindow();
  await openMomentumApp();
}
