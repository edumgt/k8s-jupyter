<template>
  <q-layout view="lHh Lpr lFf">
    <q-page-container>
      <q-page class="page-shell">
        <section class="hero-panel">
          <div class="eyebrow">K8s Data Platform OVA</div>
          <h1>사용자 실습과 클러스터 운영을 한 화면에서 보는 Kubernetes 랩</h1>
          <p>
            Quasar frontend에서 사용자별 JupyterLab 세션을 만들고, 같은 화면의 control-plane
            dashboard에서 cluster node와 pod 상태를 로그인 후 확인할 수 있습니다.
          </p>
          <div class="hero-actions">
            <q-btn
              color="dark"
              unelevated
              no-caps
              icon="refresh"
              label="Reload Dashboard"
              @click="loadDashboard"
            />
            <q-btn
              outline
              color="dark"
              no-caps
              icon="play_circle"
              label="Run ANSI SQL"
              @click="runFirstQuery"
            />
          </div>
        </section>

        <section class="content-grid">
          <q-card flat class="surface-card lab-card">
            <q-card-section>
              <div class="row items-center justify-between q-col-gutter-md">
                <div>
                  <div class="section-title">Personal JupyterLab</div>
                  <div class="card-title">사용자별 Python 실습 세션</div>
                </div>
                <q-badge :color="labStatusColor" rounded>
                  {{ labSession.status }}
                </q-badge>
              </div>

              <p class="muted">
                사용자명을 입력하면 backend가 현재 namespace에 전용 Jupyter pod를 생성합니다.
                준비가 끝나면 새 탭으로 열어서 Notebook, Console, Terminal 기반으로 Python을
                연습할 수 있습니다.
              </p>

              <div class="lab-form">
                <q-input
                  v-model="labUsername"
                  dense
                  outlined
                  color="dark"
                  label="Username"
                  hint="예: student01, analyst.dev"
                  class="lab-input"
                  @keyup.enter="startLabSession"
                />
                <q-btn
                  color="dark"
                  unelevated
                  no-caps
                  icon="rocket_launch"
                  label="Start Lab"
                  :loading="sessionLoading"
                  :disable="!trimmedLabUsername"
                  @click="startLabSession"
                />
                <q-btn
                  outline
                  color="dark"
                  no-caps
                  icon="sync"
                  label="Refresh"
                  :loading="sessionLoading"
                  :disable="!trimmedLabUsername"
                  @click="refreshLabSession"
                />
                <q-btn
                  outline
                  color="dark"
                  no-caps
                  icon="open_in_new"
                  label="Open Lab"
                  :disable="!labLaunchUrl"
                  @click="openLab"
                />
                <q-btn
                  flat
                  color="negative"
                  no-caps
                  icon="delete"
                  label="Stop Lab"
                  :loading="sessionLoading"
                  :disable="!trimmedLabUsername"
                  @click="stopLabSession"
                />
              </div>

              <q-linear-progress
                v-if="labSession.status === 'provisioning'"
                indeterminate
                color="dark"
                class="lab-progress"
              />

              <q-banner rounded class="banner-note lab-banner">
                <div><strong>Status</strong> {{ labSession.detail }}</div>
                <div v-if="labSession.pod_name">Pod: {{ labSession.pod_name }}</div>
                <div v-if="labSession.service_name">Service: {{ labSession.service_name }}</div>
                <div v-if="labSession.node_port">NodePort: {{ labSession.node_port }}</div>
                <div v-if="labLaunchUrl" class="lab-url">{{ labLaunchUrl }}</div>
              </q-banner>
            </q-card-section>
          </q-card>

          <q-card flat class="surface-card">
            <q-card-section>
              <div class="section-title">Lab Guide</div>
              <div class="card-title">열리면 바로 Python 연습</div>
              <p class="muted">
                세션이 준비되면 JupyterLab Launcher에서 <strong>Notebook</strong> 또는
                <strong>Console</strong>을 선택하면 됩니다. 이미지에는 샘플 notebook이 포함되어
                있고, 세션 파일은 pod 삭제 시 함께 정리됩니다.
              </p>
              <div class="chip-grid">
                <q-chip color="white" text-color="dark" square>Python 3.12</q-chip>
                <q-chip color="white" text-color="dark" square>JupyterLab</q-chip>
                <q-chip color="white" text-color="dark" square>Kubernetes Pod per User</q-chip>
                <q-chip color="white" text-color="dark" square>Ephemeral Practice Workspace</q-chip>
              </div>
            </q-card-section>
          </q-card>
        </section>

        <section id="control-plane" class="content-grid control-plane-anchor">
          <q-card flat class="surface-card">
            <q-card-section>
              <div class="row items-center justify-between q-col-gutter-md">
                <div>
                  <div class="section-title">Control Plane Dashboard</div>
                  <div class="card-title">로그인 후 node / pod 인벤토리 조회</div>
                </div>
                <q-badge :color="controlPlane.authenticated ? 'positive' : 'grey-7'" rounded>
                  {{ controlPlane.authenticated ? "authenticated" : "login required" }}
                </q-badge>
              </div>

              <p class="muted">
                이 모듈은 backend를 통해 cluster-wide read 권한으로 node와 pod 현황을 읽어 옵니다.
                로그인 전에는 credentials를 입력하고, 로그인 후에는 namespace 필터와 inventory 탭을
                사용할 수 있습니다.
              </p>

              <div v-if="!controlPlane.authenticated" class="admin-login-grid">
                <q-input
                  v-model="controlPlaneLogin.username"
                  dense
                  outlined
                  color="dark"
                  label="Admin Username"
                  class="admin-input"
                  @keyup.enter="loginControlPlane"
                />
                <q-input
                  v-model="controlPlaneLogin.password"
                  dense
                  outlined
                  color="dark"
                  type="password"
                  label="Admin Password"
                  class="admin-input"
                  @keyup.enter="loginControlPlane"
                />
                <q-btn
                  color="dark"
                  unelevated
                  no-caps
                  icon="login"
                  label="Login Dashboard"
                  :loading="controlPlane.loading"
                  :disable="!controlPlaneLogin.username || !controlPlaneLogin.password"
                  @click="loginControlPlane"
                />
              </div>

              <div v-else class="admin-toolbar">
                <div class="chip-grid">
                  <q-chip
                    v-for="item in controlPlaneSummaryItems"
                    :key="item.label"
                    color="white"
                    text-color="dark"
                    square
                  >
                    <strong>{{ item.label }}</strong>&nbsp;{{ item.value }}
                  </q-chip>
                </div>
                <div class="hero-actions">
                  <q-select
                    v-model="controlPlane.namespace"
                    dense
                    outlined
                    color="dark"
                    label="Pod Namespace"
                    :options="controlPlane.namespaces"
                    class="namespace-select"
                    @update:model-value="loadControlPlaneDashboard"
                  />
                  <q-btn
                    outline
                    color="dark"
                    no-caps
                    icon="sync"
                    label="Refresh"
                    :loading="controlPlane.loading"
                    @click="loadControlPlaneDashboard"
                  />
                  <q-btn
                    flat
                    color="negative"
                    no-caps
                    icon="logout"
                    label="Logout"
                    @click="logoutControlPlane"
                  />
                </div>
              </div>

              <q-banner rounded class="banner-note lab-banner">
                {{ controlPlaneMessage }}
              </q-banner>
            </q-card-section>
          </q-card>

          <q-card v-if="controlPlane.authenticated" flat class="surface-card inventory-card">
            <q-card-section>
              <q-tabs
                v-model="controlPlane.activeTab"
                align="left"
                active-color="dark"
                indicator-color="dark"
                no-caps
              >
                <q-tab name="nodes" label="Nodes" icon="dns" />
                <q-tab name="pods" label="Pods" icon="deployed_code" />
              </q-tabs>

              <q-separator class="inventory-separator" />

              <q-tab-panels v-model="controlPlane.activeTab" animated class="inventory-panels">
                <q-tab-panel name="nodes">
                  <q-table
                    flat
                    :rows="controlPlane.nodes"
                    :columns="nodeColumns"
                    row-key="name"
                    :rows-per-page-options="[0]"
                    hide-pagination
                  >
                    <template #body-cell-ready="props">
                      <q-td :props="props">
                        <q-badge :color="props.value ? 'positive' : 'negative'" rounded>
                          {{ props.value ? "Ready" : "Check" }}
                        </q-badge>
                      </q-td>
                    </template>
                  </q-table>
                </q-tab-panel>

                <q-tab-panel name="pods">
                  <q-table
                    flat
                    :rows="controlPlane.pods"
                    :columns="podColumns"
                    row-key="name"
                    :rows-per-page-options="[0]"
                    hide-pagination
                  >
                    <template #body-cell-status="props">
                      <q-td :props="props">
                        <q-badge :color="podStatusColor(props.value)" rounded>
                          {{ props.value }}
                        </q-badge>
                      </q-td>
                    </template>
                  </q-table>
                </q-tab-panel>
              </q-tab-panels>
            </q-card-section>
          </q-card>
        </section>

        <section class="section-grid">
          <q-card v-for="service in dashboard.services" :key="service.name" flat class="status-card">
            <q-card-section>
              <div class="row items-center justify-between">
                <div>
                  <div class="card-label">{{ service.kind }}</div>
                  <div class="card-title">{{ service.name }}</div>
                </div>
                <q-badge :color="service.ok ? 'positive' : 'negative'" rounded>
                  {{ service.ok ? "ready" : "check" }}
                </q-badge>
              </div>
              <div class="card-endpoint">{{ service.endpoint }}</div>
              <div class="card-detail">{{ service.detail }}</div>
            </q-card-section>
          </q-card>
        </section>

        <section class="content-grid">
          <q-card flat class="surface-card">
            <q-card-section>
              <div class="section-title">Runtime Profile</div>
              <div class="chip-grid">
                <q-chip
                  v-for="(value, key) in dashboard.runtime"
                  :key="key"
                  color="white"
                  text-color="dark"
                  square
                >
                  <strong>{{ key }}</strong>&nbsp;{{ value }}
                </q-chip>
              </div>
            </q-card-section>
          </q-card>

          <q-card flat class="surface-card">
            <q-card-section>
              <div class="section-title">Quick Links</div>
              <div class="button-grid">
                <q-btn
                  v-for="link in dashboard.quick_links"
                  :key="link.name"
                  :href="link.url"
                  target="_blank"
                  no-caps
                  outline
                  color="dark"
                  class="link-button"
                >
                  <div class="text-left full-width">
                    <div class="link-title">{{ link.name }}</div>
                    <div class="link-description">{{ link.description }}</div>
                  </div>
                </q-btn>
              </div>
            </q-card-section>
          </q-card>
        </section>

        <section class="content-grid">
          <q-card flat class="surface-card">
            <q-card-section>
              <div class="section-title">Sample ANSI SQL</div>
              <q-table
                flat
                :rows="dashboard.sample_queries"
                :columns="queryColumns"
                row-key="name"
                :rows-per-page-options="[0]"
                hide-pagination
              >
                <template #body-cell-sql="props">
                  <q-td :props="props">
                    <code class="sql-preview">{{ props.value }}</code>
                  </q-td>
                </template>
              </q-table>
            </q-card-section>
          </q-card>

          <q-card flat class="surface-card">
            <q-card-section>
              <div class="section-title">Notebook Workspace</div>
              <div v-if="dashboard.notebooks.length" class="notebook-list">
                <q-chip
                  v-for="notebook in dashboard.notebooks"
                  :key="notebook"
                  icon="book"
                  color="secondary"
                  text-color="white"
                >
                  {{ notebook }}
                </q-chip>
              </div>
              <q-banner v-else rounded class="banner-note">
                Shared notebook volume is empty. Personal Jupyter sessions still start with the
                image-bundled sample notebook.
              </q-banner>
            </q-card-section>
          </q-card>
        </section>

        <section class="content-grid">
          <q-card flat class="surface-card">
            <q-card-section>
              <div class="section-title">Teradata Mode</div>
              <p class="muted">{{ dashboard.teradata.note }}</p>
              <q-banner rounded class="banner-note">
                Current mode: <strong>{{ dashboard.teradata.mode }}</strong>
              </q-banner>
            </q-card-section>
          </q-card>

          <q-card flat class="surface-card">
            <q-card-section>
              <div class="section-title">Query Result</div>
              <q-inner-loading :showing="queryLoading || loading">
                <q-spinner-grid color="dark" size="42px" />
              </q-inner-loading>
              <q-markup-table flat class="result-table" v-if="queryResult.rows.length">
                <thead>
                  <tr>
                    <th v-for="column in queryResult.columns" :key="column">{{ column }}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="(row, rowIndex) in queryResult.rows" :key="rowIndex">
                    <td v-for="column in queryResult.columns" :key="column">{{ row[column] }}</td>
                  </tr>
                </tbody>
              </q-markup-table>
              <q-banner v-else rounded class="banner-note">
                Run the first sample query to preview the Teradata response shape.
              </q-banner>
            </q-card-section>
          </q-card>
        </section>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { Notify } from "quasar";
