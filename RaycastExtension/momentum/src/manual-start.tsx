import {
  Action,
  ActionPanel,
  Detail,
  Form,
  Icon,
  LaunchType,
  LocalStorage,
  closeMainWindow,
  launchCommand,
  popToRoot,
  showHUD,
  showToast,
  Toast,
} from "@raycast/api";
import { useEffect, useMemo, useState } from "react";
import { postMomentumCommand } from "./momentum";

const TOKEN_KEY = "momentum.token";

type Project = {
  id: string;
  name: string;
  colorHex: string;
  iconName: string;
};

type ManualStartResponse = {
  project: Project;
};

type StartMode = "existing" | "new";
export default function Command() {
  const [token, setToken] = useState<string | null>(null);
  const [projects, setProjects] = useState<Project[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [pairingRequired, setPairingRequired] = useState(false);
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
      const { response, payload } = await postMomentumCommand<Project[]>(activeToken, {
        action: "projects.list",
        apiVersion: 1,
      });
      if (!response.ok || !payload.ok) {
        if (response.status === 401) {
          await LocalStorage.removeItem(TOKEN_KEY);
          setPairingRequired(true);
          setToken(null);
          return;
        }
        throw new Error(payload.message ?? "No pudimos leer los proyectos.");
      }

      const listedProjects = payload.data ?? [];
      setProjects(listedProjects);
      if (listedProjects.length > 0) {
        setProjectId((current) => current || listedProjects[0].id);
      }
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "No pudimos cargar proyectos",
        message: error instanceof Error ? error.message : "Error desconocido",
      });
    } finally {
      setIsLoading(false);
    }
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
        title: "Selecciona un proyecto",
      });
      return;
    }

    const selectedProject = projects.find((project) => project.id == projectId);
    try {
      const { response, payload } = await postMomentumCommand<ManualStartResponse>(token, {
        action: "manual.start",
        apiVersion: 1,
        payload: {
          projectId,
          projectName: selectedProject?.name,
        },
      });
      if (!response.ok || !payload.ok || !payload.data?.project) {
        if (response.status === 401) {
          await LocalStorage.removeItem(TOKEN_KEY);
          setPairingRequired(true);
          setToken(null);
          await showToast({
            style: Toast.Style.Failure,
            title: "Token inválido",
            message: "Empareja de nuevo desde List projects.",
          });
          return;
        }
        if (payload.error === "UnsupportedAction") {
          throw new Error(
            "La app abierta no soporta este comando. Cierra Momentum release, abre la versión dev y vuelve a emparejar.",
          );
        }
        throw new Error(payload.message ?? "No pudimos iniciar el tracking manual.");
      }

      await showToast({
        style: Toast.Style.Success,
        title: "Tracking manual iniciado",
        message: payload.data.project.name,
      });
      await popToRoot({ clearSearchBar: true });
      await closeMainWindow({ clearRootSearch: true });
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "No pudimos iniciar tracking manual",
        message: error instanceof Error ? error.message : "Error desconocido",
      });
    }
  }

  async function openNativeManualForm(activeToken: string) {
    try {
      const { response, payload } = await postMomentumCommand<Record<string, never>>(activeToken, {
        action: "manual.open",
        apiVersion: 1,
        payload: {
          mode: "new",
        },
      });
      if (!response.ok || !payload.ok) {
        if (response.status === 401) {
          await LocalStorage.removeItem(TOKEN_KEY);
          setPairingRequired(true);
          setToken(null);
          await showToast({
            style: Toast.Style.Failure,
            title: "Token inválido",
            message: "Empareja de nuevo desde List projects.",
          });
          return;
        }
        if (payload.error === "UnsupportedAction") {
          throw new Error(
            "La app abierta no soporta este comando. Cierra Momentum release, abre la versión dev y vuelve a emparejar.",
          );
        }
        throw new Error(payload.message ?? "No pudimos abrir el formulario en Momentum.");
      }

      await showHUD("✓ Abriendo formulario en Momentum");
      await popToRoot({ clearSearchBar: true });
      await closeMainWindow({ clearRootSearch: true });
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "No pudimos abrir el formulario",
        message: error instanceof Error ? error.message : "Error desconocido",
      });
    }
  }

  if (pairingRequired) {
    return (
      <Detail
        markdown="## Emparejamiento requerido\n\nEmpareja primero la extensión desde `List projects`."
        actions={
          <ActionPanel>
            <Action
              title="Abrir List projects"
              onAction={() => launchCommand({ name: "list-projects", type: LaunchType.UserInitiated })}
            />
          </ActionPanel>
        }
      />
    );
  }

  return (
    <Form
      isLoading={isLoading}
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Iniciar tracking manual" onSubmit={submit} icon={Icon.Play} />
          <Action
            title="Recargar proyectos"
            onAction={() => token && fetchProjects(token)}
            icon={Icon.ArrowClockwise}
          />
        </ActionPanel>
      }
    >
      <Form.Description text="Usa un proyecto existente o abre en Momentum el formulario de proyecto nuevo." />
      <Form.Dropdown id="mode" title="Modo" value={mode} onChange={(value) => setMode(value as StartMode)}>
        <Form.Dropdown.Item value="existing" title="Proyecto existente" />
        <Form.Dropdown.Item value="new" title="Crear proyecto nuevo (en app)" />
      </Form.Dropdown>

      {mode == "existing" ? (
        <Form.Dropdown
          id="project"
          title="Proyecto"
          value={projectId}
          onChange={setProjectId}
          error={existingModeDisabled ? "No hay proyectos. Usa el modo de crear nuevo." : undefined}
        >
          {projects.map((project) => (
            <Form.Dropdown.Item key={project.id} value={project.id} title={project.name} icon={Icon.Folder} />
          ))}
        </Form.Dropdown>
      ) : (
        <Form.Description text="Al confirmar, se abrirá en Momentum el diálogo nativo de tracking manual, directamente en modo proyecto nuevo." />
      )}
    </Form>
  );
}
