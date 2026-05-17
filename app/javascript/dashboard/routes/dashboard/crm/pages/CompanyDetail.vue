<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import Spinner from 'shared/components/Spinner.vue';

const props = defineProps({
  companyId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const store = useStore();
const { accountId } = useAccount();

// [2026-05-17] Number coercion no mesmo padrão de PipelineKanban —
// previne mismatches string-vs-number nos getters/comparações.
const companyIdNum = computed(() => Number(props.companyId));

const getCompanyFn = useMapGetter('crmCompanies/getCrmCompany');
const opportunities = useMapGetter('crmOpportunities/getCrmOpportunities');

const companiesUiFlags = useMapGetter('crmCompanies/getUIFlags');
const opportunitiesUiFlags = useMapGetter('crmOpportunities/getUIFlags');

const company = computed(() => getCompanyFn.value(companyIdNum.value));

// [2026-05-17] hasMounted gate igual ao PipelineKanban — evita flash de
// "Empresa não encontrada" no primeiro frame antes do show/get resolver.
const hasMounted = ref(false);

// [2026-05-17] Backend crm_opportunities_controller#index NÃO filtra por
// crm_company_id (apenas pipeline_id|stage_id|status|assignee_id).
// Fetch all + filter client-side. Pode ser pesado se houver muitas
// opportunities; mover pra filter dedicado é Phase 4 follow-up.
// TODO Phase 4 follow-up: extract getter `getCrmOpportunitiesForCompany`
// análogo a `getCrmOpportunitiesForStage` quando houver mais consumidores.
const opportunitiesForCompany = computed(() =>
  opportunities.value.filter(opp => opp.crm_company_id === companyIdNum.value)
);

onMounted(async () => {
  // show() popula só o item; se backend retornar embedded counts/links
  // (não retorna hoje), aproveitamos. Caso falhe, render entra em
  // "not found" state via guard abaixo.
  try {
    await store.dispatch('crmCompanies/show', companyIdNum.value);
  } catch (error) {
    // Engole — guard `companyMissing` cuida do estado terminal.
  }
  // Fetch global de opportunities pra alimentar a section. Reutiliza
  // mesmo store que o Kanban (cache compartilhado entre rotas).
  await store.dispatch('crmOpportunities/get');
  hasMounted.value = true;
});

const isLoading = computed(
  () =>
    companiesUiFlags.value.fetchingItem ||
    opportunitiesUiFlags.value.fetchingList
);

const isReady = computed(() => hasMounted.value && !isLoading.value);
const companyMissing = computed(() => isReady.value && !company.value);

const formatCreatedAt = value => {
  if (!value) return t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_UNAVAILABLE');
  try {
    return new Intl.DateTimeFormat('pt-BR', {
      dateStyle: 'medium',
    }).format(new Date(value));
  } catch {
    return value;
  }
};

const formatCurrency = (value, currency) => {
  try {
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency,
    }).format(value);
  } catch {
    return `${currency} ${Number(value).toFixed(2)}`;
  }
};