import { computed, onMounted, onUnmounted, ref } from "vue";

const browserProtocol = typeof window !== "undefined" ? window.location.protocol : "http:";
const browserHost = typeof window !== "undefined" ? window.location.hostname : "localhost";
const apiBaseUrl =
  import.meta.env.VITE_API_BASE_URL || `${browserProtocol}//${browserHost}:30081`;
const savedLabUsername =
  typeof window !== "undefined" ? window.localStorage.getItem("labUsername") || "" : "";
const savedControlPlaneToken =
  typeof window !== "undefined" ? window.localStorage.getItem("controlPlaneToken") || "" : "";
const savedControlPlaneUsername =
  typeof window !== "undefined" ? window.localStorage.getItem("controlPlaneUsername") || "" : "";

const loading = ref(true);
const queryLoading = ref(false);
const sessionLoading = ref(false);
const labUsername = ref(savedLabUsername);
const labSession = ref(emptyLabSession());
const controlPlaneLogin = ref({
  username: savedControlPlaneUsername || "platform-admin",
  password: "",
});
const controlPlane = ref(emptyControlPlaneState(savedControlPlaneToken));

let pollHandle = null;

const trimmedLabUsername = computed(() => labUsername.value.trim());
const labStatusColor = computed(() => {
  if (labSession.value.status === "ready") {
    return "positive";
  }
  if (labSession.value.status === "provisioning") {
    return "warning";
  }
  if (labSession.value.status === "failed") {
    return "negative";
  }
  return "grey-7";
});
const labLaunchUrl = computed(() => {
  if (!labSession.value.node_port || !labSession.value.token) {
    return "";
  }
  return (
    `${browserProtocol}//${browserHost}:${labSession.value.node_port}/lab` +
    `?token=${encodeURIComponent(labSession.value.token)}`
  );
});
const controlPlaneSummaryItems = computed(() => [
  {
    label: "cluster",
    value: controlPlane.value.summary.cluster_name,
  },
  {
    label: "version",
    value: controlPlane.value.summary.cluster_version,
  },
  {
    label: "nodes",
    value: `${controlPlane.value.summary.ready_node_count}/${controlPlane.value.summary.node_count} ready`,
  },
  {
    label: "pods",
    value: `${controlPlane.value.summary.running_pod_count}/${controlPlane.value.summary.pod_count} running`,
  },
  {
    label: "namespace",
    value: controlPlane.value.summary.current_namespace,
  },
]);
const controlPlaneMessage = computed(() => {
  if (!controlPlane.value.authenticated) {
    return "Enter the admin credentials to unlock the control-plane dashboard.";
  }
  return `Loaded ${controlPlane.value.nodes.length} nodes and ${controlPlane.value.pods.length} pods.`;
});

