<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { Bar, Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  Title,
  Tooltip,
  Legend,
  BarElement,
  CategoryScale,
  LinearScale,
  LineElement,
  PointElement,
} from 'chart.js';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import crmReportsApi from 'dashboard/api/crm/reports';
import ReportSection from '../components/ReportSection.vue';
import { formatCurrency } from '../helpers/formatters';

// [2026-05-17] Chart.js registration top-level: chart components dependem
// dos plugins/elements estarem registrados globalmente. Idempotente —
// registrar 2x não quebra. Bar reusa elements de BarChart.vue (shared);
// Line adiciona LineElement+PointElement só usados aqui.
ChartJS.register(
  Title,
  Tooltip,
  Legend,
  BarElement,
  CategoryScale,
  LinearScale,
  LineElement,
  PointElement
);

const { t } = useI18n();
const store = useStore();

// [2026-05-17] Vuex pra pipelines (reuso do módulo crmPipelines já registrado);
// reports propriamente não tem módulo Vuex — refs locais bastam (cada relatório
// é one-shot read, sem cache cross-componente justificável). Ver brain/
// crm-pipeline-spec.md Phase 4 — decisão de não adicionar módulo.
const pipelines = useMapGetter('crmPipelines/getCrmPipelines');
const pipelinesUiFlags = useMapGetter('crmPipelines/getUIFlags');

const selectedPipelineId = ref(null);

// [2026-05-17] Helper pra defaults de range: agent_performance default backend
// = last 30 days. Espelhamos no client pra mostrar valores corretos no input
// (vazio = backend decide, mas usuário não enxerga o range).
const toISODate = date => date.toISOString().slice(0, 10);
const today = new Date();
const thirtyDaysAgo = new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000);

const fromDate = ref(toISODate(thirtyDaysAgo));
const toDate = ref(toISODate(today));
// Quarter end aproximação simples: 3 meses pra frente. Backend recalcula
// end_of_quarter exato quando until vier ausente; aqui é só placeholder.
const untilDate = ref(
  toISODate(new Date(today.getFullYear(), today.getMonth() + 3, 0))
);

const pipelineSummaryData = ref(null);
const pipelineSummaryLoading = ref(false);
const pipelineSummaryError = ref(false);

const agentPerformanceData = ref(null);
const agentPerformanceLoading = ref(false);
const agentPerformanceError = ref(false);

const forecastData = ref(null);
const forecastLoading = ref(false);
const forecastError = ref(false);

const isPipelinesLoading = computed(() => pipelinesUiFlags.value.fetchingList);

const fetchPipelineSummary = async () => {
  if (!selectedPipelineId.value) return;
  pipelineSummaryLoading.value = true;
  pipelineSummaryError.value = false;
  try {
    const { data } = await crmReportsApi.pipelineSummary(
      selectedPipelineId.value
    );
    pipelineSummaryData.value = data;
  } catch {
    pipelineSummaryError.value = true;
    pipelineSummaryData.value = null;
  } finally {
    pipelineSummaryLoading.value = false;
  }
};

const fetchAgentPerformance = async () => {
  agentPerformanceLoading.value = true;
  agentPerformanceError.value = false;
  try {
    const { data } = await crmReportsApi.agentPerformance({
      from: fromDate.value,
      to: toDate.value,
    });
    agentPerformanceData.value = data;
  } catch {
    agentPerformanceError.value = true;
    agentPerformanceData.value = null;
  } finally {
    agentPerformanceLoading.value = false;
  }
};

const fetchForecast = async () => {
  if (!selectedPipelineId.value) return;
  forecastLoading.value = true;
  forecastError.value = false;
  try {
    const { data } = await crmReportsApi.forecast(
      selectedPipelineId.value,
      untilDate.value
    );
    forecastData.value = data;
  } catch {
    forecastError.value = true;
    forecastData.value = null;
  } finally {
    forecastLoading.value = false;
  }
};

const refreshPipelineLinked = () => {
  fetchPipelineSummary();
  fetchForecast();
};

