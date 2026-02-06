import { Toast, showToast } from "@raycast/api";
import { execFile } from "child_process";
import { promisify } from "util";

const API_BASE = "http://127.0.0.1:51637";
const COMMAND_BASE_CANDIDATES = Array.from(new Set([API_BASE, "http://127.0.0.1:51638"]));
const API_BASE_CANDIDATES = COMMAND_BASE_CANDIDATES;
const MOMENTUM_BUNDLE_IDS = ["miguelgarglez.Momentum.dev", "miguelgarglez.Momentum"];
const execFileAsync = promisify(execFile);
let openSettingsInFlight = false;
let openAppInFlight = false;

type Envelope<T> = {
  ok: boolean;
  data?: T;
  error?: string;
  message?: string;
};

type CommandEnvelope<T> = {
  response: Response;
  payload: Envelope<T>;
};

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function requestOpenSettings(): Promise<boolean> {
  for (const baseURL of API_BASE_CANDIDATES) {
    try {
      const response = await fetch(`${baseURL}/v1/settings/open`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ section: "raycast", apiVersion: 1 }),
      });
      const payload = (await response.json()) as Envelope<unknown>;
      if (response.ok && payload.ok) {
        return true;
      }
    } catch {
      // Try next port.
    }
  }
  return false;
}

async function requestOpenApp(): Promise<boolean> {
  for (const baseURL of API_BASE_CANDIDATES) {
    try {
      const response = await fetch(`${baseURL}/v1/app/open`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ apiVersion: 1 }),
      });
      const payload = (await response.json()) as Envelope<unknown>;
      if (response.ok && payload.ok) {
        return true;
      }
    } catch {
      // Try next port.
    }
  }
  return false;
}

async function pingServer(): Promise<boolean> {
  for (const baseURL of API_BASE_CANDIDATES) {
    try {
      const response = await fetch(`${baseURL}/health`);
      if (response.ok) {
        return true;
      }
    } catch {
      // Try next port.
    }
  }
  return false;
}

async function launchMomentum(): Promise<boolean> {
  for (const bundleId of MOMENTUM_BUNDLE_IDS) {
    try {
      await execFileAsync("/usr/bin/open", ["-b", bundleId]);
      return true;
    } catch {
      // Try next bundle id.
    }
  }
  try {
    await execFileAsync("/usr/bin/open", ["-a", "Momentum"]);
    return true;
  } catch {
    return false;
  }
}

async function waitForServerReady(): Promise<boolean> {
  for (let attempt = 0; attempt < 24; attempt += 1) {
    await sleep(350);
    if (await pingServer()) {
      return true;
    }
  }
  return false;
}

export async function openMomentumSettings(): Promise<void> {
  if (openSettingsInFlight) {
    return;
  }
  openSettingsInFlight = true;
  try {
    if (await requestOpenSettings()) {
      return;
    }

    const launched = await launchMomentum();
    if (!launched) {
      await showToast({
        style: Toast.Style.Failure,
        title: "No pudimos abrir Momentum",
        message: "Abre la app manualmente y vuelve a intentarlo.",
      });
      return;
    }

    if (await waitForServerReady()) {
      if (await requestOpenSettings()) {
        return;
      }
    }

    await showToast({
      style: Toast.Style.Failure,
      title: "No pudimos abrir Ajustes",
      message: "Abre Momentum manualmente para continuar.",
    });
  } finally {
    openSettingsInFlight = false;
  }
}

export async function openMomentumApp(): Promise<void> {
  if (openAppInFlight) {
    return;
  }
  openAppInFlight = true;
  try {
    if (await requestOpenApp()) {
      return;
    }

    const launched = await launchMomentum();
    if (!launched) {
      await showToast({
        style: Toast.Style.Failure,
        title: "No pudimos abrir Momentum",
        message: "Abre la app manualmente y vuelve a intentarlo.",
      });
      return;
    }

    if (await waitForServerReady()) {
      if (await requestOpenApp()) {
        return;
      }
    }
    // At this point Momentum was launched successfully, but the local API
    // might be disabled/unavailable (e.g. integration off or older build).
    // Treat it as success to avoid a false failure toast.
    return;
  } finally {
    openAppInFlight = false;
  }
}

export async function postMomentumCommand<T>(
  activeToken: string,
  body: Record<string, unknown>,
): Promise<CommandEnvelope<T>> {
  let fallbackUnauthorized: CommandEnvelope<T> | null = null;
  let fallbackUnsupported: CommandEnvelope<T> | null = null;
  let lastFailure: Error | null = null;

  for (const baseURL of COMMAND_BASE_CANDIDATES) {
    try {
      const response = await fetch(`${baseURL}/v1/commands`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${activeToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
      const payload = (await response.json()) as Envelope<T>;
      const attempt = { response, payload };

      if (response.status === 401) {
        fallbackUnauthorized = attempt;
        continue;
      }
      if (response.status === 422 && payload.error === "UnsupportedAction") {
        fallbackUnsupported = attempt;
        continue;
      }
      return attempt;
    } catch (error) {
      lastFailure = error instanceof Error ? error : new Error("No pudimos contactar con Momentum.");
    }
  }

  if (fallbackUnauthorized) {
    return fallbackUnauthorized;
  }
  if (fallbackUnsupported) {
    return fallbackUnsupported;
  }
  throw lastFailure ?? new Error("No pudimos contactar con Momentum.");
}

export { API_BASE, Envelope };