const dashboard = ref({
  runtime: {},
  services: [],
  quick_links: [],
  sample_queries: [],
  notebooks: [],
  teradata: {
    mode: "mock",
    note: "",
  },
});

const queryResult = ref({
  columns: [],
  rows: [],
});

const queryColumns = [
  { name: "name", label: "Query", field: "name", align: "left" },
  { name: "description", label: "Description", field: "description", align: "left" },
  { name: "sql", label: "SQL", field: "sql", align: "left" },
];

const nodeColumns = [
  { name: "name", label: "Node", field: "name", align: "left" },
  { name: "ready", label: "Ready", field: "ready", align: "left" },
  { name: "roles", label: "Roles", field: "roles", align: "left" },
  { name: "version", label: "Version", field: "version", align: "left" },
  { name: "internal_ip", label: "Internal IP", field: "internal_ip", align: "left" },
  { name: "os_image", label: "OS", field: "os_image", align: "left" },
];

const podColumns = [
  { name: "namespace", label: "Namespace", field: "namespace", align: "left" },
  { name: "name", label: "Pod", field: "name", align: "left" },
  { name: "ready", label: "Ready", field: "ready", align: "left" },
  { name: "status", label: "Status", field: "status", align: "left" },
  { name: "restarts", label: "Restarts", field: "restarts", align: "right" },
  { name: "node_name", label: "Node", field: "node_name", align: "left" },
];

