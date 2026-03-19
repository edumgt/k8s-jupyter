<template>
  <q-layout view="lHh Lpr lFf">
    <q-page-container>
      <q-page class="page-shell">
        <section class="hero-panel">
          <div class="eyebrow">K8s Data Platform OVA</div>
          <h1>데모 사용자 로그인부터 Jupyter sandbox, 관리자 모니터링까지 한 화면에서</h1>
          <p>
            `test1@test.com`, `test2@test.com` 사용자는 로그인 후 본인 전용 Jupyter pod를 실행할 수
            있고, `admin@test.com` 관리자는 사용자별 실행 여부, 사용시간, 사용회수와 cluster
            inventory를 같은 웹앱에서 확인할 수 있습니다.
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
          <div class="chip-grid">
            <q-chip color="white" text-color="dark" square>
              <strong>frontend</strong>&nbsp;v{{ frontendAppVersion }}
            </q-chip>
            <q-chip color="white" text-color="dark" square>
              <strong>backend</strong>&nbsp;v{{ backendAppVersion }}
            </q-chip>
          </div>
        </section>

        <section class="content-grid">
          <q-card flat class="surface-card auth-card">
            <q-card-section>
              <div class="row items-center justify-between q-col-gutter-md">
                <div>
                  <div class="section-title">Sandbox Login</div>
                  <div class="card-title">데모 사용자 / 관리자 인증</div>
                </div>
                <q-badge :color="isAuthenticated ? 'positive' : 'grey-7'" rounded>
                  {{ isAuthenticated ? appSession.user.role : "login required" }}
                </q-badge>
              </div>

              <p class="muted">
                사용자는 본인 계정으로만 Jupyter sandbox를 시작할 수 있고, 관리자는 별도 관리자
                모드에서 사용자 sandbox 사용 현황과 control plane을 모니터링합니다.
              </p>

              <div v-if="!isAuthenticated" class="admin-login-grid">
                <q-input
                  v-model="loginForm.username"
                  dense
                  outlined
                  color="dark"
                  label="Email"
                  class="admin-input"
                  @keyup.enter="loginApp"
                />
                <q-input
                  v-model="loginForm.password"
                  dense
                  outlined
                  color="dark"
                  type="password"
                  label="Password"
                  class="admin-input"
                  @keyup.enter="loginApp"
                />
                <q-btn
                  color="dark"
                  unelevated
                  no-caps
                  icon="login"
                  label="Login"
                  :loading="authLoading"
                  :disable="!loginForm.username || !loginForm.password"
                  @click="loginApp"
                />
              </div>

              <div v-else class="auth-session-bar">
                <div class="chip-grid">
                  <q-chip color="white" text-color="dark" square>
                    <strong>User</strong>&nbsp;{{ appSession.user.display_name }}
                  </q-chip>
                  <q-chip color="white" text-color="dark" square>
                    <strong>Email</strong>&nbsp;{{ appSession.user.username }}
                  </q-chip>
                  <q-chip color="white" text-color="dark" square>
                    <strong>Role</strong>&nbsp;{{ appSession.user.role }}
                  </q-chip>
                </div>
                <div class="hero-actions">
                  <q-btn
                    v-if="isAdmin"
                    outline
                    color="dark"
                    no-caps
                    icon="monitor"
                    label="Refresh Admin Overview"
                    :loading="adminLoading"
                    @click="loadAdminOverview"
                  />
                  <q-btn
                    flat
                    color="negative"
                    no-caps
                    icon="logout"
                    label="Logout"
                    :loading="authLoading"
                    @click="logoutApp"
                  />
                </div>
              </div>

              <div class="demo-account-grid">
                <q-card
                  v-for="account in demoAccounts"
                  :key="account.username"
                  flat
                  class="demo-user-card"
                >
                  <q-card-section>
                    <div class="card-label">{{ account.role }}</div>
                    <div class="card-title demo-title">{{ account.display_name }}</div>
                    <div class="card-endpoint">{{ account.username }}</div>
                    <div class="card-detail">Password: 123456</div>
                    <q-btn
                      outline
                      color="dark"
                      no-caps
                      icon="login"
                      class="demo-fill-button"
                      label="Use This Account"
                      @click="applyDemoAccount(account)"
                    />
                  </q-card-section>
                </q-card>
              </div>
            </q-card-section>
          </q-card>
        </section>

        <section v-if="isUser" class="content-grid">
          <q-card flat class="surface-card lab-card">
            <q-card-section>
              <div class="row items-center justify-between q-col-gutter-md">
                <div>
                  <div class="section-title">Personal JupyterLab</div>
                  <div class="card-title">로그인한 사용자 전용 sandbox</div>
                </div>
                <q-badge :color="labStatusColor" rounded>
                  {{ labSession.status }}
                </q-badge>
              </div>

              <p class="muted">
                현재 로그인한 계정 <strong>{{ managedUsername }}</strong> 전용 Jupyter pod를 시작합니다.
                backend는 사용자별 PVC subPath와 snapshot 이미지를 확인하고, 준비가 끝나면 새 탭으로
                JupyterLab을 열 수 있습니다.
              </p>

              <div class="chip-grid">
                <q-chip color="white" text-color="dark" square>
                  <strong>User</strong>&nbsp;{{ managedUsername }}
                </q-chip>
                <q-chip color="white" text-color="dark" square>
                  <strong>Workspace</strong>&nbsp;{{ labSession.workspace_subpath || "not created" }}
                </q-chip>
              </div>

              <div class="lab-form">
                <q-btn
                  color="dark"
                  unelevated
                  no-caps
                  icon="rocket_launch"
                  label="Start My Sandbox"
                  :loading="sessionLoading"
                  @click="startLabSession"
                />
                <q-btn
                  outline
                  color="dark"
                  no-caps
                  icon="sync"
                  label="Refresh"
                  :loading="sessionLoading"
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
                <div v-if="labSession.workspace_subpath">Workspace: {{ labSession.workspace_subpath }}</div>
                <div v-if="labSession.node_port">NodePort: {{ labSession.node_port }}</div>
                <div v-if="labSession.image" class="lab-url">Image: {{ labSession.image }}</div>
                <div v-if="labLaunchUrl" class="lab-url">{{ labLaunchUrl }}</div>
              </q-banner>
            </q-card-section>
          </q-card>

          <q-card flat class="surface-card">
            <q-card-section>
              <div class="row items-center justify-between q-col-gutter-md">
                <div>
                  <div class="section-title">Workspace Snapshot</div>
                  <div class="card-title">개인 sandbox 복원 이미지</div>
                </div>
                <q-badge :color="snapshotStatusColor" rounded>
                  {{ snapshotState.status }}
                </q-badge>
              </div>

              <p class="muted">
                PVC `users/&lt;session-id&gt;`에 저장된 작업 내용을 Harbor snapshot으로 publish할 수
                있습니다. 다음 로그인 시 backend가 이 이미지를 우선 사용합니다.
              </p>

              <div class="lab-form">
                <q-btn
                  color="dark"
                  unelevated
                  no-caps
                  icon="cloud_upload"
                  label="Publish Snapshot"
                  :loading="snapshotLoading"
                  @click="publishSnapshot"
                />
                <q-btn
                  outline
                  color="dark"
                  no-caps
                  icon="inventory_2"
                  label="Refresh Snapshot"
                  :loading="snapshotLoading"
                  @click="refreshSnapshotStatus"
                />
              </div>

              <q-linear-progress
                v-if="snapshotState.status === 'building'"
                indeterminate
                color="dark"
                class="lab-progress"
              />

              <q-banner rounded class="banner-note lab-banner">
                <div><strong>Status</strong> {{ snapshotState.detail }}</div>
                <div v-if="snapshotState.job_name">Job: {{ snapshotState.job_name }}</div>
                <div v-if="snapshotState.workspace_subpath">
                  Workspace: {{ snapshotState.workspace_subpath }}
                </div>
                <div v-if="snapshotState.published_at">Published: {{ snapshotState.published_at }}</div>
                <div v-if="snapshotState.image" class="lab-url">
                  Snapshot Image: {{ snapshotState.image }}
                </div>
              </q-banner>
            </q-card-section>
          </q-card>
        </section>

        <section v-if="isAdmin" id="sandbox-admin" class="content-grid control-plane-anchor">
          <q-card flat class="surface-card">
            <q-card-section>
              <div class="row items-center justify-between q-col-gutter-md">
                <div>
                  <div class="section-title">Admin Monitoring</div>
                  <div class="card-title">사용자별 Jupyter sandbox 모니터링</div>
                </div>
                <q-badge :color="adminOverview.summary.running_user_count ? 'positive' : 'grey-7'" rounded>
                  {{ adminOverview.summary.running_user_count }} running
                </q-badge>
              </div>

              <p class="muted">
                관리자는 `test1@test.com`, `test2@test.com` 사용자 sandbox의 실행 여부, 현재 사용시간,
                누적 사용시간, 로그인 회수, Jupyter 실행 회수를 확인할 수 있습니다.
              </p>

              <div class="chip-grid">
                <q-chip
                  v-for="item in adminSummaryItems"
                  :key="item.label"
                  color="white"
                  text-color="dark"
                  square
                >
                  <strong>{{ item.label }}</strong>&nbsp;{{ item.value }}
                </q-chip>
              </div>

              <q-banner rounded class="banner-note lab-banner">
                {{ adminMonitorMessage }}
              </q-banner>
            </q-card-section>
          </q-card>

          <q-card flat class="surface-card inventory-card">
            <q-card-section>
              <q-table
                flat
                :rows="adminOverview.users"
                :columns="adminUserColumns"
                row-key="username"
                :rows-per-page-options="[0]"
                hide-pagination
                :loading="adminLoading"
              >
                <template #body-cell-status="props">
                  <q-td :props="props">
                    <q-badge :color="sandboxStatusColor(props.value, props.row.ready)" rounded>
                      {{ props.value }}
                    </q-badge>
                  </q-td>
                </template>
                <template #body-cell-current_session_seconds="props">
                  <q-td :props="props">
                    {{ formatDuration(props.value) }}
                  </q-td>
                </template>
                <template #body-cell-total_session_seconds="props">
                  <q-td :props="props">
                    {{ formatDuration(props.value) }}
                  </q-td>
                </template>
                <template #body-cell-last_login_at="props">
                  <q-td :props="props">
                    {{ formatDateTime(props.value) }}
                  </q-td>
                </template>
                <template #body-cell-last_launch_at="props">
                  <q-td :props="props">
                    {{ formatDateTime(props.value) }}
                  </q-td>
                </template>
              </q-table>
            </q-card-section>
          </q-card>
        </section>

        <section class="content-grid control-plane-anchor">
          <q-card flat class="surface-card">
            <q-card-section>
              <div class="row items-center justify-between q-col-gutter-md">
                <div>
                  <div class="section-title">Control Plane Dashboard</div>
                  <div class="card-title">관리자 모드 cluster inventory</div>
                </div>
                <q-badge :color="isAdmin ? 'positive' : 'grey-7'" rounded>
                  {{ isAdmin ? "admin session" : "admin required" }}
                </q-badge>
              </div>

              <p class="muted">
                관리자 계정으로 로그인하면 node / pod inventory를 읽어 오고 namespace 필터로 cluster
                전체 상태를 확인할 수 있습니다.
              </p>

              <div v-if="isAdmin" class="admin-toolbar">
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
                </div>
              </div>

              <q-banner rounded class="banner-note lab-banner">
                {{ controlPlaneMessage }}
              </q-banner>
            </q-card-section>
          </q-card>

          <q-card v-if="isAdmin" flat class="surface-card inventory-card">
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
                    :loading="controlPlane.loading"
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
                    :loading="controlPlane.loading"
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
import frontendPackage from "../package.json";

