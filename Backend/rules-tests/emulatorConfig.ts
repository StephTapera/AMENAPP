type HostPort = {
  host: string;
  port: number;
};

function parseHostPort(value: string | undefined, fallbackPort: number): HostPort {
  if (!value) {
    return { host: "127.0.0.1", port: fallbackPort };
  }

  const normalized = value.replace(/^https?:\/\//, "");
  const [host, portText] = normalized.split(":");
  const port = Number(portText);

  return {
    host: host || "127.0.0.1",
    port: Number.isFinite(port) ? port : fallbackPort,
  };
}

export const firestoreEmulator = parseHostPort(process.env.FIRESTORE_EMULATOR_HOST, 8080);
export const authEmulator = parseHostPort(process.env.FIREBASE_AUTH_EMULATOR_HOST, 9099);
export const storageEmulator = parseHostPort(process.env.FIREBASE_STORAGE_EMULATOR_HOST, 9199);
export const databaseEmulator = parseHostPort(process.env.FIREBASE_DATABASE_EMULATOR_HOST, 9000);

export function databaseUrl(projectId: string): string {
  return `http://${databaseEmulator.host}:${databaseEmulator.port}?ns=${projectId}`;
}