function emptyLabSession() {
  return {
    session_id: "",
    username: "",
    namespace: "",
    pod_name: "",
    service_name: "",
    status: "idle",
    phase: "Idle",
    ready: false,
    detail: "Create a personal lab to start JupyterLab.",
    token: "",
    node_port: null,
    created_at: null,
  };
}

function emptyControlPlaneState(token = "") {
  return {
    authenticated: Boolean(token),
    loading: false,
    token,
    namespace: "all",
    namespaces: ["all"],
    activeTab: "nodes",
    summary: {
      cluster_name: "k3s control plane",
      cluster_version: "-",
      current_namespace: "all",
      namespace_count: 0,
      node_count: 0,
      ready_node_count: 0,
      pod_count: 0,
      running_pod_count: 0,
    },
    nodes: [],
    pods: [],
  };
}

function startPolling() {
  if (pollHandle !== null) {
    return;
  }
  pollHandle = window.setInterval(() => {
    void refreshLabSession({ silent: true });
  }, 4000);
}

function stopPolling() {
  if (pollHandle !== null) {
    window.clearInterval(pollHandle);
    pollHandle = null;
  }
}

function applyLabSession(payload, options = {}) {
  const previousStatus = labSession.value.status;
  labSession.value = {
    ...emptyLabSession(),
    ...payload,
  };

  if (labSession.value.status === "provisioning") {
    startPolling();
  } else {
    stopPolling();
  }

  if (
    options.notifyReady &&
    previousStatus === "provisioning" &&
    labSession.value.status === "ready"
  ) {
    Notify.create({
      type: "positive",
      message: `JupyterLab is ready for ${labSession.value.username}.`,
    });
  }
}