const browserProtocol = typeof window !== "undefined" ? window.location.protocol : "http:";
const browserHost = typeof window !== "undefined" ? window.location.hostname : "localhost";
const apiBaseUrl =
  import.meta.env.VITE_API_BASE_URL || `${browserProtocol}//${browserHost}:30081`;
const frontendAppVersion = frontendPackage.version;

const savedAuthToken =
  typeof window !== "undefined" ? window.localStorage.getItem("appAuthToken") || "" : "";
const savedAuthUser =
  typeof window !== "undefined" && window.localStorage.getItem("appAuthUser")
    ? JSON.parse(window.localStorage.getItem("appAuthUser"))
    : null;

const loading = ref(true);
const queryLoading = ref(false);
const authLoading = ref(false);
const sessionLoading = ref(false);
const snapshotLoading = ref(false);
const adminLoading = ref(false);

const demoAccounts = ref([
  { username: "test1@test.com", role: "user", display_name: "Test User 1" },
  { username: "test2@test.com", role: "user", display_name: "Test User 2" },
  { username: "admin@test.com", role: "admin", display_name: "Platform Admin" },
]);

const loginForm = ref({
  username: savedAuthUser?.username || "test1@test.com",
  password: "123456",
});

const appSession = ref(emptyAppSession(savedAuthToken, savedAuthUser));
const labSession = ref(emptyLabSession());
const snapshotState = ref(emptySnapshotState());
const adminOverview = ref(emptyAdminOverview());
const controlPlane = ref(emptyControlPlaneState());

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

