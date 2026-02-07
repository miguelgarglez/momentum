import { isCommandSupported, postMomentumCommand } from "../momentum";
import { copy } from "../copy";

type PostMomentumCommand = typeof postMomentumCommand;
type SupportsCommand = typeof isCommandSupported;

type ConflictsOpenResponse = {
  conflictsCount: number;
  opened: boolean;
};

export type ResolveConflictsResult =
  | { kind: "opened"; conflictsCount: number }
  | { kind: "no-conflicts" }
  | { kind: "unauthorized" }
  | { kind: "error"; message: string };

export async function resolveConflicts(
  token: string,
  postCommand: PostMomentumCommand = postMomentumCommand,
  supportsCommand: SupportsCommand = isCommandSupported,
): Promise<ResolveConflictsResult> {
  const support = await supportsCommand("conflicts.open");
  if (support === "unsupported") {
    return { kind: "error", message: copy.unsupportedConflictsMessage };
  }

  const { response, payload } = await postCommand<ConflictsOpenResponse>(token, {
    action: "conflicts.open",
    present: true,
    apiVersion: 1,
  });

  if (response.status === 401) {
    return { kind: "unauthorized" };
  }
  if (!response.ok || !payload.ok) {
    return { kind: "error", message: payload.message ?? "Couldn't check pending conflicts." };
  }

  const conflictsCount = payload.data?.conflictsCount ?? 0;
  if (conflictsCount > 0) {
    return { kind: "opened", conflictsCount };
  }

  return { kind: "no-conflicts" };
}
