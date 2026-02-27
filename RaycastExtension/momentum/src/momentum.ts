import { Toast, showToast } from "@raycast/api";
import { execFile } from "child_process";
import { promisify } from "util";
import { copy } from "./copy";

const API_BASE = "http://127.0.0.1:51637";
const COMMAND_BASE_CANDIDATES = Array.from(new Set([API_BASE, "http://127.0.0.1:51638"]));
const API_BASE_CANDIDATES = COMMAND_BASE_CANDIDATES;
const RELEASE_BUNDLE_ID = "miguelgarglez.Momentum";
const DEV_BUNDLE_ID = "miguelgarglez.Momentum.dev";
const MOMENTUM_BUNDLE_IDS_BY_PRIORITY = [RELEASE_BUNDLE_ID, DEV_BUNDLE_ID];
const execFileAsync = promisify(execFile);
let openSettingsInFlight = false;
let openAppInFlight = false;
const CAPABILITIES_CACHE_TTL_MS = 15_000;
let cachedCapabilities: { value: MomentumCapabilities | null; expiresAt: number } | null = null;

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

type HealthPayload = {
  apiVersion: number;
  capabilities?: {
    supportedCommandActions?: string[];
    requiresPairing?: boolean;
  };
};

type MomentumCapabilities = {
  apiVersion: number;
  supportedCommandActions: string[];
  requiresPairing: boolean;
};

type LaunchOutcome = "launched" | "not-installed" | "launch-failed";

type ServerRecoveryOutcome = "ready" | "not-installed" | "unreachable";

type CommandAttemptResult<T> = {
  success: CommandEnvelope<T> | null;
  fallbackUnauthorized: CommandEnvelope<T> | null;
  fallbackUnsupported: CommandEnvelope<T> | null;
  lastFailure: Error | null;
  hadResponse: boolean;
};

type PairingAttemptResult = {
  token: string | null;
  lastMessage: string | null;
  lastFailure: Error | null;
  hadResponse: boolean;
};

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function asError(error: unknown): Error {
  return error instanceof Error ? error : new Error(copy.cannotReachMomentum);
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

async function isBundleRunning(bundleId: string): Promise<boolean> {
  if (process.platform !== "darwin") {
    return false;
  }

  try {
    const { stdout } = await execFileAsync("/usr/bin/osascript", [
      "-e",
      `if application id "${bundleId}" is running then return "running"`,
    ]);
    return stdout.trim() === "running";
  } catch {
    return false;
  }
}

async function isBundleInstalled(bundleId: string): Promise<boolean> {
  if (process.platform !== "darwin") {
    return false;
  }

  try {
    const { stdout } = await execFileAsync("/usr/bin/osascript", [
      "-e",
      `set appId to "${bundleId}"`,
      "-e",
      "try",
      "-e",
      "id of application id appId",
      "-e",
      "on error",
      "-e",
      'return ""',
      "-e",
      "end try",
    ]);
    return stdout.trim() === bundleId;
  } catch {
    return false;
  }
}

async function resolveLaunchBundleOrder(): Promise<string[]> {
  const runningBundleIds: string[] = [];
  for (const bundleId of MOMENTUM_BUNDLE_IDS_BY_PRIORITY) {
    if (await isBundleRunning(bundleId)) {
      runningBundleIds.push(bundleId);
    }
  }

  if (runningBundleIds.length === 0) {
    return [...MOMENTUM_BUNDLE_IDS_BY_PRIORITY];
  }

  return [
    ...runningBundleIds,
    ...MOMENTUM_BUNDLE_IDS_BY_PRIORITY.filter((bundleId) => !runningBundleIds.includes(bundleId)),
  ];
}

async function launchMomentum(): Promise<LaunchOutcome> {
  const bundleIds = await resolveLaunchBundleOrder();
  let installedBundleDetected = false;

  for (const bundleId of bundleIds) {
    const isInstalled = await isBundleInstalled(bundleId);
    if (!isInstalled) {
      continue;
    }

    installedBundleDetected = true;
    try {
      await execFileAsync("/usr/bin/open", ["-b", bundleId]);
      return "launched";
    } catch {
      // Try next bundle id.
    }
  }

  try {
    await execFileAsync("/usr/bin/open", ["-a", "Momentum"]);
    return "launched";
  } catch {
    return installedBundleDetected ? "launch-failed" : "not-installed";
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

async function recoverServerReachability(): Promise<ServerRecoveryOutcome> {
  if (await pingServer()) {
    return "ready";
  }

  const launchOutcome = await launchMomentum();
  if (launchOutcome === "not-installed") {
    return "not-installed";
  }

  if (await waitForServerReady()) {
    return "ready";
  }

  return "unreachable";
}

async function attemptConfirmPairing(code: string): Promise<PairingAttemptResult> {
  let lastMessage: string | null = null;
  let lastFailure: Error | null = null;
  let hadResponse = false;

  for (const baseURL of API_BASE_CANDIDATES) {
    try {
      const response = await fetch(`${baseURL}/v1/pairing/confirm`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ code, clientName: "Raycast", apiVersion: 1 }),
      });

      const payload = (await response.json()) as Envelope<{ token: string }>;
      hadResponse = true;
      if (response.ok && payload.ok && payload.data?.token) {
        return { token: payload.data.token, lastMessage, lastFailure, hadResponse };
      }

      lastMessage = payload.message ?? "Invalid or expired code.";
    } catch (error) {
      lastFailure = asError(error);
    }
  }

  return {
    token: null,
    lastMessage,
    lastFailure,
    hadResponse,
  };
}