let labPollHandle = null;
let adminPollHandle = null;

const isAuthenticated = computed(() => appSession.value.authenticated);
const isAdmin = computed(() => appSession.value.user?.role === "admin");
const isUser = computed(() => appSession.value.user?.role === "user");
const managedUsername = computed(() => (isUser.value ? appSession.value.user.username : ""));
const backendAppVersion = computed(() => dashboard.value.runtime.backend_version || "-");

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

const snapshotStatusColor = computed(() => {
  if (snapshotState.value.status === "ready") {
    return "positive";
  }
  if (snapshotState.value.status === "building" || snapshotState.value.status === "pending") {
    return "warning";
  }
  if (snapshotState.value.status === "failed") {
    return "negative";
  }
  return "grey-7";
});

const adminSummaryItems = computed(() => [
  {
    label: "users",
    value: `${adminOverview.value.summary.ready_user_count}/${adminOverview.value.summary.sandbox_user_count} ready`,
  },
  {
    label: "running",
    value: adminOverview.value.summary.running_user_count,
  },
  {
    label: "logins",
    value: adminOverview.value.summary.total_login_count,
  },
  {
    label: "launches",
    value: adminOverview.value.summary.total_launch_count,
  },
  {
    label: "total use",
    value: formatDuration(adminOverview.value.summary.total_session_seconds),
  },
]);