function applyControlPlaneDashboard(payload) {
  controlPlane.value = {
    ...controlPlane.value,
    authenticated: true,
    namespace: payload.summary.current_namespace,
    namespaces: payload.namespaces,
    nodes: payload.nodes,
    pods: payload.pods,
    summary: payload.summary,
  };
}

async function parseJson(response) {
  if (!response.ok) {
    let message = `Request failed: ${response.status}`;
    try {
      const payload = await response.json();
      if (payload.detail) {
        message = payload.detail;
      }
    } catch {
      // keep the default message
    }
    throw new Error(message);
  }
  return response.json();
}

function podStatusColor(status) {
  if (status === "Running") {
    return "positive";
  }
  if (status === "Pending") {
    return "warning";
  }
  if (status === "Succeeded") {
    return "secondary";
  }
  return "negative";
}

async function loadDashboard() {
  loading.value = true;
  try {
    const response = await fetch(`${apiBaseUrl}/api/dashboard`);
    dashboard.value = await parseJson(response);
  } catch (error) {
    Notify.create({
      type: "negative",
      message: error.message,
    });
  } finally {
    loading.value = false;
  }
}

async function runFirstQuery() {
  const firstQuery = dashboard.value.sample_queries[0];
  if (!firstQuery) {
    return;
  }

  queryLoading.value = true;
  try {
    const response = await fetch(`${apiBaseUrl}/api/teradata/query`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        sql: firstQuery.sql,
        limit: 10,
      }),
    });

    const payload = await parseJson(response);
    queryResult.value = {
      columns: payload.columns,
      rows: payload.rows,
    };
    Notify.create({
      type: "positive",
      message: payload.note,
    });
  } catch (error) {
    Notify.create({
      type: "negative",
      message: error.message,
    });
  } finally {
    queryLoading.value = false;
  }
}

async function refreshLabSession(options = {}) {
  if (!trimmedLabUsername.value || sessionLoading.value) {
    if (!trimmedLabUsername.value) {
      stopPolling();
      applyLabSession(emptyLabSession());
    }
    return;
  }

  sessionLoading.value = true;
  try {
    const response = await fetch(
      `${apiBaseUrl}/api/jupyter/sessions/${encodeURIComponent(trimmedLabUsername.value)}`,
    );
    const payload = await parseJson(response);
    applyLabSession(payload, { notifyReady: true });
    if (!options.silent && payload.status === "missing") {
      Notify.create({
        type: "info",
        message: "No personal JupyterLab exists yet. Start a new lab first.",
      });
    }
  } catch (error) {
    stopPolling();
    Notify.create({
      type: "negative",
      message: error.message,
    });
  } finally {
    sessionLoading.value = false;
  }
}

