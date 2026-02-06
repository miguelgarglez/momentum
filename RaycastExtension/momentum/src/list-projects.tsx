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
import { Envelope, openMomentumApp, openMomentumSettings, postMomentumCommand } from "./momentum";

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
          setError("Token inválido. Empareja de nuevo.");
          return;
        }
        throw new Error(payload.message ?? "No pudimos leer los proyectos.");
      }
      setProjects(payload.data ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : "No pudimos contactar con Momentum.");
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
            title: "Token inválido",
            message: "Empareja de nuevo para abrir proyectos.",
          });
          return;
        }
        if (payload.error === "UnsupportedAction") {
          throw new Error("La app abierta no soporta este comando. Abre la versión más reciente de Momentum.");
        }
        throw new Error(payload.message ?? "No pudimos abrir el proyecto.");
      }

      await popToRoot({ clearSearchBar: true });
      await closeMainWindow({ clearRootSearch: true });
    } catch (err) {
      await showToast({
        style: Toast.Style.Failure,
        title: "No pudimos abrir el proyecto",
        message: err instanceof Error ? err.message : "Error desconocido",
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
          "## No pudimos conectar con Momentum",
          error,
          "",
          "Asegúrate de que Momentum está abierto y que la integración Raycast está activada.",
        ].join("\n")}
        actions={
          <ActionPanel>
            <Action title="Reintentar" onAction={() => token && fetchProjects(token)} />
            <Action.OpenInBrowser
              title="Abrir documentación"
              url="https://developers.raycast.com/basics/create-your-first-extension"
            />
          </ActionPanel>
        }
      />
    );
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Buscar proyectos…">
      {projects.map((project) => (
        <List.Item
          key={project.id}
          title={project.name}
          subtitle={project.iconName}
          icon={Icon.Folder}
          actions={
            <ActionPanel>
              <Action
                title="Abrir proyecto en Momentum"
                onAction={() => openProjectFromAction(project)}
                icon={Icon.AppWindow}
              />
              <Action title="Abrir Momentum" onAction={openMomentumFromAction} icon={Icon.AppWindow} />
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
  const validationError = trimmed.length > 0 && trimmed.length !== 4 ? "Introduce 4 dígitos." : undefined;

  async function handleSubmit() {
    if (trimmed.length !== 4) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Código inválido",
        message: "Introduce un código de 4 dígitos.",
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
        throw new Error(payload.message ?? "Código inválido o expirado.");
      }
      await onPaired(payload.data.token);
      await showToast({ style: Toast.Style.Success, title: "Raycast emparejado" });
    } catch (err) {
      await showToast({
        style: Toast.Style.Failure,
        title: "No pudimos emparejar",
        message: err instanceof Error ? err.message : "Error desconocido",
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
        title: "Portapapeles vacío",
        message: "Copia el código desde Momentum y vuelve a intentar.",
      });
      return;
    }
    const digits = text.replace(/\D/g, "");
    if (digits.length < 4) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Código incompleto",
        message: "No encontramos 4 dígitos en el portapapeles.",
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
          <Action title="Obtener código" onAction={openSettingsFromAction} icon={Icon.Gear} />
          <Action title="Pegar código" onAction={pasteFromClipboard} icon={Icon.Clipboard} />
          <Action.SubmitForm title="Emparejar" onSubmit={handleSubmit} icon={Icon.Link} />
        </ActionPanel>
      }
    >
      <Form.Description
        text={[
          "Abre Momentum > Ajustes > Raycast Extension y genera un código.",
          "Introduce aquí el código de 4 dígitos para emparejar.",
          "Acciones (Cmd+K): Pegar código · Obtener código",
        ].join("\n")}
      />
      <Form.TextField
        id="pairingCode"
        title="Código"
        value={trimmed}
        onChange={(value) => applyDigits(value)}
        placeholder="XXXX"
        error={validationError}
      />
      {error ? <Form.Description text={error} /> : null}
    </Form>
  );
}