const adminMonitorMessage = computed(() => {
  if (!isAdmin.value) {
    return "Admin login is required to monitor user sandboxes.";
  }
  if (!adminOverview.value.users.length) {
    return "Sandbox monitoring data will appear here after users log in and start Jupyter.";
  }
  return `Tracking ${adminOverview.value.users.length} demo users with ${adminOverview.value.summary.running_user_count} active sandbox sessions.`;
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
  if (!isAdmin.value) {
    return "Log in with admin@test.com / 123456 to unlock the control-plane dashboard.";
  }
  return `Loaded ${controlPlane.value.nodes.length} nodes and ${controlPlane.value.pods.length} pods.`;
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

const adminUserColumns = [
  { name: "display_name", label: "User", field: "display_name", align: "left" },
  { name: "username", label: "Email", field: "username", align: "left" },
  { name: "status", label: "Sandbox", field: "status", align: "left" },
  { name: "launch_count", label: "Launches", field: "launch_count", align: "right" },
  { name: "login_count", label: "Logins", field: "login_count", align: "right" },
  {
    name: "current_session_seconds",
    label: "Current Use",
    field: "current_session_seconds",
    align: "right",
  },
  {
    name: "total_session_seconds",
    label: "Total Use",
    field: "total_session_seconds",
    align: "right",
  },
  { name: "pod_name", label: "Pod", field: "pod_name", align: "left" },
  { name: "node_port", label: "NodePort", field: "node_port", align: "right" },
  { name: "last_login_at", label: "Last Login", field: "last_login_at", align: "left" },
  { name: "last_launch_at", label: "Last Launch", field: "last_launch_at", align: "left" },
];

function emptyAppSession(token = "", user = null) {
  return {
    authenticated: Boolean(token && user),
    token,
    user,
  };
}

function emptyLabSession() {
  return {
    session_id: "",
    username: "",
    namespace: "",
    pod_name: "",
    service_name: "",
    workspace_subpath: "",
    image: "",
    status: "idle",
    phase: "Idle",
    ready: false,
    detail: "Log in as a sandbox user to start JupyterLab.",
    token: "",
    node_port: null,
    created_at: null,
  };
}

function emptySnapshotState() {
  return {
    username: "",
    session_id: "",
    workspace_subpath: "",
    image: "",
    status: "idle",
    job_name: "",
    published_at: "",
    restorable: false,
    detail: "Publish a workspace snapshot after your Jupyter sandbox is running.",
  };
}

function emptyAdminOverview() {
  return {
    summary: {
      sandbox_user_count: 0,
      running_user_count: 0,
      ready_user_count: 0,
      total_login_count: 0,
      total_launch_count: 0,
      total_session_seconds: 0,
    },
    users: [],
  };
}

function emptyControlPlaneState() {
  return {
    loading: false,
    namespace: "all",
    namespaces: ["all"],
    activeTab: "nodes",
    summary: {
      cluster_name: "Kubernetes control plane",
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

function authHeaders(extraHeaders = {}) {
  const headers = { ...extraHeaders };
  if (appSession.value.token) {
    headers["X-Auth-Token"] = appSession.value.token;
  }
  return headers;
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
      // keep default message
    }
    throw new Error(message);
  }
  return response.json();
}

function formatDuration(totalSeconds) {
  const seconds = Math.max(0, Number(totalSeconds || 0));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainingSeconds = seconds % 60;
  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  if (minutes > 0) {
    return `${minutes}m ${remainingSeconds}s`;
  }
  return `${remainingSeconds}s`;
}

function formatDateTime(value) {
  if (!value) {
    return "-";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleString();
}

function sandboxStatusColor(status, ready) {
  if (ready || status === "ready") {
    return "positive";
  }
  if (status === "provisioning") {
    return "warning";
  }
  if (status === "missing" || status === "idle") {
    return "grey-7";
  }
  return "negative";
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

function applyDemoAccount(account) {
  loginForm.value = {
    username: account.username,
    password: "123456",
  };
}

function persistAppSession(token, user) {
  if (typeof window === "undefined") {
    return;
  }
  window.localStorage.setItem("appAuthToken", token);
  window.localStorage.setItem("appAuthUser", JSON.stringify(user));
}

function clearAppSessionStorage() {
  if (typeof window === "undefined") {
    return;
  }
  window.localStorage.removeItem("appAuthToken");
  window.localStorage.removeItem("appAuthUser");
}

function startLabPolling() {
  if (labPollHandle !== null || !isUser.value) {
    return;
  }
  labPollHandle = window.setInterval(() => {
    void refreshLabSession({ silent: true });
  }, 4000);
}

function stopLabPolling() {
  if (labPollHandle !== null) {
    window.clearInterval(labPollHandle);
    labPollHandle = null;
  }
}

function startAdminPolling() {
  if (adminPollHandle !== null || !isAdmin.value) {
    return;
  }
  adminPollHandle = window.setInterval(() => {
    void loadAdminOverview({ silent: true });
  }, 6000);
}

function stopAdminPolling() {
  if (adminPollHandle !== null) {
    window.clearInterval(adminPollHandle);
    adminPollHandle = null;
  }
}

function resetRoleScopedState() {
  stopLabPolling();
  stopAdminPolling();
  labSession.value = emptyLabSession();
  snapshotState.value = emptySnapshotState();
  adminOverview.value = emptyAdminOverview();
  controlPlane.value = emptyControlPlaneState();
}

async function loadDemoUsers() {
  try {
    const response = await fetch(`${apiBaseUrl}/api/demo-users`);
    const payload = await parseJson(response);
    demoAccounts.value = payload.items;
  } catch {
    // fallback to built-in demo accounts
  }
}

async function restoreAuthSession() {
  if (!appSession.value.token) {
    return;
  }
  try {
    const response = await fetch(`${apiBaseUrl}/api/auth/me`, {
      headers: authHeaders(),
    });
    const payload = await parseJson(response);
    appSession.value = emptyAppSession(appSession.value.token, payload.user);
    persistAppSession(appSession.value.token, payload.user);
  } catch (error) {
    clearAppSessionStorage();
    appSession.value = emptyAppSession();
    Notify.create({
      type: "warning",
      message: error.message,
    });
  }
}

async function loginApp() {
  if (authLoading.value) {
    return;
  }

  authLoading.value = true;
  try {
    const response = await fetch(`${apiBaseUrl}/api/auth/login`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(loginForm.value),
    });
    const payload = await parseJson(response);
    appSession.value = emptyAppSession(payload.token, payload.user);
    persistAppSession(payload.token, payload.user);
    resetRoleScopedState();

    if (payload.user.role === "user") {
      await refreshLabSession({ silent: true, skipSnapshotRefresh: true });
      await refreshSnapshotStatus({ silent: true });
    } else if (payload.user.role === "admin") {
      await loadAdminOverview({ silent: true });
      await loadControlPlaneDashboard({ silent: true });
      startAdminPolling();
    }

    Notify.create({
      type: "positive",
      message:
        payload.user.role === "admin"
          ? "Admin mode is ready."
          : `Logged in as ${payload.user.display_name}.`,
    });
  } catch (error) {
    Notify.create({
      type: "negative",
      message: error.message,
    });
  } finally {
    authLoading.value = false;
  }
}

async function logoutApp() {
  if (authLoading.value || !appSession.value.token) {
    return;
  }

  authLoading.value = true;
  try {
    await fetch(`${apiBaseUrl}/api/auth/logout`, {
      method: "POST",
      headers: authHeaders(),
    });
  } finally {
    clearAppSessionStorage();
    appSession.value = emptyAppSession();
    resetRoleScopedState();
    authLoading.value = false;
    Notify.create({
      type: "info",
      message: "Application session cleared.",
    });
  }
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
  if (!isUser.value || !managedUsername.value || sessionLoading.value) {
    return;
  }

  sessionLoading.value = true;
  try {
    const response = await fetch(
      `${apiBaseUrl}/api/jupyter/sessions/${encodeURIComponent(managedUsername.value)}`,
      {
        headers: authHeaders(),
      },
    );
    const payload = await parseJson(response);
    labSession.value = {
      ...emptyLabSession(),
      ...payload,
    };

    if (labSession.value.status === "provisioning") {
      startLabPolling();
    } else {
      stopLabPolling();
    }

    if (!options.skipSnapshotRefresh) {
      void refreshSnapshotStatus({ silent: true });
    }
  } catch (error) {
    stopLabPolling();
    Notify.create({
      type: "negative",
      message: error.message,
    });
  } finally {
    sessionLoading.value = false;
  }
}

async function startLabSession() {
  if (!isUser.value || !managedUsername.value || sessionLoading.value) {
    return;
  }

  sessionLoading.value = true;
  try {
    const response = await fetch(`${apiBaseUrl}/api/jupyter/sessions`, {
      method: "POST",
      headers: authHeaders({
        "Content-Type": "application/json",
      }),
      body: JSON.stringify({
        username: managedUsername.value,
      }),
    });
    const payload = await parseJson(response);
    labSession.value = {
      ...emptyLabSession(),
      ...payload,
    };
    if (labSession.value.status === "provisioning") {
      startLabPolling();
    }
    void refreshSnapshotStatus({ silent: true });
    Notify.create({
      type: payload.status === "ready" ? "positive" : "info",
      message:
        payload.status === "ready"
          ? "Your Jupyter sandbox is ready."
          : "Creating your Jupyter sandbox pod.",
    });
  } catch (error) {
    stopLabPolling();
    Notify.create({
      type: "negative",
      message: error.message,
    });
  } finally {
    sessionLoading.value = false;
  }
}

async function stopLabSession() {
  if (!isUser.value || !managedUsername.value || sessionLoading.value) {
    return;
  }

  sessionLoading.value = true;
  try {
    const response = await fetch(
      `${apiBaseUrl}/api/jupyter/sessions/${encodeURIComponent(managedUsername.value)}`,
      {
        method: "DELETE",
        headers: authHeaders(),
      },
    );
    const payload = await parseJson(response);
    labSession.value = {
      ...emptyLabSession(),
      ...payload,
    };
    stopLabPolling();
    void refreshSnapshotStatus({ silent: true });
    Notify.create({
      type: "warning",
      message: "Your Jupyter sandbox resources were deleted.",
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

async function refreshSnapshotStatus(options = {}) {
  if (!isUser.value || !managedUsername.value || snapshotLoading.value) {
    return;
  }

  snapshotLoading.value = true;
  try {
    const response = await fetch(
      `${apiBaseUrl}/api/jupyter/snapshots/${encodeURIComponent(managedUsername.value)}`,
      {
        headers: authHeaders(),
      },
    );
    const payload = await parseJson(response);
    snapshotState.value = {
      ...emptySnapshotState(),
      ...payload,
    };
    if (!options.silent && payload.status === "missing") {
      Notify.create({
        type: "info",
        message: "No Harbor snapshot exists for this user yet.",
      });
    }
  } catch (error) {
    Notify.create({
      type: "negative",
      message: error.message,
    });
  } finally {
    snapshotLoading.value = false;
  }
}

async function publishSnapshot() {
  if (!isUser.value || !managedUsername.value || snapshotLoading.value) {
    return;
  }

  snapshotLoading.value = true;
  try {
    const response = await fetch(`${apiBaseUrl}/api/jupyter/snapshots`, {
      method: "POST",
      headers: authHeaders({
        "Content-Type": "application/json",
      }),
      body: JSON.stringify({
        username: managedUsername.value,
      }),
    });
    const payload = await parseJson(response);
    snapshotState.value = {
      ...emptySnapshotState(),
      ...payload,
    };
    Notify.create({
      type: payload.status === "building" ? "info" : "positive",
      message:
        payload.status === "building"
          ? "Publishing your Harbor snapshot."
          : "Latest Harbor snapshot is ready.",
    });
  } catch (error) {
    Notify.create({
      type: "negative",
      message: error.message,
    });
  } finally {
    snapshotLoading.value = false;
  }
}

async function loadAdminOverview(options = {}) {
  if (!isAdmin.value || adminLoading.value) {
    return;
  }

  adminLoading.value = true;
  try {
    const response = await fetch(`${apiBaseUrl}/api/admin/sandboxes`, {
      headers: authHeaders(),
    });
    adminOverview.value = await parseJson(response);
  } catch (error) {
    if (!options.silent) {
      Notify.create({
        type: "negative",
        message: error.message,
      });
    }
  } finally {
    adminLoading.value = false;
  }
}

async function loadControlPlaneDashboard(options = {}) {
  if (!isAdmin.value || controlPlane.value.loading) {
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
        headers: authHeaders(),
      },
    );
    const payload = await parseJson(response);
    controlPlane.value = {
      ...controlPlane.value,
      namespace: payload.summary.current_namespace,
      namespaces: payload.namespaces,
      nodes: payload.nodes,
      pods: payload.pods,
      summary: payload.summary,
    };
  } catch (error) {
    if (!options.silent) {
      Notify.create({
        type: "negative",
        message: error.message,
      });
    }
  } finally {
    controlPlane.value = {
      ...controlPlane.value,
      loading: false,
    };
  }
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
  await loadDemoUsers();
  await loadDashboard();
  await runFirstQuery();
  await restoreAuthSession();

  if (isUser.value) {
    await refreshLabSession({ silent: true, skipSnapshotRefresh: true });
    await refreshSnapshotStatus({ silent: true });
  }

  if (isAdmin.value) {
    await loadAdminOverview({ silent: true });
    await loadControlPlaneDashboard({ silent: true });
    startAdminPolling();
  }
});

onUnmounted(() => {
  stopLabPolling();
  stopAdminPolling();
});
</script>
