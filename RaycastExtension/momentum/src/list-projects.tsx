import {
  Action,
  ActionPanel,
  Clipboard,
  popToRoot,
  closeMainWindow,
  Detail,
  Form,
  Icon,
  List,
  LocalStorage,
  Toast,
  showToast,
} from "@raycast/api";
import { useEffect, useMemo, useState } from "react";
import { Envelope, isCommandSupported, openMomentumApp, openMomentumSettings, postMomentumCommand } from "./momentum";
import { copy } from "./copy";

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
          setError("Invalid token. Pair again.");
          return;
        }
        throw new Error(payload.message ?? "Couldn't read projects.");
      }
      setProjects(payload.data ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : copy.cannotReachMomentum);
    } finally {
      setIsLoading(false);
    }
  }

  async function handlePaired(newToken: string) {
    await LocalStorage.setItem(TOKEN_KEY, newToken);
    setToken(newToken);
    setNeedsPairing(false);
    await fetchProjects(newToken);
  }

  async function openMomentumFromAction() {
    await closeMainWindow();
    await openMomentumApp();
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
    } catch (err) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't open project",
        message: err instanceof Error ? err.message : copy.unknownError,
      });
    }
  }

  if (needsPairing) {
    return <PairingView onPaired={handlePaired} error={error} />;
  }

  if (error && !isLoading && projects.length === 0) {
    return (
      <Detail
        markdown={[
          "## Couldn't connect to Momentum",
          error,
          "",
          "Make sure Momentum is running and Raycast integration is enabled.",
        ].join("\n")}
        actions={
          <ActionPanel>
            <Action title="Retry" onAction={() => token && fetchProjects(token)} />
            <Action.OpenInBrowser
              title="Open Documentation"
              url="https://developers.raycast.com/basics/create-your-first-extension"
            />
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

function PairingView({ onPaired, error }: { onPaired: (token: string) => Promise<void>; error: string | null }) {
  const [code, setCode] = useState("");
  const trimmed = useMemo(() => code.trim(), [code]);
  const validationError = trimmed.length > 0 && trimmed.length !== 4 ? "Enter 4 digits." : undefined;

  async function handleSubmit() {
    if (trimmed.length !== 4) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Invalid code",
        message: "Enter a 4-digit code.",
      });
      return;
    }
    try {
      const response = await fetch(`${API_BASE}/v1/pairing/confirm`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ code: trimmed, clientName: "Raycast", apiVersion: 1 }),
      });
      const payload = (await response.json()) as Envelope<{ token: string }>;
      if (!response.ok || !payload.ok || !payload.data?.token) {
        throw new Error(payload.message ?? "Invalid or expired code.");
      }
      await onPaired(payload.data.token);
      await showToast({ style: Toast.Style.Success, title: "Raycast paired" });
    } catch (err) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't pair",
        message: err instanceof Error ? err.message : copy.unknownError,
      });
    }
  }

  function applyDigits(value: string) {
    const parsed = value.replace(/\D/g, "").slice(0, 4);
    setCode(parsed);
  }

  async function pasteFromClipboard() {
    const text = await Clipboard.readText();
    if (!text) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Clipboard is empty",
        message: "Copy the code from Momentum and try again.",
      });
      return;
    }
    const digits = text.replace(/\D/g, "");
    if (digits.length < 4) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Incomplete code",
        message: "Couldn't find 4 digits in the clipboard.",
      });
      return;
    }
    applyDigits(digits);
  }

  async function openSettingsFromAction() {
    await closeMainWindow();
    await openMomentumSettings();
  }

  return (
    <Form
      actions={
        <ActionPanel>
          <Action title="Get Code" onAction={openSettingsFromAction} icon={Icon.Gear} />
          <Action title="Paste Code" onAction={pasteFromClipboard} icon={Icon.Clipboard} />
          <Action.SubmitForm title="Pair" onSubmit={handleSubmit} icon={Icon.Link} />
        </ActionPanel>
      }
    >
      <Form.Description
        text={[
          "Open Momentum > Settings > Raycast Extension and generate a code.",
          "Enter the 4-digit code here to pair.",
          "Actions (Cmd+K): Paste code · Get code",
        ].join("\n")}
      />
      <Form.TextField
        id="pairingCode"
        title="Code"
        value={trimmed}
        onChange={(value) => applyDigits(value)}
        placeholder="XXXX"
        error={validationError}
      />
      {error ? <Form.Description text={error} /> : null}
    </Form>
  );
}