// [2026-05-17] Bootstrap: busca pipelines (se ainda não estiverem no store),
// auto-seleciona o default ou o primeiro, dispara reports. agent_performance
// não depende de pipeline — dispara independente.
onMounted(async () => {
  if (pipelines.value.length === 0) {
    await store.dispatch('crmPipelines/get');
  }
  if (pipelines.value.length > 0 && selectedPipelineId.value === null) {
    const defaultPipeline =
      pipelines.value.find(p => p.default_pipeline) || pipelines.value[0];
    selectedPipelineId.value = defaultPipeline.id;
  }
  fetchAgentPerformance();
  refreshPipelineLinked();
});

// Recarrega summary + forecast quando pipeline muda. Range pickers usam
// botão refresh dedicado (evita refetch a cada digitação no <input>).
watch(selectedPipelineId, newId => {
  if (newId) refreshPipelineLinked();
});

// ---------- chart data builders ----------
const fontFamily =
  'Inter,-apple-system,system-ui,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif';

const pipelineSummaryChart = computed(() => {
  const stages = pipelineSummaryData.value?.stages || [];
  return {
    labels: stages.map(s => s.stage_name),
    datasets: [
      {
        label: t('CRM_PIPELINE.REPORTS.PIPELINE_SUMMARY.OPPORTUNITIES_AXIS'),
        backgroundColor: '#3b82f6',
        data: stages.map(s => s.opportunities_count),
        yAxisID: 'yCount',
      },
      {
        label: t('CRM_PIPELINE.REPORTS.PIPELINE_SUMMARY.VALUE_AXIS'),
        backgroundColor: '#10b981',
        data: stages.map(s => Number(s.total_value)),
        yAxisID: 'yValue',
      },
    ],
  };
});

const pipelineSummaryChartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: { display: true, labels: { font: { family: fontFamily } } },
  },
  scales: {
    x: { ticks: { font: { family: fontFamily } } },
    yCount: {
      type: 'linear',
      position: 'left',
      beginAtZero: true,
      ticks: { font: { family: fontFamily }, stepSize: 1 },
    },
    yValue: {
      type: 'linear',
      position: 'right',
      beginAtZero: true,
      grid: { drawOnChartArea: false },
      ticks: { font: { family: fontFamily } },
    },
  },
}));

const forecastChart = computed(() => {
  const months = forecastData.value?.monthly_projection || [];
  return {
    labels: months.map(m => m.month),
    datasets: [
      {
        label: t('CRM_PIPELINE.REPORTS.FORECAST.PROJECTED_AXIS'),
        borderColor: '#6366f1',
        backgroundColor: 'rgba(99, 102, 241, 0.2)',
        data: months.map(m => Number(m.projected_value)),
        tension: 0.3,
        fill: true,
      },
    ],
  };
});

const forecastChartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: { display: true, labels: { font: { family: fontFamily } } },
  },
  scales: {
    x: { ticks: { font: { family: fontFamily } } },
    y: {
      beginAtZero: true,
      ticks: { font: { family: fontFamily } },
    },
  },
}));

// ---------- empty state helpers ----------
const isPipelineSummaryEmpty = computed(
  () =>
    !pipelineSummaryError.value &&
    !pipelineSummaryLoading.value &&
    (!pipelineSummaryData.value ||
      pipelineSummaryData.value.stages.length === 0)
);

const isAgentPerformanceEmpty = computed(
  () =>
    !agentPerformanceError.value &&
    !agentPerformanceLoading.value &&
    (!agentPerformanceData.value ||
      agentPerformanceData.value.agents.length === 0)
);

const isForecastEmpty = computed(
  () =>
    !forecastError.value &&
    !forecastLoading.value &&
    (!forecastData.value || forecastData.value.monthly_projection.length === 0)
);

const formatWinRate = rate => `${Math.round((rate || 0) * 100)}%`;
const formatBRL = value => formatCurrency(Number(value || 0), 'BRL');

