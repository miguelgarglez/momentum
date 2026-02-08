import { Action, ActionPanel, Clipboard, Form, Icon, Toast, closeMainWindow, showToast } from "@raycast/api";
import { useMemo, useState } from "react";
import { copy } from "../copy";
import { confirmPairing, openMomentumSettings } from "../momentum";

type PairingFormProps = {
  onPaired: (token: string) => Promise<void>;
  error?: string | null;
};

export function PairingForm({ onPaired, error }: PairingFormProps) {
  const [code, setCode] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
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

    setIsSubmitting(true);
    try {
      const token = await confirmPairing(trimmed);
      await onPaired(token);
      await showToast({ style: Toast.Style.Success, title: "Raycast paired" });
    } catch (submitError) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't pair",
        message: submitError instanceof Error ? submitError.message : copy.unknownError,
      });
    } finally {
      setIsSubmitting(false);
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
      isLoading={isSubmitting}
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
        onChange={applyDigits}
        placeholder="XXXX"
        error={validationError}
      />
      {error ? <Form.Description text={error} /> : null}
    </Form>
  );
}