async function startLabSession() {
  if (!trimmedLabUsername.value || sessionLoading.value) {
    return;
  }

  sessionLoading.value = true;
  try {
    if (typeof window !== "undefined") {
      window.localStorage.setItem("labUsername", trimmedLabUsername.value);
    }

    const response = await fetch(`${apiBaseUrl}/api/jupyter/sessions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        username: trimmedLabUsername.value,
      }),
    });
    const payload = await parseJson(response);
    applyLabSession(payload);
    Notify.create({
      type: payload.status === "ready" ? "positive" : "info",
      message:
        payload.status === "ready"
          ? `JupyterLab is ready for ${payload.username}.`
          : `Creating JupyterLab pod for ${payload.username}.`,
    });
  } catch (error) {
    stopPolling();
    Notify.create({
      type: "negative",
      message: error.message,
    });
  } finally {
    sessionLoading.value = false;
  }
}

async function stopLabSession() {
  if (!trimmedLabUsername.value || sessionLoading.value) {
    return;
  }

  sessionLoading.value = true;
  try {
    const response = await fetch(
      `${apiBaseUrl}/api/jupyter/sessions/${encodeURIComponent(trimmedLabUsername.value)}`,
      {
        method: "DELETE",
      },
    );
    const payload = await parseJson(response);
    applyLabSession(payload);
    stopPolling();
    Notify.create({
      type: "warning",
      message: `Removed personal JupyterLab resources for ${payload.username}.`,
    });
  } catch (error) {
    Notify.create({
      type: "negative",
      message: error.message,
    });
  } finally {
    sessionLoading.value = false;
  }
}

async function loadControlPlaneDashboard() {
  if (!controlPlane.value.token || controlPlane.value.loading) {
    return;
  }

  controlPlane.value = {
    ...controlPlane.value,
    loading: true,
  };
  try {
    const response = await fetch(
      `${apiBaseUrl}/api/control-plane/dashboard?namespace=${encodeURIComponent(controlPlane.value.namespace)}`,
      {
        headers: {
          "X-Control-Plane-Token": controlPlane.value.token,
        },
      },
    );
    const payload = await parseJson(response);
    applyControlPlaneDashboard(payload);
  } catch (error) {
    if (typeof window !== "undefined" && /login required/i.test(error.message)) {
      window.localStorage.removeItem("controlPlaneToken");
    }
    controlPlane.value = emptyControlPlaneState();
    Notify.create({
      type: "negative",
      message: error.message,
    });
  } finally {
    controlPlane.value = {
      ...controlPlane.value,
      loading: false,
    };
  }
}

async function loginControlPlane() {
  if (controlPlane.value.loading) {
    return;
  }

  controlPlane.value = {
    ...controlPlane.value,
    loading: true,
  };
  try {
    const response = await fetch(`${apiBaseUrl}/api/control-plane/login`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        username: controlPlaneLogin.value.username,
        password: controlPlaneLogin.value.password,
      }),
    });
    const payload = await parseJson(response);
    controlPlane.value = {
      ...emptyControlPlaneState(payload.token),
      authenticated: true,
      token: payload.token,
      loading: false,
      namespace: payload.dashboard.summary.current_namespace,
      namespaces: payload.dashboard.namespaces,
      activeTab: "nodes",
      summary: payload.dashboard.summary,
      nodes: payload.dashboard.nodes,
      pods: payload.dashboard.pods,
    };

    if (typeof window !== "undefined") {
      window.localStorage.setItem("controlPlaneToken", payload.token);
      window.localStorage.setItem("controlPlaneUsername", payload.username);
    }

    Notify.create({
      type: "positive",
      message: "Control-plane dashboard login succeeded.",
    });
  } catch (error) {
    controlPlane.value = {
      ...controlPlane.value,
      loading: false,
    };
    Notify.create({
      type: "negative",
      message: error.message,
    });
  }
}

function logoutControlPlane() {
  controlPlane.value = emptyControlPlaneState();
  controlPlaneLogin.value = {
    username: controlPlaneLogin.value.username || "platform-admin",
    password: "",
  };
  if (typeof window !== "undefined") {
    window.localStorage.removeItem("controlPlaneToken");
  }
  Notify.create({
    type: "info",
    message: "Control-plane dashboard session cleared.",
  });
}

function openLab() {
  if (!labLaunchUrl.value) {
    Notify.create({
      type: "warning",
      message: "JupyterLab is not ready yet.",
    });
    return;
  }

  window.open(labLaunchUrl.value, "_blank", "noopener");
}

onMounted(async () => {
  await loadDashboard();
  await runFirstQuery();
  if (trimmedLabUsername.value) {
    await refreshLabSession({ silent: true });
  }
  if (controlPlane.value.authenticated) {
    await loadControlPlaneDashboard();
  }
});

onUnmounted(() => {
  stopPolling();
});
</script>