export async function confirmPairing(code: string): Promise<string> {
  const trimmed = code.trim();
  const firstAttempt = await attemptConfirmPairing(trimmed);
  if (firstAttempt.token) {
    return firstAttempt.token;
  }

  if (firstAttempt.lastMessage) {
    throw new Error(firstAttempt.lastMessage);
  }

  if (!firstAttempt.hadResponse) {
    const recovery = await recoverServerReachability();
    if (recovery === "not-installed") {
      throw new Error(copy.momentumNotInstalledMessage);
    }
    if (recovery === "unreachable") {
      throw new Error(copy.momentumApiUnavailableMessage);
    }

    const secondAttempt = await attemptConfirmPairing(trimmed);
    if (secondAttempt.token) {
      return secondAttempt.token;
    }
    if (secondAttempt.lastMessage) {
      throw new Error(secondAttempt.lastMessage);
    }

    throw secondAttempt.lastFailure ?? new Error(copy.cannotReachMomentum);
  }

  throw firstAttempt.lastFailure ?? new Error(copy.cannotReachMomentum);
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

    const launchOutcome = await launchMomentum();
    if (launchOutcome === "not-installed") {
      await showToast({
        style: Toast.Style.Failure,
        title: copy.momentumRequiredTitle,
        message: copy.momentumNotInstalledMessage,
      });
      return;
    }

    if (await waitForServerReady()) {
      if (await requestOpenSettings()) {
        return;
      }
    }

    if (launchOutcome === "launch-failed") {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't open Momentum",
        message: copy.openMomentumManuallyMessage,
      });
      return;
    }

    await showToast({
      style: Toast.Style.Failure,
      title: copy.momentumApiUnavailableTitle,
      message: copy.momentumApiUnavailableMessage,
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

    const launchOutcome = await launchMomentum();
    if (launchOutcome === "not-installed") {
      await showToast({
        style: Toast.Style.Failure,
        title: copy.momentumRequiredTitle,
        message: copy.momentumNotInstalledMessage,
      });
      return;
    }

    if (launchOutcome === "launch-failed") {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't open Momentum",
        message: copy.openMomentumManuallyMessage,
      });
      return;
    }

    if (await waitForServerReady()) {
      if (await requestOpenApp()) {
        return;
      }
    }

    // Momentum was launched successfully. If the API is unavailable,
    // avoid false failures: opening the app itself is the main intent.
    return;
  } finally {
    openAppInFlight = false;
  }
}

