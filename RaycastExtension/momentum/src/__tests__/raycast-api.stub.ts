import { vi } from "vitest";

export const Toast = {
  Style: {
    Failure: "failure",
    Success: "success",
    Animated: "animated",
  },
};

export const PopToRootType = {
  Immediate: "immediate",
};

export const LocalStorage = {
  getItem: vi.fn(),
  setItem: vi.fn(),
  removeItem: vi.fn(),
};

export const showToast = vi.fn();
export const showHUD = vi.fn();
export const popToRoot = vi.fn();
export const closeMainWindow = vi.fn();
export const launchCommand = vi.fn();

export const LaunchType = {
  UserInitiated: "userInitiated",
};
