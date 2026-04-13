<template>
  <q-layout view="lHh Lpr lFf" class="app-layout">
    <q-header v-if="isAuthenticated" bordered class="header-shell">
      <q-toolbar class="toolbar-shell">
        <div class="toolbar-brand">
          <div class="brand-eyebrow">Analysis Environment Server</div>
          <div class="brand-title">platform.local Jupyter 운영 포털</div>
        </div>
        <q-space />
        <div class="toolbar-user">
          <q-chip square color="white" text-color="dark" icon="person">
            {{ appSession.user.display_name }} ({{ appSession.user.role }})
          </q-chip>
          <q-btn
            flat
            dense
            color="negative"
            no-caps
            icon="logout"
            label="로그아웃"
            :loading="authLoading"
            @click="logoutApp"
          />
        </div>
      </q-toolbar>
    </q-header>

    <q-page-container>
      <q-page class="page-shell">
        <section v-if="!isAuthenticated" class="login-shell">
          <q-card flat class="surface-card login-card">
            <q-card-section>
              <div class="section-eyebrow">금감원 DX 중장기 사업</div>
              <h1 class="hero-title">Jupyter 분석환경 로그인</h1>
              <p class="hero-description">
                문서 기준 분석환경 서버 흐름으로 구성된 포털입니다. 로그인 후 사용자 신청,
                관리자 승인, 개인 JupyterLab 실행/접속을 처리합니다.
              </p>

              <div class="login-grid">
                <q-input
                  v-model="loginForm.username"
                  dense
                  outlined
                  color="dark"
                  label="Username"
                  @keyup.enter="loginApp"
                />
                <q-input
                  v-model="loginForm.password"
                  dense
                  outlined
                  color="dark"
                  label="Password"
                  type="password"
                  @keyup.enter="loginApp"
                />
                <q-btn
                  color="dark"
                  unelevated
                  no-caps
                  icon="login"
                  label="로그인"
                  :loading="authLoading"
                  :disable="!canLogin"
                  @click="loginApp"
                />
              </div>

              <q-separator class="q-my-md" />
              <div class="section-eyebrow">데모 계정</div>
              <div class="account-grid">
                <q-btn
                  v-for="account in demoAccounts"
                  :key="account.username"
                  outline
                  color="dark"
                  no-caps
                  :label="`${account.display_name} (${account.username})`"
                  @click="applyDemoAccount(account)"
                />
              </div>
            </q-card-section>
          </q-card>
        </section>

        <template v-else>
          <section class="hero-panel surface-card">
            <div class="hero-header">
              <div>
                <div class="section-eyebrow">Workflow</div>
                <h2>신청 · 승인 · 실행 · 접속</h2>
                <p>
                  사용자는 리소스/분석환경을 신청하고, 관리자는 승인 후 개인 전용 Jupyter Pod를
                  실행할 수 있습니다. 실행 후 소유권 검증을 거쳐 개인 URL로 연결됩니다.
                </p>
              </div>
              <div class="hero-actions">
                <q-btn
                  outline
                  color="dark"
                  no-caps
                  icon="refresh"
                  label="전체 새로고침"
                  :loading="pageLoading"
                  @click="loadPageData"
                />
              </div>
            </div>

            <div class="workflow-steps">
              <div class="step-chip">1. 리소스 신청</div>
              <div class="step-chip">2. 분석환경 신청</div>
              <div class="step-chip">3. 관리자 승인</div>
              <div class="step-chip">4. JupyterLab 실행/접속</div>
            </div>
          </section>

          <section class="kpi-grid">
            <q-card v-for="card in topMetrics" :key="card.key" flat class="surface-card kpi-card">
              <q-card-section>
                <div class="kpi-label">{{ card.label }}</div>
                <div class="kpi-value">{{ card.value }}</div>
                <div class="kpi-note">{{ card.note }}</div>
              </q-card-section>
            </q-card>
          </section>

          <section class="main-grid">
            <q-card flat class="surface-card">
              <q-card-section>
                <div class="section-eyebrow">My JupyterLab</div>
                <div class="section-title">개인 분석환경 실행</div>

                <div class="chip-grid q-mt-sm">
                  <q-chip color="white" text-color="dark" square>
                    <strong>User</strong>&nbsp;{{ managedUsername }}
                  </q-chip>
                  <q-chip color="white" text-color="dark" square>
                    <strong>Status</strong>&nbsp;{{ labSession.status }}
                  </q-chip>
                  <q-chip color="white" text-color="dark" square>
                    <strong>Ready</strong>&nbsp;{{ labSession.ready ? "yes" : "no" }}
                  </q-chip>
                </div>

                <div class="lab-form">
                  <q-btn
                    color="dark"
                    unelevated
                    no-caps
                    icon="rocket_launch"
                    label="내 환경 실행"
                    :loading="sessionLoading"
                    @click="startLabSession"
                  />
                  <q-btn
                    outline
                    color="dark"
                    no-caps
                    icon="sync"
                    label="상태 새로고침"
                    :loading="sessionLoading"
                    @click="refreshLabSession"
                  />
                  <q-btn
                    outline
                    color="dark"
                    no-caps
                    icon="open_in_new"
                    label="Jupyter 열기"
                    :disable="!labSession.ready"
                    @click="openLab"
                  />
                  <q-btn
                    flat
                    color="negative"
                    no-caps
                    icon="delete"
                    label="환경 종료"
                    :loading="sessionLoading"
                    @click="stopLabSession"
                  />
                </div>

                <q-banner rounded class="banner-note q-mt-md">
                  <div><strong>Detail:</strong> {{ labSession.detail }}</div>
                  <div v-if="labSession.pod_name"><strong>Pod:</strong> {{ labSession.pod_name }}</div>
                  <div v-if="labSession.service_name"><strong>Service:</strong> {{ labSession.service_name }}</div>
                  <div v-if="labSession.workspace_subpath">
                    <strong>Workspace:</strong> {{ labSession.workspace_subpath }}
                  </div>
                  <div v-if="labSession.image" class="mono-line"><strong>Image:</strong> {{ labSession.image }}</div>
                  <div v-if="labLaunchUrl" class="mono-line"><strong>URL:</strong> {{ labLaunchUrl }}</div>
                </q-banner>
              </q-card-section>
            </q-card>

            <q-card flat class="surface-card">
              <q-card-section>
                <div class="section-eyebrow">Policy</div>
                <div class="section-title">리소스/환경 승인 정책</div>

                <div class="chip-grid q-mt-sm">
                  <q-chip color="white" text-color="dark" square>
                    <strong>governance</strong>&nbsp;{{ userLabPolicy.governance_enabled ? "on" : "off" }}
                  </q-chip>
                  <q-chip color="white" text-color="dark" square>
                    <strong>ready</strong>&nbsp;{{ userLabPolicy.ready ? "yes" : "no" }}
                  </q-chip>
                  <q-chip v-if="userLabPolicy.vcpu" color="white" text-color="dark" square>
                    <strong>vcpu</strong>&nbsp;{{ userLabPolicy.vcpu }}
                  </q-chip>
                  <q-chip v-if="userLabPolicy.memory_gib" color="white" text-color="dark" square>
                    <strong>memory</strong>&nbsp;{{ userLabPolicy.memory_gib }}Gi
                  </q-chip>
                  <q-chip v-if="userLabPolicy.disk_gib" color="white" text-color="dark" square>
                    <strong>disk</strong>&nbsp;{{ userLabPolicy.disk_gib }}Gi
                  </q-chip>
                </div>

                <q-banner rounded class="banner-note q-mt-md">
                  <div>{{ userLabPolicy.detail }}</div>
                  <div v-if="userLabPolicy.pvc_name"><strong>PVC:</strong> {{ userLabPolicy.pvc_name }}</div>
                  <div v-if="userLabPolicy.analysis_env_id">
                    <strong>Env:</strong> {{ userLabPolicy.analysis_env_id }}
                  </div>
                  <div v-if="userLabPolicy.analysis_image" class="mono-line">
                    <strong>Image:</strong> {{ userLabPolicy.analysis_image }}
                  </div>
                </q-banner>

                <q-separator class="q-my-md" />

                <div class="section-eyebrow">Usage (Chart.js)</div>
                <div class="section-title">내 사용 통계</div>
                <div class="chip-grid q-mt-sm">
                  <q-chip color="white" text-color="dark" square>
                    login {{ usageSummary.login_count }}
                  </q-chip>
                  <q-chip color="white" text-color="dark" square>
                    launch {{ usageSummary.launch_count }}
                  </q-chip>
                  <q-chip color="white" text-color="dark" square>
                    total {{ formatDuration(usageSummary.total_session_seconds) }}
                  </q-chip>
                </div>
                <div class="chart-shell q-mt-sm">
                  <canvas ref="usageChartCanvas" />
                </div>
              </q-card-section>
            </q-card>
          </section>

          <section class="table-grid" v-if="isUser">
            <q-card flat class="surface-card">
              <q-card-section>
                <div class="section-eyebrow">Step 1</div>
                <div class="section-title">리소스 신청</div>

                <div class="form-grid q-mt-sm">
                  <q-input v-model.number="resourceRequestForm.vcpu" type="number" dense outlined label="vCPU" color="dark" />
                  <q-input v-model.number="resourceRequestForm.memory_gib" type="number" dense outlined label="Memory (GiB)" color="dark" />
                  <q-input v-model.number="resourceRequestForm.disk_gib" type="number" dense outlined label="Disk (GiB)" color="dark" />
                </div>
                <q-input
                  v-model="resourceRequestForm.note"
                  dense
                  outlined
                  color="dark"
                  type="textarea"
                  autogrow
                  label="요청 메모"
                  class="q-mt-sm"
                />
                <div class="lab-form">
                  <q-btn
                    color="dark"
                    unelevated
                    no-caps
                    icon="send"
                    label="리소스 신청"
                    :loading="governanceLoading"
                    :disable="!canSubmitResource"
                    @click="submitResourceRequest"
                  />
                </div>

                <q-separator class="q-my-md" />

                <q-table
                  flat
                  :rows="userResourceRequests"
                  :columns="userResourceRequestColumns"
                  row-key="request_id"
                  :rows-per-page-options="[5, 10, 20]"
                  :pagination="{ rowsPerPage: 5 }"
                >
                  <template #body-cell-status="props">
                    <q-td :props="props">
                      <q-badge rounded :color="requestStatusColor(props.value)">{{ props.value }}</q-badge>
                    </q-td>
                  </template>
                  <template #body-cell-updated_at="props">
                    <q-td :props="props">{{ formatDateTime(props.value) }}</q-td>
                  </template>
                  <template #body-cell-review_note="props">
                    <q-td :props="props">{{ props.value || "-" }}</q-td>
                  </template>
                </q-table>
              </q-card-section>
            </q-card>

            <q-card flat class="surface-card">
              <q-card-section>
                <div class="section-eyebrow">Step 2</div>
                <div class="section-title">분석환경 신청</div>

                <q-select
                  v-model="environmentRequestForm.env_id"
                  dense
                  outlined
                  color="dark"
                  emit-value
                  map-options
                  option-label="label"
                  option-value="value"
                  :options="analysisEnvironmentOptions"
                  label="Analysis Environment"
                  class="q-mt-sm"
                />
                <q-input
                  v-model="environmentRequestForm.note"
                  dense
                  outlined
                  color="dark"
                  type="textarea"
                  autogrow
                  label="요청 메모"
                  class="q-mt-sm"
                />
                <div class="lab-form">
                  <q-btn
                    color="dark"
                    unelevated
                    no-caps
                    icon="send"
                    label="환경 신청"
                    :loading="governanceLoading"
                    :disable="!canSubmitEnvironment"
                    @click="submitEnvironmentRequest"
                  />
                </div>

                <q-separator class="q-my-md" />

                <q-table
                  flat
                  :rows="userEnvironmentRequests"
                  :columns="userEnvironmentRequestColumns"
                  row-key="request_id"
                  :rows-per-page-options="[5, 10, 20]"
                  :pagination="{ rowsPerPage: 5 }"
                >
                  <template #body-cell-status="props">
                    <q-td :props="props">
                      <q-badge rounded :color="requestStatusColor(props.value)">{{ props.value }}</q-badge>
                    </q-td>
                  </template>
                  <template #body-cell-updated_at="props">
                    <q-td :props="props">{{ formatDateTime(props.value) }}</q-td>
                  </template>
                  <template #body-cell-review_note="props">
                    <q-td :props="props">{{ props.value || "-" }}</q-td>
                  </template>
                </q-table>
              </q-card-section>
            </q-card>
          </section>

          <section v-if="isAdmin" class="table-grid">
            <q-card flat class="surface-card">
              <q-card-section>
                <div class="section-eyebrow">Admin Governance</div>
                <div class="section-title">신청 승인 처리</div>

                <div class="chip-grid q-mt-sm">
                  <q-chip color="white" text-color="dark" square>
                    resource pending {{ pendingResourceRequests.length }}
                  </q-chip>
                  <q-chip color="white" text-color="dark" square>
                    environment pending {{ pendingEnvironmentRequests.length }}
                  </q-chip>
                </div>

                <q-separator class="q-my-md" />

                <div class="section-subtitle">리소스 신청 승인</div>
                <q-table
                  flat
                  :rows="pendingResourceRequests"
                  :columns="adminResourceRequestColumns"
                  row-key="request_id"
                  :rows-per-page-options="[5, 10, 20]"
                  :pagination="{ rowsPerPage: 5 }"
                >
                  <template #body-cell-status="props">
                    <q-td :props="props">
                      <q-badge rounded :color="requestStatusColor(props.value)">{{ props.value }}</q-badge>
                    </q-td>
                  </template>
                  <template #body-cell-actions="props">
                    <q-td :props="props" class="actions-cell">
                      <q-btn dense flat color="positive" icon="check" @click="reviewResourceRequest(props.row, true)" />
                      <q-btn dense flat color="negative" icon="close" @click="reviewResourceRequest(props.row, false)" />
                    </q-td>
                  </template>
                </q-table>

                <q-separator class="q-my-md" />

                <div class="section-subtitle">분석환경 신청 승인</div>
                <q-table
                  flat
                  :rows="pendingEnvironmentRequests"
                  :columns="adminEnvironmentRequestColumns"
                  row-key="request_id"
                  :rows-per-page-options="[5, 10, 20]"
                  :pagination="{ rowsPerPage: 5 }"
                >
                  <template #body-cell-status="props">
                    <q-td :props="props">
                      <q-badge rounded :color="requestStatusColor(props.value)">{{ props.value }}</q-badge>
                    </q-td>
                  </template>
                  <template #body-cell-actions="props">
                    <q-td :props="props" class="actions-cell">
                      <q-btn dense flat color="positive" icon="check" @click="reviewEnvironmentRequest(props.row, true)" />
                      <q-btn dense flat color="negative" icon="close" @click="reviewEnvironmentRequest(props.row, false)" />
                    </q-td>
                  </template>
                </q-table>
              </q-card-section>
            </q-card>

            <q-card flat class="surface-card">
              <q-card-section>
                <div class="section-eyebrow">Admin Provisioning</div>
                <div class="section-title">사용자/이미지 등록</div>

                <div class="section-subtitle q-mt-sm">사용자 생성</div>
                <div class="form-grid q-mt-xs">
                  <q-input v-model="adminUserForm.username" dense outlined color="dark" label="Username" />
                  <q-input v-model="adminUserForm.display_name" dense outlined color="dark" label="Display Name" />
                  <q-input v-model="adminUserForm.password" dense outlined color="dark" label="Password" type="password" />
                  <q-select v-model="adminUserForm.role" dense outlined color="dark" :options="['user', 'admin']" label="Role" />
                </div>
                <div class="lab-form">
                  <q-btn
                    color="dark"
                    unelevated
                    no-caps
                    icon="person_add"
                    label="사용자 생성"
                    :loading="governanceAdminLoading"
                    :disable="!canCreateUser"
                    @click="createManagedUser"
                  />
                </div>

                <q-separator class="q-my-md" />

                <div class="section-subtitle">분석환경 이미지 등록</div>
                <div class="form-grid q-mt-xs">
                  <q-input v-model="adminEnvironmentForm.env_id" dense outlined color="dark" label="env_id" />
                  <q-input v-model="adminEnvironmentForm.name" dense outlined color="dark" label="Name" />
                  <q-input v-model="adminEnvironmentForm.image" dense outlined color="dark" label="Image" class="wide-cell" />
                  <q-input v-model="adminEnvironmentForm.description" dense outlined color="dark" label="Description" class="wide-cell" />
                  <q-toggle v-model="adminEnvironmentForm.gpu_enabled" label="GPU Enabled" color="dark" />
                  <q-toggle v-model="adminEnvironmentForm.is_active" label="Active" color="dark" />
                </div>
                <div class="lab-form">
                  <q-btn
                    color="dark"
                    unelevated
                    no-caps
                    icon="inventory_2"
                    label="환경 등록/수정"
                    :loading="governanceAdminLoading"
                    :disable="!canUpsertEnvironment"
                    @click="upsertAnalysisEnvironment"
                  />
                </div>

                <q-separator class="q-my-md" />
                <q-table
                  flat
                  :rows="adminAnalysisEnvironments"
                  :columns="adminEnvironmentColumns"
                  row-key="env_id"
                  :rows-per-page-options="[5, 10, 20]"
                  :pagination="{ rowsPerPage: 5 }"
                >
                  <template #body-cell-is_active="props">
                    <q-td :props="props">
                      <q-badge rounded :color="props.value ? 'positive' : 'grey-7'">
                        {{ props.value ? "active" : "inactive" }}
                      </q-badge>
                    </q-td>
                  </template>
                </q-table>
              </q-card-section>
            </q-card>

            <q-card flat class="surface-card">
              <q-card-section>
                <div class="section-eyebrow">Admin Monitor</div>
                <div class="section-title">사용자별 Sandbox 현황</div>

                <div class="chip-grid q-mt-sm">
                  <q-chip color="white" text-color="dark" square>
                    users {{ adminOverview.summary.sandbox_user_count || 0 }}
                  </q-chip>
                  <q-chip color="white" text-color="dark" square>
                    running {{ adminOverview.summary.running_user_count || 0 }}
                  </q-chip>
                  <q-chip color="white" text-color="dark" square>
                    ready {{ adminOverview.summary.ready_user_count || 0 }}
                  </q-chip>
                </div>

                <div class="chart-shell q-mt-sm">
                  <canvas ref="adminChartCanvas" />
                </div>

                <q-table
                  flat
                  :rows="adminOverview.users"
                  :columns="adminSandboxColumns"
                  row-key="username"
                  :rows-per-page-options="[5, 10, 20]"
                  :pagination="{ rowsPerPage: 5 }"
                  class="q-mt-sm"
                >
                  <template #body-cell-status="props">
                    <q-td :props="props">
                      <q-badge rounded :color="labStatusColor(props.value)">{{ props.value }}</q-badge>
                    </q-td>
                  </template>
                </q-table>
              </q-card-section>
            </q-card>

            <q-card flat class="surface-card">
              <q-card-section>
                <div class="section-eyebrow">Control Plane</div>
                <div class="section-title">노드/팟 인벤토리</div>

                <div class="lab-form q-mt-sm">
                  <q-input
                    v-model="controlPlaneNamespace"
                    dense
                    outlined
                    color="dark"
                    label="Namespace (all 또는 이름)"
                    class="namespace-input"
                  />
                  <q-btn
                    outline
                    color="dark"
                    no-caps
                    icon="sync"
                    label="Control Plane 새로고침"
                    :loading="controlPlaneLoading"
                    @click="loadControlPlane"
                  />
                </div>

                <q-banner rounded class="banner-note q-mt-md">
                  <div><strong>Cluster:</strong> {{ controlPlane.summary.cluster_name || "-" }}</div>
                  <div><strong>Version:</strong> {{ controlPlane.summary.cluster_version || "-" }}</div>
                  <div><strong>Nodes:</strong> {{ controlPlane.summary.ready_node_count || 0 }}/{{ controlPlane.summary.node_count || 0 }}</div>
                  <div><strong>Pods:</strong> {{ controlPlane.summary.running_pod_count || 0 }}/{{ controlPlane.summary.pod_count || 0 }}</div>
                </q-banner>

                <q-separator class="q-my-md" />

                <div class="section-subtitle">Nodes</div>
                <q-table
                  flat
                  :rows="controlPlane.nodes"
                  :columns="controlPlaneNodeColumns"
                  row-key="name"
                  :rows-per-page-options="[5, 10, 20]"
                  :pagination="{ rowsPerPage: 5 }"
                >
                  <template #body-cell-ready="props">
                    <q-td :props="props">
                      <q-badge rounded :color="props.value ? 'positive' : 'negative'">
                        {{ props.value ? "ready" : "not-ready" }}
                      </q-badge>
                    </q-td>
                  </template>
                </q-table>
              </q-card-section>
            </q-card>
          </section>
        </template>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from "vue";
