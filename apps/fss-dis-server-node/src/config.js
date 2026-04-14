import dotenv from "dotenv";

dotenv.config();

function parseBool(value, fallback = false) {
  if (value == null || value === "") return fallback;
  return ["1", "true", "yes", "y", "on"].includes(String(value).toLowerCase());
}

function parseNumber(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function splitCsv(value) {
  return String(value || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

export const config = {
  port: parseNumber(process.env.PORT, 3000),
  nodeEnv: process.env.NODE_ENV || "development",
  appName: process.env.APP_NAME || "fss-dis-server-node",
  mongoUri:
    process.env.MONGO_URI ||
    "mongodb://root:CHANGE_ME@mongo.infra.svc.cluster.local:27017/fss_dis?authSource=admin",
  redisUrl:
    process.env.REDIS_URL ||
    "redis://root:CHANGE_ME@redis.infra.svc.cluster.local:6379/0",
  authTokenTtlSeconds: parseNumber(process.env.AUTH_TOKEN_TTL_SECONDS, 8 * 60 * 60),
  authSessionPrefix: process.env.AUTH_SESSION_PREFIX || "fss:auth:session:",
  corsOrigins: splitCsv(process.env.CORS_ORIGINS || "http://localhost:9000"),

  k8sUserNamespace: process.env.K8S_USER_NAMESPACE || "dis",
  k8sAppNamespace: process.env.K8S_APP_NAMESPACE || "app",
  labGovernanceEnabled: parseBool(process.env.LAB_GOVERNANCE_ENABLED, true),

  jupyterImage:
    process.env.JUPYTER_IMAGE || "192.168.56.72/dis/jupter-teradata-fss:latest",
  jupyterAccessMode: process.env.JUPYTER_ACCESS_MODE || "dynamic-route",
  jupyterDynamicHostSuffix:
    process.env.JUPYTER_DYNAMIC_HOST_SUFFIX || "service.jupyter.platform.local",
  jupyterDynamicScheme: process.env.JUPYTER_DYNAMIC_SCHEME || "https",
  jupyterDynamicSubdomain: process.env.JUPYTER_DYNAMIC_SUBDOMAIN || "jupyter-named-pod",
  jupyterToken: process.env.JUPYTER_TOKEN || "CHANGE_ME",
  jupyterWorkspaceRoot: process.env.JUPYTER_WORKSPACE_ROOT || "/workspace/user-home",
  jupyterBootstrapDir: process.env.JUPYTER_BOOTSTRAP_DIR || "/opt/platform/bootstrap-workspace",
  jupyterUserPvcStorageClass: process.env.JUPYTER_USER_PVC_STORAGE_CLASS || "",

  controlPlaneUsername: process.env.CONTROL_PLANE_USERNAME || "admin@test.com",
  controlPlanePassword: process.env.CONTROL_PLANE_PASSWORD || "CHANGE_ME",

  harborRegistry: process.env.HARBOR_REGISTRY || "192.168.56.72",
  harborProject: process.env.HARBOR_PROJECT || "dis",

  frontendUrl: process.env.FRONTEND_URL || "http://dis.platform.local",
  airflowUrl: process.env.AIRFLOW_URL || "",
};

export function isDynamicRouteMode() {
  const mode = String(config.jupyterAccessMode || "dynamic-route").toLowerCase().trim();
  return ["dynamic-route", "dynamic_route", "dynamic", "wildcard"].includes(mode);
}
