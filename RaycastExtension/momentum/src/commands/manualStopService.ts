import { isCommandSupported, postMomentumCommand } from "../momentum";

type PostMomentumCommand = typeof postMomentumCommand;
type SupportsCommand = typeof isCommandSupported;

type ManualStopResponse = {
  wasActive: boolean;
};

export type ManualStopResult =
  | { kind: "ok"; wasActive: boolean }
  | { kind: "unauthorized" }
  | { kind: "unsupported" }
  | { kind: "error"; message: string };

export async function stopManualTracking(
  token: string,
  postCommand: PostMomentumCommand = postMomentumCommand,
  supportsCommand: SupportsCommand = isCommandSupported,
): Promise<ManualStopResult> {
  const support = await supportsCommand("manual.stop");
  if (support === "unsupported") {
    return { kind: "unsupported" };
  }

  const { response, payload } = await postCommand<ManualStopResponse>(token, {
    action: "manual.stop",
    apiVersion: 1,
  });

  if (response.status === 401) {
    return { kind: "unauthorized" };
  }

  if (!response.ok || !payload.ok) {
    if (payload.error === "UnsupportedAction") {
      return { kind: "unsupported" };
    }
    return { kind: "error", message: payload.message ?? "Couldn't stop manual tracking." };
  }

  return {
    kind: "ok",
    wasActive: payload.data?.wasActive ?? false,
  };
}
