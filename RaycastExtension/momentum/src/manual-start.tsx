import {
  Action,
  ActionPanel,
  Form,
  Icon,
  LocalStorage,
  Toast,
  closeMainWindow,
  popToRoot,
  showHUD,
  showToast,
} from "@raycast/api";
import { useEffect, useMemo, useState } from "react";
import {
  loadManualStartProjects,
  ManualStartProject,
  openManualStartForm,
  startManualTrackingExisting,
} from "./commands/manualStartService";
import { PairingForm } from "./components/PairingForm";
import { copy } from "./copy";

const TOKEN_KEY = "momentum.token";

type StartMode = "existing" | "new";

export default function Command() {
  const [token, setToken] = useState<string | null>(null);
  const [projects, setProjects] = useState<ManualStartProject[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [pairingRequired, setPairingRequired] = useState(false);
  const [pairingError, setPairingError] = useState<string | null>(null);
  const [mode, setMode] = useState<StartMode>("existing");
  const [projectId, setProjectId] = useState("");

  useEffect(() => {
    void bootstrap();
  }, []);

  async function bootstrap() {
    setIsLoading(true);
    const stored = (await LocalStorage.getItem<string>(TOKEN_KEY)) ?? null;
    if (!stored) {
      setPairingRequired(true);
      setIsLoading(false);
      return;
    }

    setToken(stored);
    await fetchProjects(stored);
  }

  async function fetchProjects(activeToken: string) {
    setIsLoading(true);
    try {
      const result = await loadManualStartProjects(activeToken);
      if (result.kind == "unauthorized") {
        await LocalStorage.removeItem(TOKEN_KEY);
        setPairingRequired(true);
        setPairingError(copy.pairAgainFromListProjects);
        setToken(null);
        return;
      }

      if (result.kind == "error") {
        throw new Error(result.message);
      }

      const listedProjects = result.projects;
      setProjects(listedProjects);
      if (listedProjects.length > 0) {
        setProjectId((current) => current || listedProjects[0].id);
      }
    } catch (fetchError) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't load projects",
        message: fetchError instanceof Error ? fetchError.message : copy.unknownError,
      });
    } finally {
      setIsLoading(false);
    }
  }

  async function handlePaired(newToken: string) {
    await LocalStorage.setItem(TOKEN_KEY, newToken);
    setToken(newToken);
    setPairingRequired(false);
    setPairingError(null);
    await fetchProjects(newToken);
  }

  const existingModeDisabled = useMemo(() => projects.length === 0, [projects.length]);

  async function submit() {
    if (!token) {
      setPairingRequired(true);
      return;
    }

    if (mode == "new") {
      await openNativeManualForm(token);
      return;
    }

    if (!projectId) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Select a project",
      });
      return;
    }

    const selectedProject = projects.find((project) => project.id == projectId);
    try {
      const result = await startManualTrackingExisting(token, projectId, selectedProject?.name);
      if (result.kind !== "ok") {
        if (result.kind === "unauthorized") {
          await LocalStorage.removeItem(TOKEN_KEY);
          setPairingRequired(true);
          setPairingError(copy.pairAgainFromListProjects);
          setToken(null);
          await showToast({
            style: Toast.Style.Failure,
            title: copy.invalidTokenTitle,
            message: copy.pairAgainFromListProjects,
          });
          return;
        }

        if (result.kind === "unsupported") {
          throw new Error(copy.unsupportedAppCommandMessage);
        }

        throw new Error(result.message);
      }

      await showToast({
        style: Toast.Style.Success,
        title: "Manual tracking started",
        message: result.project.name,
      });
      await popToRoot({ clearSearchBar: true });
      await closeMainWindow({ clearRootSearch: true });
    } catch (startError) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't start manual tracking",
        message: startError instanceof Error ? startError.message : copy.unknownError,
      });
    }
  }

  async function openNativeManualForm(activeToken: string) {
    try {
      const result = await openManualStartForm(activeToken);
      if (result.kind !== "ok") {
        if (result.kind === "unauthorized") {
          await LocalStorage.removeItem(TOKEN_KEY);
          setPairingRequired(true);
          setPairingError(copy.pairAgainFromListProjects);
          setToken(null);
          await showToast({
            style: Toast.Style.Failure,
            title: copy.invalidTokenTitle,
            message: copy.pairAgainFromListProjects,
          });
          return;
        }

        if (result.kind === "unsupported") {
          throw new Error(copy.unsupportedAppCommandMessage);
        }

        throw new Error(result.message);
      }

      await showHUD("✓ Opening form in Momentum");
      await popToRoot({ clearSearchBar: true });
      await closeMainWindow({ clearRootSearch: true });
    } catch (openError) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't open form",
        message: openError instanceof Error ? openError.message : copy.unknownError,
      });
    }
  }

  if (pairingRequired) {
    return <PairingForm onPaired={handlePaired} error={pairingError} />;
  }

  return (
    <Form
      isLoading={isLoading}
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Start Manual Tracking" onSubmit={submit} icon={Icon.Play} />
          <Action title="Reload Projects" onAction={() => token && fetchProjects(token)} icon={Icon.ArrowClockwise} />
        </ActionPanel>
      }
    >
      <Form.Description text="Use an existing project or open the new-project form in Momentum." />
      <Form.Dropdown id="mode" title="Mode" value={mode} onChange={(value) => setMode(value as StartMode)}>
        <Form.Dropdown.Item value="existing" title="Existing project" />
        <Form.Dropdown.Item value="new" title="Create new project (in app)" />
      </Form.Dropdown>

      {mode == "existing" ? (
        <Form.Dropdown
          id="project"
          title="Project"
          value={projectId}
          onChange={setProjectId}
          error={existingModeDisabled ? "No projects found. Use create-new mode." : undefined}
        >
          {projects.map((project) => (
            <Form.Dropdown.Item key={project.id} value={project.id} title={project.name} icon={Icon.Folder} />
          ))}
        </Form.Dropdown>
      ) : (
        <Form.Description text="On submit, Momentum will open the native manual tracking flow in new-project mode." />
      )}
    </Form>
  );
}