import axios from "axios";
import {
  BarElement,
  CategoryScale,
  Chart,
  DoughnutController,
  ArcElement,
  Legend,
  LinearScale,
  Tooltip,
} from "chart.js";
import { useQuasar } from "quasar";

Chart.register(
  BarElement,
  CategoryScale,
  DoughnutController,
  ArcElement,
  Legend,
  LinearScale,
  Tooltip,
);

const AUTH_TOKEN_KEY = "platform.auth.token";
const $q = useQuasar();

function resolveApiBaseUrl() {
  const envValue = String(import.meta.env.VITE_API_BASE_URL || "").trim();
  if (envValue) return envValue.replace(/\/+$/, "");
  if (typeof window !== "undefined") {
    const host = window.location.hostname;
    if (host.includes("platform.local")) {
      if (host.startsWith("dev.")) return `${window.location.protocol}//dev-api.platform.local`;
      if (host.startsWith("www.")) return `${window.location.protocol}//api.platform.local`;
      return `${window.location.protocol}//api.platform.local`;
    }
    return window.location.origin;
  }
  return "http://api.platform.local";
}

const api = axios.create({
  baseURL: resolveApiBaseUrl(),
  timeout: 15000,
});

const authToken = ref(localStorage.getItem(AUTH_TOKEN_KEY) || "");
api.interceptors.request.use((config) => {
  if (authToken.value) {
    config.headers = {
      ...config.headers,
      Authorization: `Bearer ${authToken.value}`,
      "X-Auth-Token": authToken.value,
    };
  }
  return config;
});