async function attemptPostMomentumCommand<T>(
  activeToken: string,
  body: Record<string, unknown>,
): Promise<CommandAttemptResult<T>> {
  let fallbackUnauthorized: CommandEnvelope<T> | null = null;
  let fallbackUnsupported: CommandEnvelope<T> | null = null;
  let lastFailure: Error | null = null;
  let hadResponse = false;

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
      hadResponse = true;

      if (response.status === 401) {
        fallbackUnauthorized = attempt;
        continue;
      }
      if (response.status === 422 && payload.error === "UnsupportedAction") {
        fallbackUnsupported = attempt;
        continue;
      }
      return {
        success: attempt,
        fallbackUnauthorized,
        fallbackUnsupported,
        lastFailure,
        hadResponse,
      };
    } catch (error) {
      lastFailure = asError(error);
    }
  }

  return {
    success: null,
    fallbackUnauthorized,
    fallbackUnsupported,
    lastFailure,
    hadResponse,
  };
}

export async function postMomentumCommand<T>(
  activeToken: string,
  body: Record<string, unknown>,
): Promise<CommandEnvelope<T>> {
  const firstAttempt = await attemptPostMomentumCommand<T>(activeToken, body);

  if (firstAttempt.success) {
    return firstAttempt.success;
  }
  if (firstAttempt.fallbackUnauthorized) {
    return firstAttempt.fallbackUnauthorized;
  }
  if (firstAttempt.fallbackUnsupported) {
    return firstAttempt.fallbackUnsupported;
  }

  if (!firstAttempt.hadResponse) {
    const recovery = await recoverServerReachability();
    if (recovery === "not-installed") {
      throw new Error(copy.momentumNotInstalledMessage);
    }
    if (recovery === "unreachable") {
      throw new Error(copy.momentumApiUnavailableMessage);
    }

    const secondAttempt = await attemptPostMomentumCommand<T>(activeToken, body);
    if (secondAttempt.success) {
      return secondAttempt.success;
    }
    if (secondAttempt.fallbackUnauthorized) {
      return secondAttempt.fallbackUnauthorized;
    }
    if (secondAttempt.fallbackUnsupported) {
      return secondAttempt.fallbackUnsupported;
    }

    throw secondAttempt.lastFailure ?? new Error(copy.cannotReachMomentum);
  }

  throw firstAttempt.lastFailure ?? new Error(copy.cannotReachMomentum);
}

export async function getMomentumCapabilities(options?: { force?: boolean }): Promise<MomentumCapabilities | null> {
  const force = options?.force ?? false;
  const now = Date.now();

  if (!force && cachedCapabilities && cachedCapabilities.expiresAt > now) {
    return cachedCapabilities.value;
  }

  for (const baseURL of API_BASE_CANDIDATES) {
    try {
      const response = await fetch(`${baseURL}/health`);
      if (!response.ok) {
        continue;
      }

      const payload = (await response.json()) as Envelope<HealthPayload>;
      if (!payload.ok || !payload.data) {
        continue;
      }

      const value: MomentumCapabilities = {
        apiVersion: payload.data.apiVersion ?? 1,
        supportedCommandActions: payload.data.capabilities?.supportedCommandActions ?? [],
        requiresPairing: payload.data.capabilities?.requiresPairing ?? true,
      };
      cachedCapabilities = {
        value,
        expiresAt: now + CAPABILITIES_CACHE_TTL_MS,
      };
      return value;
    } catch {
      // Try next port.
    }
  }

  cachedCapabilities = {
    value: null,
    expiresAt: now + CAPABILITIES_CACHE_TTL_MS,
  };
  return null;
}

export async function isCommandSupported(
  action: string,
  options?: { force?: boolean },
): Promise<"supported" | "unsupported" | "unknown"> {
  const capabilities = await getMomentumCapabilities(options);
  if (!capabilities) {
    return "unknown";
  }
  if (capabilities.supportedCommandActions.length == 0) {
    return "unknown";
  }
  return capabilities.supportedCommandActions.includes(action) ? "supported" : "unsupported";
}

export type { Envelope, MomentumCapabilities };
