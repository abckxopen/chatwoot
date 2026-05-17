<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Spinner from 'shared/components/Spinner.vue';

const props = defineProps({
  pipelineId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const store = useStore();

// [2026-05-17] Ler como Number — getters dos módulos CRM normalizam via
// Number() internamente, mas usar Number aqui evita comparações silenciosas
// string-vs-number nos templates (`pipeline.id === pipelineId`).
const pipelineIdNum = computed(() => Number(props.pipelineId));

const getPipelineFn = useMapGetter('crmPipelines/getCrmPipeline');
const getStagesFn = useMapGetter('crmStages/getCrmStagesForPipeline');
const getOpportunitiesForStageFn = useMapGetter(
  'crmOpportunities/getCrmOpportunitiesForStage'
);

const pipelineUiFlags = useMapGetter('crmPipelines/getUIFlags');
const stagesUiFlags = useMapGetter('crmStages/getUIFlags');
const opportunitiesUiFlags = useMapGetter('crmOpportunities/getUIFlags');

const pipeline = computed(() => getPipelineFn.value(pipelineIdNum.value));
const stages = computed(() => getStagesFn.value(pipelineIdNum.value));

// [2026-05-17] Ordem de dispatch importa pra UX, não pra correção:
//   1. pipelines/get popula header (caso usuário tenha entrado direto via URL)
//   2. stages/get popula colunas
//   3. opportunities/get popula cards
// Backend filtra por pipeline_id snake_case (override em api/crm/opportunities.js).
// Sem o snake_case o controller#index ignora silenciosamente e retorna TODAS
// as opps do account — devastador em produção.
onMounted(async () => {
  if (!pipeline.value) {
    await store.dispatch('crmPipelines/get');
  }
  await store.dispatch('crmStages/get', pipelineIdNum.value);
  await store.dispatch('crmOpportunities/get', {
    pipeline_id: pipelineIdNum.value,
  });
});

const isLoading = computed(
  () =>
    pipelineUiFlags.value.fetchingList ||
    stagesUiFlags.value.fetchingList ||
    opportunitiesUiFlags.value.fetchingList
);

const pipelineMissing = computed(() => !isLoading.value && !pipeline.value);

const isPipelineEmpty = computed(
  () => !isLoading.value && !!pipeline.value && stages.value.length === 0
);

const formatCurrency = (value, currency) => {
  try {
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency,
    }).format(value);
  } catch {
    // Currency inválido (BRL fallback) — Intl rejeita ISO desconhecido.
    return `${currency} ${Number(value).toFixed(2)}`;
  }
};

// [2026-05-17] Soma client-side: backend não expõe endpoint /stages/:id/totals
// e refazer roundtrip por stage seria pior. Lista de opps já está em memória.
// Se a base crescer pra milhares de cards por pipeline, mover pra getter
// memoizado ou endpoint dedicado.
const stageOpportunities = stageId => getOpportunitiesForStageFn.value(stageId);

const stageTotal = stageId => {
  const opps = stageOpportunities(stageId);
  if (opps.length === 0) return null;
  // Assumimos currency consistente por stage (UI MVP). Pega da 1a opp.
  const currency = opps[0].currency || 'BRL';
  const sum = opps.reduce((acc, opp) => acc + (Number(opp.value) || 0), 0);
  return formatCurrency(sum, currency);
};

const formatOpportunityValue = opp => {
  if (opp.value === null || opp.value === undefined) {
    return t('CRM_PIPELINE.KANBAN.CARD_VALUE_PLACEHOLDER');
  }
  return formatCurrency(Number(opp.value), opp.currency || 'BRL');
};

const assigneeInitials = opp => {
  // [2026-05-17] Serializer só expõe assignee_id, não embed completo. Slice 3
  // mostra placeholder "U<id>" pra debug visual; slice futura embute nome.
  if (!opp.assignee_id) return t('CRM_PIPELINE.KANBAN.UNASSIGNED');
  return `U${opp.assignee_id}`;
};
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden bg-n-background">
    <header
      class="flex items-center justify-between gap-4 px-6 py-4 border-b border-n-strong"
    >
      <div class="flex flex-col gap-1 min-w-0">
        <router-link
          :to="{ name: 'crm_home' }"
          class="no-underline text-n-brand text-xs font-medium"
        >
          {{ t('CRM_PIPELINE.KANBAN.BACK_TO_HOME') }}
        </router-link>
        <h1 class="text-xl font-semibold text-n-slate-12 truncate">
          {{ pipeline ? pipeline.name : t('CRM_PIPELINE.PAGE_HEADER') }}
        </h1>
      </div>
    </header>

    <section
      v-if="isLoading"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <Spinner />
      <span class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.KANBAN.LOADING') }}
      </span>
    </section>

    <section
      v-else-if="pipelineMissing"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.KANBAN.PIPELINE_NOT_FOUND') }}
      </p>
      <router-link
        :to="{ name: 'crm_home' }"
        class="no-underline text-n-brand text-sm font-medium"
      >
        {{ t('CRM_PIPELINE.KANBAN.BACK_TO_HOME') }}
      </router-link>
    </section>

    <section
      v-else-if="isPipelineEmpty"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.KANBAN.EMPTY_PIPELINE') }}
      </p>
    </section>

    <section
      v-else
      class="flex gap-4 overflow-x-auto flex-1 px-6 py-4 items-start"
    >
      <article
        v-for="stage in stages"
        :key="stage.id"
        class="flex flex-col flex-shrink-0 w-72 max-h-full rounded-lg border border-n-strong bg-n-solid-2"
      >
        <header
          class="flex flex-col gap-1 p-3 border-b border-n-strong bg-n-solid-1 rounded-t-lg"
        >
          <h2 class="text-sm font-semibold text-n-slate-12 truncate">
            {{ stage.name }}
          </h2>
          <div class="flex justify-between gap-2 text-xs text-n-slate-11">
            <span>
              {{
                t('CRM_PIPELINE.KANBAN.OPPORTUNITIES_COUNT', {
                  n: stageOpportunities(stage.id).length,
                })
              }}
            </span>
            <span v-if="stageTotal(stage.id)" class="font-medium">
              {{
                t('CRM_PIPELINE.KANBAN.STAGE_TOTAL', {
                  value: stageTotal(stage.id),
                })
              }}
            </span>
          </div>
        </header>

        <div class="flex flex-col gap-2 p-3 overflow-y-auto">
          <p
            v-if="stageOpportunities(stage.id).length === 0"
            class="text-xs text-n-slate-11 italic text-center py-4"
          >
            {{ t('CRM_PIPELINE.KANBAN.EMPTY_STAGE') }}
          </p>

          <article
            v-for="opp in stageOpportunities(stage.id)"
            :key="opp.id"
            class="flex flex-col gap-2 p-3 rounded-md border border-n-strong bg-n-solid-1 hover:bg-n-alpha-2 transition-colors"
          >
            <h3 class="text-sm font-medium text-n-slate-12 line-clamp-2">
              {{ opp.name }}
            </h3>
            <div
              class="flex justify-between items-center gap-2 text-xs text-n-slate-11"
            >
              <span class="font-medium text-n-slate-12">
                {{ formatOpportunityValue(opp) }}
              </span>
              <span
                class="px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
              >
                {{ assigneeInitials(opp) }}
              </span>
            </div>
          </article>
        </div>
      </article>
    </section>
  </div>
</template>