const loginForm = reactive({
  username: "",
  password: "",
});

const demoAccounts = [
  { username: "admin@test.com", password: "123456", display_name: "Platform Admin" },
  { username: "test1@test.com", password: "123456", display_name: "Test User 1" },
];

const appSession = reactive({
  user: {
    username: "",
    display_name: "",
    role: "user",
  },
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

const labSession = reactive({
  status: "idle",
  ready: false,
  detail: "로그인 후 개인 환경을 실행할 수 있습니다.",
  pod_name: "",
  service_name: "",
  workspace_subpath: "",
  image: "",
  token: "",
});

const userLabPolicy = reactive({
  governance_enabled: true,
  ready: false,
  detail: "정책 정보를 불러오는 중입니다.",
  vcpu: null,
  memory_gib: null,
  disk_gib: null,
  pvc_name: null,
  analysis_env_id: null,
  analysis_image: null,
});

const usageSummary = reactive({
  current_status: "idle",
  login_count: 0,
  launch_count: 0,
  current_session_seconds: 0,
  total_session_seconds: 0,
  pod_name: "",
  last_login_at: null,
  last_launch_at: null,
  last_stop_at: null,
});

const userResourceRequests = ref([]);
const userEnvironmentRequests = ref([]);
const analysisEnvironments = ref([]);

const adminManagedUsers = ref([]);
const adminAnalysisEnvironments = ref([]);
const adminResourceRequests = ref([]);
const adminEnvironmentRequests = ref([]);

const adminOverview = ref({
  summary: {
    sandbox_user_count: 0,
    running_user_count: 0,
    ready_user_count: 0,
    total_login_count: 0,
    total_launch_count: 0,
    total_session_seconds: 0,
  },
  users: [],
});

const controlPlane = ref({
  summary: {
    cluster_name: "-",
    cluster_version: "-",
    current_namespace: "all",
    namespace_count: 0,
    node_count: 0,
    ready_node_count: 0,
    pod_count: 0,
    running_pod_count: 0,
  },
  namespaces: [],
  nodes: [],
  pods: [],
});

const controlPlaneNamespace = ref("all");

const resourceRequestForm = reactive({
  vcpu: 2,
  memory_gib: 2,
  disk_gib: 10,
  note: "",
});

const environmentRequestForm = reactive({
  env_id: "",
  note: "",
});

const adminUserForm = reactive({
  username: "",
  display_name: "",
  password: "",
  role: "user",
});

const adminEnvironmentForm = reactive({
  env_id: "",
  name: "",
  image: "",
  description: "",
  gpu_enabled: false,
  is_active: true,
});

const authLoading = ref(false);
const pageLoading = ref(false);
const sessionLoading = ref(false);
const governanceLoading = ref(false);
const governanceAdminLoading = ref(false);
const controlPlaneLoading = ref(false);

const labLaunchUrl = ref("");
const usageChartCanvas = ref(null);
const adminChartCanvas = ref(null);
let usageChart = null;
let adminChart = null;

const isAuthenticated = computed(() => Boolean(appSession.user.username));
const isAdmin = computed(() => appSession.user.role === "admin");
const isUser = computed(() => isAuthenticated.value && appSession.user.role !== "admin");
const managedUsername = computed(() => appSession.user.username || "");
const canLogin = computed(() => Boolean(loginForm.username.trim() && loginForm.password.trim()));

const canSubmitResource = computed(() =>
  Boolean(
    Number(resourceRequestForm.vcpu) > 0 &&
      Number(resourceRequestForm.memory_gib) > 0 &&
      Number(resourceRequestForm.disk_gib) > 0,
  ),
);

const canSubmitEnvironment = computed(() => Boolean(environmentRequestForm.env_id));

const canCreateUser = computed(() =>
  Boolean(
    adminUserForm.username.trim() &&
      adminUserForm.display_name.trim() &&
      adminUserForm.password.trim() &&
      adminUserForm.role,
  ),
);

const canUpsertEnvironment = computed(() =>
  Boolean(
    adminEnvironmentForm.env_id.trim() &&
      adminEnvironmentForm.name.trim() &&
      adminEnvironmentForm.image.trim(),
  ),
);

const pendingResourceRequests = computed(() =>
  adminResourceRequests.value.filter((item) => item.status === "pending"),
);
const pendingEnvironmentRequests = computed(() =>
  adminEnvironmentRequests.value.filter((item) => item.status === "pending"),
);

const topMetrics = computed(() => {
  const summary = adminOverview.value.summary || {};
  return [
    {
      key: "status",
      label: "내 상태",
      value: labSession.status || "idle",
      note: userLabPolicy.ready ? "Jupyter 실행 가능" : "승인 필요",
    },
    {
      key: "logins",
      label: "내 로그인 횟수",
      value: usageSummary.login_count || 0,
      note: `launch ${usageSummary.launch_count || 0}`,
    },
    {
      key: "running",
      label: "실행 사용자 수",
      value: summary.running_user_count || 0,
      note: `ready ${summary.ready_user_count || 0}`,
    },
    {
      key: "pending",
      label: "대기 승인",
      value: pendingResourceRequests.value.length + pendingEnvironmentRequests.value.length,
      note: `resource ${pendingResourceRequests.value.length}, env ${pendingEnvironmentRequests.value.length}`,
    },
  ];
});

const analysisEnvironmentOptions = computed(() =>
  analysisEnvironments.value.map((item) => ({
    value: item.env_id,
    label: `${item.name} (${item.env_id})`,
  })),
);

const userResourceRequestColumns = [
  { name: "request_id", label: "요청ID", field: "request_id", align: "left" },
  { name: "vcpu", label: "vCPU", field: "vcpu", align: "right" },
  { name: "memory_gib", label: "Mem", field: "memory_gib", align: "right" },
  { name: "disk_gib", label: "Disk", field: "disk_gib", align: "right" },
  { name: "status", label: "상태", field: "status", align: "left" },
  { name: "updated_at", label: "갱신시각", field: "updated_at", align: "left" },
  { name: "review_note", label: "리뷰메모", field: "review_note", align: "left" },
];

const userEnvironmentRequestColumns = [
  { name: "request_id", label: "요청ID", field: "request_id", align: "left" },
  { name: "env_id", label: "Env", field: "env_id", align: "left" },
  { name: "status", label: "상태", field: "status", align: "left" },
  { name: "updated_at", label: "갱신시각", field: "updated_at", align: "left" },
  { name: "review_note", label: "리뷰메모", field: "review_note", align: "left" },
];

const adminResourceRequestColumns = [
  { name: "request_id", label: "요청ID", field: "request_id", align: "left" },
  { name: "username", label: "사용자", field: "username", align: "left" },
  { name: "vcpu", label: "vCPU", field: "vcpu", align: "right" },
  { name: "memory_gib", label: "Mem", field: "memory_gib", align: "right" },
  { name: "disk_gib", label: "Disk", field: "disk_gib", align: "right" },
  { name: "status", label: "상태", field: "status", align: "left" },
  { name: "actions", label: "액션", field: "actions", align: "left" },
];

const adminEnvironmentRequestColumns = [
  { name: "request_id", label: "요청ID", field: "request_id", align: "left" },
  { name: "username", label: "사용자", field: "username", align: "left" },
  { name: "env_id", label: "Env", field: "env_id", align: "left" },
  { name: "status", label: "상태", field: "status", align: "left" },
  { name: "actions", label: "액션", field: "actions", align: "left" },
];

const adminEnvironmentColumns = [
  { name: "env_id", label: "Env ID", field: "env_id", align: "left" },
  { name: "name", label: "Name", field: "name", align: "left" },
  { name: "image", label: "Image", field: "image", align: "left" },
  { name: "is_active", label: "Active", field: "is_active", align: "left" },
];

const adminSandboxColumns = [
  { name: "username", label: "사용자", field: "username", align: "left" },
  { name: "status", label: "상태", field: "status", align: "left" },
  { name: "pod_name", label: "Pod", field: "pod_name", align: "left" },
  { name: "login_count", label: "로그인", field: "login_count", align: "right" },
  { name: "launch_count", label: "실행", field: "launch_count", align: "right" },
  { name: "total_session_seconds", label: "총사용(초)", field: "total_session_seconds", align: "right" },
];

const controlPlaneNodeColumns = [
  { name: "name", label: "Node", field: "name", align: "left" },
  { name: "ready", label: "Ready", field: "ready", align: "left" },
  { name: "roles", label: "Roles", field: "roles", align: "left" },
  { name: "version", label: "Version", field: "version", align: "left" },
  { name: "internal_ip", label: "IP", field: "internal_ip", align: "left" },
];

function notifyPositive(message) {
  $q.notify({ type: "positive", position: "top", message });
}

function notifyError(error, fallback = "요청 처리 중 오류가 발생했습니다.") {
  const detail =
    error?.response?.data?.detail || error?.response?.data?.message || error?.message || fallback;
  $q.notify({
    type: "negative",
    position: "top",
    timeout: 3500,
    message: String(detail),
  });
}

function requestStatusColor(status) {
  const value = String(status || "").toLowerCase();
  if (value === "approved") return "positive";
  if (value === "rejected") return "negative";
  return "warning";
}

function labStatusColor(status) {
  const value = String(status || "").toLowerCase();
  if (value === "ready") return "positive";
  if (value === "provisioning") return "warning";
  if (value === "deleted") return "grey-7";
  return "indigo";
}

function formatDateTime(value) {
  if (!value) return "-";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat("ko-KR", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(date);
}

function formatDuration(seconds) {
  const sec = Math.max(0, Number(seconds || 0));
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  if (h > 0) return `${h}h ${m}m ${s}s`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

function applyDemoAccount(account) {
  loginForm.username = account.username;
  loginForm.password = account.password;
}

async function restoreSession() {
  if (!authToken.value) return;
  try {
    const { data } = await api.get("/api/auth/me");
    appSession.user = {
      username: data?.user?.username || "",
      display_name: data?.user?.display_name || "",
      role: data?.user?.role || "user",
    };
  } catch (_error) {
    authToken.value = "";
    localStorage.removeItem(AUTH_TOKEN_KEY);
  }
}

async function loginApp() {
  if (!canLogin.value) return;
  authLoading.value = true;
  try {
    const { data } = await api.post("/api/auth/login", {
      username: loginForm.username.trim(),
      password: loginForm.password,
    });
    const token = String(data?.access_token || data?.token || "");
    if (!token) throw new Error("토큰 발급에 실패했습니다.");
    authToken.value = token;
    localStorage.setItem(AUTH_TOKEN_KEY, token);

    const me = await api.get("/api/auth/me");
    appSession.user = {
      username: me.data?.user?.username || "",
      display_name: me.data?.user?.display_name || "",
      role: me.data?.user?.role || "user",
    };

    await loadPageData();
    notifyPositive("로그인 완료");
  } catch (error) {
    notifyError(error, "로그인 실패");
  } finally {
    authLoading.value = false;
  }
}

async function logoutApp() {
  authLoading.value = true;
  try {
    if (authToken.value) {
      await api.post("/api/auth/logout");
    }
  } catch (_error) {
    // noop
  } finally {
    authToken.value = "";
    localStorage.removeItem(AUTH_TOKEN_KEY);
    appSession.user = { username: "", display_name: "", role: "user" };
    authLoading.value = false;
  }
}

async function loadDashboard() {
  const { data } = await api.get("/api/dashboard");
  dashboard.value = data || dashboard.value;
}

async function loadLabSession() {
  if (!managedUsername.value) return;
  try {
    const { data } = await api.get(`/api/jupyter/sessions/${encodeURIComponent(managedUsername.value)}`);
    Object.assign(labSession, data || {});
  } catch (error) {
    if (error?.response?.status === 400) {
      Object.assign(labSession, {
        status: "idle",
        ready: false,
        detail: error.response.data?.detail || "세션이 없습니다.",
      });
      return;
    }
    throw error;
  }
}

async function startLabSession() {
  if (!managedUsername.value) return;
  sessionLoading.value = true;
  try {
    const { data } = await api.post("/api/jupyter/sessions", { username: managedUsername.value });
    Object.assign(labSession, data || {});
    notifyPositive(data?.ready ? "JupyterLab 준비 완료" : "JupyterLab 생성 중");
    await Promise.all([loadUsage(), loadAdminOverviewSafe()]);
  } catch (error) {
    notifyError(error, "Jupyter 실행 실패");
  } finally {
    sessionLoading.value = false;
  }
}

async function refreshLabSession() {
  if (!managedUsername.value) return;
  sessionLoading.value = true;
  try {
    await loadLabSession();
    await Promise.all([loadUsage(), loadAdminOverviewSafe()]);
  } catch (error) {
    notifyError(error, "세션 상태 조회 실패");
  } finally {
    sessionLoading.value = false;
  }
}

async function stopLabSession() {
  if (!managedUsername.value) return;
  sessionLoading.value = true;
  try {
    const { data } = await api.delete(`/api/jupyter/sessions/${encodeURIComponent(managedUsername.value)}`);
    Object.assign(labSession, data || {});
    notifyPositive("JupyterLab 자원 종료 완료");
    await Promise.all([loadUsage(), loadAdminOverviewSafe()]);
  } catch (error) {
    notifyError(error, "세션 종료 실패");
  } finally {
    sessionLoading.value = false;
  }
}

async function openLab() {
  if (!managedUsername.value) return;
  try {
    const { data } = await api.get(`/api/jupyter/connect/${encodeURIComponent(managedUsername.value)}`);
    if (!data?.redirect_url) throw new Error("연결 URL이 없습니다.");
    labLaunchUrl.value = data.redirect_url;
    window.open(data.redirect_url, "_blank", "noopener");
    notifyPositive("새 탭에서 JupyterLab을 엽니다.");
  } catch (error) {
    notifyError(error, "Jupyter 연결 실패");
  }
}

async function loadUsage() {
  if (!managedUsername.value) return;
  const { data } = await api.get("/api/users/me/usage");
  Object.assign(usageSummary, data?.summary || {});
  await nextTick();
  renderUsageChart();
}

async function loadLabPolicy() {
  const { data } = await api.get("/api/users/me/lab-policy");
  Object.assign(userLabPolicy, data || {});
}

async function loadUserGovernanceData() {
  const [resourceResp, environmentResp, envResp] = await Promise.all([
    api.get("/api/resource-requests/me"),
    api.get("/api/environment-requests/me"),
    api.get("/api/analysis-environments"),
  ]);

  userResourceRequests.value = resourceResp.data?.items || [];
  userEnvironmentRequests.value = environmentResp.data?.items || [];
  analysisEnvironments.value = envResp.data?.items || [];

  if (!environmentRequestForm.env_id) {
    environmentRequestForm.env_id = analysisEnvironments.value[0]?.env_id || "";
  }
}

async function submitResourceRequest() {
  if (!canSubmitResource.value) return;
  governanceLoading.value = true;
  try {
    await api.post("/api/resource-requests", {
      vcpu: Number(resourceRequestForm.vcpu),
      memory_gib: Number(resourceRequestForm.memory_gib),
      disk_gib: Number(resourceRequestForm.disk_gib),
      note: resourceRequestForm.note || "",
    });
    resourceRequestForm.note = "";
    await Promise.all([loadUserGovernanceData(), loadLabPolicy()]);
    notifyPositive("리소스 신청 완료");
  } catch (error) {
    notifyError(error, "리소스 신청 실패");
  } finally {
    governanceLoading.value = false;
  }
}

async function submitEnvironmentRequest() {
  if (!canSubmitEnvironment.value) return;
  governanceLoading.value = true;
  try {
    await api.post("/api/environment-requests", {
      env_id: environmentRequestForm.env_id,
      note: environmentRequestForm.note || "",
    });
    environmentRequestForm.note = "";
    await Promise.all([loadUserGovernanceData(), loadLabPolicy()]);
    notifyPositive("분석환경 신청 완료");
  } catch (error) {
    notifyError(error, "분석환경 신청 실패");
  } finally {
    governanceLoading.value = false;
  }
}

async function loadAdminGovernanceData() {
  const [usersResp, envResp, resourceResp, environmentResp] = await Promise.all([
    api.get("/api/admin/users"),
    api.get("/api/admin/analysis-environments?include_inactive=true"),
    api.get("/api/admin/resource-requests"),
    api.get("/api/admin/environment-requests"),
  ]);

  adminManagedUsers.value = usersResp.data?.items || [];
  adminAnalysisEnvironments.value = envResp.data?.items || [];
  adminResourceRequests.value = resourceResp.data?.items || [];
  adminEnvironmentRequests.value = environmentResp.data?.items || [];
}

async function loadAdminOverview() {
  const { data } = await api.get("/api/admin/sandboxes");
  adminOverview.value = data || adminOverview.value;
  await nextTick();
  renderAdminChart();
}

async function loadAdminOverviewSafe() {
  if (!isAdmin.value) return;
  try {
    await loadAdminOverview();
  } catch (_error) {
    // no-op
  }
}

async function reviewResourceRequest(item, approved) {
  const note = window.prompt(
    approved ? "승인 메모(선택)" : "반려 사유",
    approved ? "" : "정책 확인 필요",
  );
  if (note === null) return;

  governanceAdminLoading.value = true;
  try {
    await api.post(`/api/admin/resource-requests/${encodeURIComponent(item.request_id)}/review`, {
      approved,
      note,
    });
    await Promise.all([loadAdminGovernanceData(), loadAdminOverview(), loadLabPolicy()]);
    notifyPositive(approved ? "리소스 승인 완료" : "리소스 반려 완료");
  } catch (error) {
    notifyError(error, "리소스 리뷰 실패");
  } finally {
    governanceAdminLoading.value = false;
  }
}

async function reviewEnvironmentRequest(item, approved) {
  const note = window.prompt(
    approved ? "승인 메모(선택)" : "반려 사유",
    approved ? "" : "검토 필요",
  );
  if (note === null) return;

  governanceAdminLoading.value = true;
  try {
    await api.post(`/api/admin/environment-requests/${encodeURIComponent(item.request_id)}/review`, {
      approved,
      note,
    });
    await Promise.all([loadAdminGovernanceData(), loadLabPolicy()]);
    notifyPositive(approved ? "환경 승인 완료" : "환경 반려 완료");
  } catch (error) {
    notifyError(error, "환경 리뷰 실패");
  } finally {
    governanceAdminLoading.value = false;
  }
}

async function createManagedUser() {
  if (!canCreateUser.value) return;
  governanceAdminLoading.value = true;
  try {
    await api.post("/api/admin/users", {
      username: adminUserForm.username.trim(),
      password: adminUserForm.password,
      role: adminUserForm.role,
      display_name: adminUserForm.display_name.trim(),
    });
    adminUserForm.username = "";
    adminUserForm.password = "";
    adminUserForm.display_name = "";
    adminUserForm.role = "user";
    await loadAdminGovernanceData();
    notifyPositive("사용자 생성 완료");
  } catch (error) {
    notifyError(error, "사용자 생성 실패");
  } finally {
    governanceAdminLoading.value = false;
  }
}

async function upsertAnalysisEnvironment() {
  if (!canUpsertEnvironment.value) return;
  governanceAdminLoading.value = true;
  try {
    await api.post("/api/admin/analysis-environments", {
      env_id: adminEnvironmentForm.env_id.trim(),
      name: adminEnvironmentForm.name.trim(),
      image: adminEnvironmentForm.image.trim(),
      description: adminEnvironmentForm.description.trim(),
      gpu_enabled: adminEnvironmentForm.gpu_enabled,
      is_active: adminEnvironmentForm.is_active,
    });
    await Promise.all([loadAdminGovernanceData(), loadUserGovernanceData(), loadLabPolicy()]);
    notifyPositive("분석환경 등록/수정 완료");
  } catch (error) {
    notifyError(error, "분석환경 등록 실패");
  } finally {
    governanceAdminLoading.value = false;
  }
}

async function loadControlPlane() {
  if (!isAdmin.value) return;
  controlPlaneLoading.value = true;
  try {
    const namespace = (controlPlaneNamespace.value || "all").trim() || "all";
    const { data } = await api.get(`/api/control-plane/dashboard?namespace=${encodeURIComponent(namespace)}`);
    controlPlane.value = data || controlPlane.value;
  } catch (error) {
    notifyError(error, "Control Plane 조회 실패");
  } finally {
    controlPlaneLoading.value = false;
  }
}

async function loadPageData() {
  if (!isAuthenticated.value) return;
  pageLoading.value = true;
  try {
    const tasks = [
      loadDashboard(),
      loadLabSession(),
      loadUsage(),
      loadLabPolicy(),
      loadUserGovernanceData(),
    ];

    if (isAdmin.value) {
      tasks.push(loadAdminGovernanceData(), loadAdminOverview(), loadControlPlane());
    }

    await Promise.all(tasks);
  } catch (error) {
    notifyError(error, "페이지 데이터 로드 실패");
  } finally {
    pageLoading.value = false;
  }
}

function renderUsageChart() {
  if (!usageChartCanvas.value) return;
  if (usageChart) {
    usageChart.destroy();
    usageChart = null;
  }

  usageChart = new Chart(usageChartCanvas.value, {
    type: "bar",
    data: {
      labels: ["Logins", "Launches", "Current(sec)", "Total(sec)"],
      datasets: [
        {
          data: [
            usageSummary.login_count || 0,
            usageSummary.launch_count || 0,
            usageSummary.current_session_seconds || 0,
            usageSummary.total_session_seconds || 0,
          ],
          backgroundColor: ["#1f7a8c", "#2a9d8f", "#cf8a2e", "#516870"],
          borderRadius: 8,
          maxBarThickness: 52,
        },
      ],
    },
    options: {
      maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: { y: { beginAtZero: true } },
    },
  });
}

function renderAdminChart() {
  if (!adminChartCanvas.value || !isAdmin.value) return;
  if (adminChart) {
    adminChart.destroy();
    adminChart = null;
  }

  const summary = adminOverview.value.summary || {};
  adminChart = new Chart(adminChartCanvas.value, {
    type: "doughnut",
    data: {
      labels: ["Ready", "Running", "Other"],
      datasets: [
        {
          data: [
            Number(summary.ready_user_count || 0),
            Number(summary.running_user_count || 0),
            Math.max(
              0,
              Number(summary.sandbox_user_count || 0) -
                Number(summary.ready_user_count || 0) -
                Number(summary.running_user_count || 0),
            ),
          ],
          backgroundColor: ["#2a9d8f", "#1f7a8c", "#a3b0b8"],
          borderWidth: 0,
        },
      ],
    },
    options: {
      maintainAspectRatio: false,
      plugins: { legend: { position: "bottom" } },
    },
  });
}

onMounted(async () => {
  await restoreSession();
  if (isAuthenticated.value) {
    await loadPageData();
  }
});

onBeforeUnmount(() => {
  if (usageChart) {
    usageChart.destroy();
    usageChart = null;
  }
  if (adminChart) {
    adminChart.destroy();
    adminChart = null;
  }
});
</script>
