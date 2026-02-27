import {
  Action,
  ActionPanel,
  Detail,
  Icon,
  List,
  LocalStorage,
  Toast,
  closeMainWindow,
  popToRoot,
  showToast,
} from "@raycast/api";
import { useEffect, useState } from "react";
import { copy } from "./copy";
import { PairingForm } from "./components/PairingForm";
import { isCommandSupported, openMomentumApp, openMomentumSettings, postMomentumCommand } from "./momentum";

const TOKEN_KEY = "momentum.token";

type Project = {
  id: string;
  name: string;
  colorHex: string;
  iconName: string;
};

export default function Command() {
  const [token, setToken] = useState<string | null>(null);
  const [projects, setProjects] = useState<Project[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [needsPairing, setNeedsPairing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void bootstrap();
  }, []);

  async function bootstrap() {
    setIsLoading(true);
    const stored = (await LocalStorage.getItem<string>(TOKEN_KEY)) ?? null;
    if (!stored) {
      setNeedsPairing(true);
      setIsLoading(false);
      return;
    }

    setToken(stored);
    await fetchProjects(stored);
  }

  async function fetchProjects(activeToken: string) {
    setIsLoading(true);
    setError(null);
    try {
      const { response, payload } = await postMomentumCommand<Project[]>(activeToken, {
        action: "projects.list",
        apiVersion: 1,
      });

      if (!response.ok || !payload.ok) {
        if (response.status === 401) {
          await LocalStorage.removeItem(TOKEN_KEY);
          setToken(null);
          setNeedsPairing(true);
          setError(copy.pairAgainFromListProjects);
          return;
        }
        throw new Error(payload.message ?? "Couldn't read projects.");
      }

      setProjects(payload.data ?? []);
    } catch (fetchError) {
      setError(fetchError instanceof Error ? fetchError.message : copy.cannotReachMomentum);
    } finally {
      setIsLoading(false);
    }
  }

  async function handlePaired(newToken: string) {
    await LocalStorage.setItem(TOKEN_KEY, newToken);
    setToken(newToken);
    setNeedsPairing(false);
    setError(null);
    await fetchProjects(newToken);
  }

  async function openMomentumFromAction() {
    await closeMainWindow();
    await openMomentumApp();
  }

  async function openMomentumSettingsFromAction() {
    await closeMainWindow();
    await openMomentumSettings();
  }

  async function openProjectFromAction(project: Project) {
    if (!token) {
      setNeedsPairing(true);
      return;
    }

    try {
      const support = await isCommandSupported("project.open");
      if (support === "unsupported") {
        await showToast({
          style: Toast.Style.Failure,
          title: copy.unsupportedCommandTitle,
          message: copy.unsupportedOpenProjectMessage,
        });
        return;
      }

      const { response, payload } = await postMomentumCommand<Record<string, never>>(token, {
        action: "project.open",
        apiVersion: 1,
        payload: {
          projectId: project.id,
          projectName: project.name,
        },
      });

      if (!response.ok || !payload.ok) {
        if (response.status === 401) {
          await LocalStorage.removeItem(TOKEN_KEY);
          setToken(null);
          setNeedsPairing(true);
          await showToast({
            style: Toast.Style.Failure,
            title: copy.invalidTokenTitle,
            message: "Pair again to open projects.",
          });
          return;
        }

        if (payload.error === "UnsupportedAction") {
          throw new Error("The open app does not support this command. Open the latest Momentum build.");
        }

        throw new Error(payload.message ?? "Couldn't open the project.");
      }

      await popToRoot({ clearSearchBar: true });
      await closeMainWindow({ clearRootSearch: true });
    } catch (openError) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't open project",
        message: openError instanceof Error ? openError.message : copy.unknownError,
      });
    }
  }

  if (needsPairing) {
    return <PairingForm onPaired={handlePaired} error={error} />;
  }

  if (error && !isLoading && projects.length === 0) {
    return (
      <Detail
        markdown={["## Couldn't connect to Momentum", error, "", copy.installOrOpenMomentumHint].join("\n")}
        actions={
          <ActionPanel>
            <Action title="Retry" onAction={() => token && fetchProjects(token)} />
            <Action title="Open Momentum" onAction={openMomentumFromAction} icon={Icon.AppWindow} />
            <Action title="Open Momentum Settings" onAction={openMomentumSettingsFromAction} icon={Icon.Gear} />
          </ActionPanel>
        }
      />
    );
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Search projects...">
      {projects.map((project) => (
        <List.Item
          key={project.id}
          title={project.name}
          subtitle={project.iconName}
          icon={Icon.Folder}
          actions={
            <ActionPanel>
              <Action
                title="Open Project in Momentum"
                onAction={() => openProjectFromAction(project)}
                icon={Icon.AppWindow}
              />
              <Action title="Open Momentum" onAction={openMomentumFromAction} icon={Icon.AppWindow} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