const totalProjectedFormatted = computed(() =>
  forecastData.value ? formatBRL(forecastData.value.total_projected) : ''
);
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden bg-n-background">
    <header
      class="flex items-start justify-between gap-4 px-6 py-4 border-b border-n-strong"
    >
      <div class="flex flex-col gap-1 min-w-0">
        <router-link
          :to="{ name: 'crm_home' }"
          class="no-underline text-n-brand text-xs font-medium"
        >
          {{ t('CRM_PIPELINE.REPORTS.BACK_TO_HOME') }}
        </router-link>
        <h1 class="text-xl font-semibold text-n-slate-12">
          {{ t('CRM_PIPELINE.REPORTS.PAGE_HEADER') }}
        </h1>
      </div>
      <div class="flex items-center gap-2">
        <label
          for="crm-reports-pipeline-select"
          class="text-xs text-n-slate-11"
        >
          {{ t('CRM_PIPELINE.REPORTS.SELECT_PIPELINE') }}
        </label>
        <select
          id="crm-reports-pipeline-select"
          v-model.number="selectedPipelineId"
          :disabled="isPipelinesLoading || pipelines.length === 0"
          class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
        >
          <option
            v-for="pipeline in pipelines"
            :key="pipeline.id"
            :value="pipeline.id"
          >
            {{ pipeline.name }}
          </option>
        </select>
      </div>
    </header>

    <div class="flex flex-col gap-4 overflow-y-auto p-6">
      <!-- Pipeline Summary -->
      <ReportSection
        :title="t('CRM_PIPELINE.REPORTS.PIPELINE_SUMMARY.TITLE')"
        :is-loading="pipelineSummaryLoading"
        :has-error="pipelineSummaryError"
        :is-empty="isPipelineSummaryEmpty"
        :error-message="t('CRM_PIPELINE.REPORTS.PIPELINE_SUMMARY.ERROR')"
        :empty-message="t('CRM_PIPELINE.REPORTS.PIPELINE_SUMMARY.EMPTY')"
      >
        <template #actions>
          <button
            type="button"
            :disabled="pipelineSummaryLoading || !selectedPipelineId"
            class="px-3 py-1.5 text-xs rounded-md border border-n-strong text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
            @click="fetchPipelineSummary"
          >
            {{ t('CRM_PIPELINE.REPORTS.REFRESH_BUTTON') }}
          </button>
        </template>
        <div class="h-72">
          <Bar
            :data="pipelineSummaryChart"
            :options="pipelineSummaryChartOptions"
          />
        </div>
      </ReportSection>

      <!-- Agent Performance -->
      <ReportSection
        :title="t('CRM_PIPELINE.REPORTS.AGENT_PERFORMANCE.TITLE')"
        :is-loading="agentPerformanceLoading"
        :has-error="agentPerformanceError"
        :is-empty="isAgentPerformanceEmpty"
        :error-message="t('CRM_PIPELINE.REPORTS.AGENT_PERFORMANCE.ERROR')"
        :empty-message="t('CRM_PIPELINE.REPORTS.AGENT_PERFORMANCE.EMPTY')"
      >
        <template #actions>
          <div class="flex flex-col gap-1">
            <label for="crm-reports-agent-from" class="text-xs text-n-slate-11">
              {{ t('CRM_PIPELINE.REPORTS.FROM_LABEL') }}
            </label>
            <input
              id="crm-reports-agent-from"
              v-model="fromDate"
              type="date"
              class="px-2 py-1 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label for="crm-reports-agent-to" class="text-xs text-n-slate-11">
              {{ t('CRM_PIPELINE.REPORTS.TO_LABEL') }}
            </label>
            <input
              id="crm-reports-agent-to"
              v-model="toDate"
              type="date"
              class="px-2 py-1 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
            />
          </div>
          <button
            type="button"
            :disabled="agentPerformanceLoading"
            class="px-3 py-1.5 text-xs rounded-md border border-n-strong text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
            @click="fetchAgentPerformance"
          >
            {{ t('CRM_PIPELINE.REPORTS.REFRESH_BUTTON') }}
          </button>
        </template>
        <div class="overflow-x-auto">
          <table class="w-full text-sm text-left">
            <thead class="text-xs text-n-slate-11 uppercase">
              <tr>
                <th class="px-3 py-2">
                  {{ t('CRM_PIPELINE.REPORTS.AGENT_PERFORMANCE.AGENT_COLUMN') }}
                </th>
                <th class="px-3 py-2 text-right">
                  {{
                    t('CRM_PIPELINE.REPORTS.AGENT_PERFORMANCE.ASSIGNED_COLUMN')
                  }}
                </th>
                <th class="px-3 py-2 text-right">
                  {{ t('CRM_PIPELINE.REPORTS.AGENT_PERFORMANCE.WON_COLUMN') }}
                </th>
                <th class="px-3 py-2 text-right">
                  {{
                    t('CRM_PIPELINE.REPORTS.AGENT_PERFORMANCE.WON_VALUE_COLUMN')
                  }}
                </th>
                <th class="px-3 py-2 text-right">
                  {{ t('CRM_PIPELINE.REPORTS.AGENT_PERFORMANCE.LOST_COLUMN') }}
                </th>
                <th class="px-3 py-2 text-right">
                  {{
                    t('CRM_PIPELINE.REPORTS.AGENT_PERFORMANCE.WIN_RATE_COLUMN')
                  }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in agentPerformanceData.agents"
                :key="row.user_id"
                class="border-t border-n-strong"
              >
                <td class="px-3 py-2 text-n-slate-12">{{ row.user_name }}</td>
                <td class="px-3 py-2 text-right text-n-slate-12">
                  {{ row.opportunities_assigned }}
                </td>
                <td class="px-3 py-2 text-right text-n-slate-12">
                  {{ row.opportunities_won }}
                </td>
                <td class="px-3 py-2 text-right text-n-slate-12">
                  {{ formatBRL(row.won_value) }}
                </td>
                <td class="px-3 py-2 text-right text-n-slate-12">
                  {{ row.opportunities_lost }}
                </td>
                <td class="px-3 py-2 text-right text-n-slate-12">
                  {{ formatWinRate(row.win_rate) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </ReportSection>

      <!-- Forecast -->
      <ReportSection
        :title="t('CRM_PIPELINE.REPORTS.FORECAST.TITLE')"
        :is-loading="forecastLoading"
        :has-error="forecastError"
        :is-empty="isForecastEmpty"
        :error-message="t('CRM_PIPELINE.REPORTS.FORECAST.ERROR')"
        :empty-message="t('CRM_PIPELINE.REPORTS.FORECAST.EMPTY')"
      >
        <template #actions>
          <div class="flex flex-col gap-1">
            <label
              for="crm-reports-forecast-until"
              class="text-xs text-n-slate-11"
            >
              {{ t('CRM_PIPELINE.REPORTS.UNTIL_LABEL') }}
            </label>
            <input
              id="crm-reports-forecast-until"
              v-model="untilDate"
              type="date"
              class="px-2 py-1 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
            />
          </div>
          <button
            type="button"
            :disabled="forecastLoading || !selectedPipelineId"
            class="px-3 py-1.5 text-xs rounded-md border border-n-strong text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
            @click="fetchForecast"
          >
            {{ t('CRM_PIPELINE.REPORTS.REFRESH_BUTTON') }}
          </button>
        </template>
        <div class="flex flex-col gap-2">
          <div class="h-72">
            <Line :data="forecastChart" :options="forecastChartOptions" />
          </div>
          <p class="text-sm text-n-slate-12 text-right">
            {{ t('CRM_PIPELINE.REPORTS.FORECAST.TOTAL_LABEL') }}:
            <span class="font-semibold">{{ totalProjectedFormatted }}</span>
          </p>
        </div>
      </ReportSection>
    </div>
  </div>
</template>
