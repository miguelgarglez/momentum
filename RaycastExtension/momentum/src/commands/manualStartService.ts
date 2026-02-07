import { isCommandSupported, postMomentumCommand } from "../momentum";

type PostMomentumCommand = typeof postMomentumCommand;
type SupportsCommand = typeof isCommandSupported;

export type ManualStartProject = {
  id: string;
  name: string;
  colorHex: string;
  iconName: string;
};

type ManualStartResponse = {
  project: ManualStartProject;
};

export type ManualStartProjectsResult =
  | { kind: "ok"; projects: ManualStartProject[] }
  | { kind: "unauthorized" }
  | { kind: "error"; message: string };

export type ManualStartExistingResult =
  | { kind: "ok"; project: ManualStartProject }
  | { kind: "unauthorized" }
  | { kind: "unsupported" }
  | { kind: "error"; message: string };

export type ManualOpenResult =
  | { kind: "ok" }
  | { kind: "unauthorized" }
  | { kind: "unsupported" }
  | { kind: "error"; message: string };

export async function loadManualStartProjects(
  token: string,
  postCommand: PostMomentumCommand = postMomentumCommand,
): Promise<ManualStartProjectsResult> {
  const { response, payload } = await postCommand<ManualStartProject[]>(token, {
    action: "projects.list",
    apiVersion: 1,
  });

  if (response.status === 401) {
    return { kind: "unauthorized" };
  }
  if (!response.ok || !payload.ok) {
    return { kind: "error", message: payload.message ?? "Couldn't read projects." };
  }

  return { kind: "ok", projects: payload.data ?? [] };
}

export async function startManualTrackingExisting(
  token: string,
  projectId: string,
  projectName: string | undefined,
  postCommand: PostMomentumCommand = postMomentumCommand,
  supportsCommand: SupportsCommand = isCommandSupported,
): Promise<ManualStartExistingResult> {
  const support = await supportsCommand("manual.start");
  if (support === "unsupported") {
    return { kind: "unsupported" };
  }

  const { response, payload } = await postCommand<ManualStartResponse>(token, {
    action: "manual.start",
    apiVersion: 1,
    payload: {
      projectId,
      projectName,
    },
  });

  if (response.status === 401) {
    return { kind: "unauthorized" };
  }
  if (!response.ok || !payload.ok || !payload.data?.project) {
    if (payload.error === "UnsupportedAction") {
      return { kind: "unsupported" };
    }
    return { kind: "error", message: payload.message ?? "Couldn't start manual tracking." };
  }

  return { kind: "ok", project: payload.data.project };
}

export async function openManualStartForm(
  token: string,
  postCommand: PostMomentumCommand = postMomentumCommand,
  supportsCommand: SupportsCommand = isCommandSupported,
): Promise<ManualOpenResult> {
  const support = await supportsCommand("manual.open");
  if (support === "unsupported") {
    return { kind: "unsupported" };
  }

  const { response, payload } = await postCommand<Record<string, never>>(token, {
    action: "manual.open",
    apiVersion: 1,
    payload: {
      mode: "new",
    },
  });

  if (response.status === 401) {
    return { kind: "unauthorized" };
  }
  if (!response.ok || !payload.ok) {
    if (payload.error === "UnsupportedAction") {
      return { kind: "unsupported" };
    }
    return { kind: "error", message: payload.message ?? "Couldn't open the form in Momentum." };
  }

  return { kind: "ok" };
}