const formatOpportunityValue = opp => {
  if (opp.value === null || opp.value === undefined) {
    return t('CRM_PIPELINE.KANBAN.CARD_VALUE_PLACEHOLDER');
  }
  return formatCurrency(Number(opp.value), opp.currency || 'BRL');
};
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden bg-n-background">
    <header
      class="flex items-center justify-between gap-4 px-6 py-4 border-b border-n-strong"
    >
      <div class="flex flex-col gap-1 min-w-0">
        <router-link
          :to="{ name: 'crm_companies', params: { accountId } }"
          class="no-underline text-n-brand text-xs font-medium"
        >
          {{ t('CRM_PIPELINE.COMPANIES.DETAIL.BACK_TO_LIST') }}
        </router-link>
        <h1 class="text-xl font-semibold text-n-slate-12 truncate">
          {{ company ? company.name : t('CRM_PIPELINE.COMPANIES.PAGE_HEADER') }}
        </h1>
      </div>
      <!-- [2026-05-17] Edit deixado como botão disabled: slice 1 entrega
           só create (form inline na list page) e read. Edit/delete entram
           numa próxima slice junto com modal compartilhado. -->
      <button
        type="button"
        disabled
        class="px-3 py-1.5 text-sm rounded-md border border-n-strong text-n-slate-11 opacity-50 cursor-not-allowed"
      >
        {{ t('CRM_PIPELINE.COMPANIES.DETAIL.EDIT_BUTTON') }}
      </button>
    </header>

    <section
      v-if="isLoading"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <Spinner />
      <span class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.COMPANIES.DETAIL.LOADING') }}
      </span>
    </section>

    <section
      v-else-if="companyMissing"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.COMPANIES.DETAIL.COMPANY_NOT_FOUND') }}
      </p>
      <router-link
        :to="{ name: 'crm_companies', params: { accountId } }"
        class="no-underline text-n-brand text-sm font-medium"
      >
        {{ t('CRM_PIPELINE.COMPANIES.DETAIL.BACK_TO_LIST') }}
      </router-link>
    </section>

    <div
      v-else-if="company"
      class="flex flex-col gap-6 p-6 overflow-y-auto flex-1"
    >
      <section
        class="flex flex-col gap-3 p-4 rounded-lg border border-n-strong bg-n-solid-1"
      >
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_SECTION') }}
        </h2>
        <dl class="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs uppercase text-n-slate-11">
              {{ t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_NAME') }}
            </dt>
            <dd class="text-n-slate-12">{{ company.name }}</dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs uppercase text-n-slate-11">
              {{ t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_DOMAIN') }}
            </dt>
            <dd class="text-n-slate-12">
              {{
                company.domain ||
                t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_UNAVAILABLE')
              }}
            </dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs uppercase text-n-slate-11">
              {{ t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_INDUSTRY') }}
            </dt>
            <dd class="text-n-slate-12">
              {{
                company.industry ||
                t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_UNAVAILABLE')
              }}
            </dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs uppercase text-n-slate-11">
              {{ t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_CREATED_AT') }}
            </dt>
            <dd class="text-n-slate-12">
              {{ formatCreatedAt(company.created_at) }}
            </dd>
          </div>
        </dl>
      </section>

      <!-- [2026-05-17] Contacts vinculados: linkage prevista no spec é via
           Contact#additional_attributes['crm_company_id'] (JSONB, sem FK
           direto pra evitar conflito de rebase com upstream contacts).
           Slice 1 deixa placeholder pra não puxar o store de contacts
           inteiro só pra filtrar por additional_attributes — performance
           ruim em accounts com muitos contatos.
           TODO Phase 4 follow-up: endpoint dedicado
           `/crm_companies/:id/contacts` ou filtro server-side em contacts. -->
      <section
        class="flex flex-col gap-3 p-4 rounded-lg border border-n-strong bg-n-solid-1"
      >
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ t('CRM_PIPELINE.COMPANIES.DETAIL.CONTACTS_SECTION') }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ t('CRM_PIPELINE.COMPANIES.DETAIL.NO_CONTACTS') }}
        </p>
      </section>

      <section
        class="flex flex-col gap-3 p-4 rounded-lg border border-n-strong bg-n-solid-1"
      >
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ t('CRM_PIPELINE.COMPANIES.DETAIL.OPPORTUNITIES_SECTION') }}
        </h2>
        <p
          v-if="opportunitiesForCompany.length === 0"
          class="text-sm text-n-slate-11"
        >
          {{ t('CRM_PIPELINE.COMPANIES.DETAIL.NO_OPPORTUNITIES') }}
        </p>
        <ul v-else class="flex flex-col gap-2">
          <li
            v-for="opp in opportunitiesForCompany"
            :key="opp.id"
            class="flex items-center justify-between gap-3 p-3 rounded-md border border-n-weak bg-n-solid-2"
          >
            <div class="flex flex-col gap-0.5 min-w-0">
              <span class="text-sm font-medium text-n-slate-12 truncate">
                {{ opp.name }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ formatOpportunityValue(opp) }}
                <template v-if="opp.status"> · {{ opp.status }} </template>
              </span>
            </div>
            <!-- [2026-05-17] Slice 2: rota crm_opportunity_detail existe agora;
                 substitui botão disabled por router-link clicável. -->
            <router-link
              :to="{
                name: 'crm_opportunity_detail',
                params: { accountId, opportunityId: opp.id },
              }"
              class="px-2 py-1 text-xs rounded border border-n-strong text-n-slate-12 hover:bg-n-alpha-2 no-underline whitespace-nowrap"
            >
              {{ t('CRM_PIPELINE.COMPANIES.DETAIL.OPEN_OPPORTUNITY') }}
            </router-link>
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>
