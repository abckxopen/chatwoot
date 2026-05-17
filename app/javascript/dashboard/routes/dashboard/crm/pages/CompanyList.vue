<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import Spinner from 'shared/components/Spinner.vue';

const { t } = useI18n();
const store = useStore();
const { accountId } = useAccount();

// [2026-05-17] Module registrado em store/index.js como `crmCompanies`.
// Slice 0 expõe actions `get|show|create|update|delete` + getters
// `getCrmCompanies|getCrmCompany|getUIFlags` (mesmo shape de crmPipelines).
const companies = useMapGetter('crmCompanies/getCrmCompanies');
const uiFlags = useMapGetter('crmCompanies/getUIFlags');

const isLoading = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);

// [2026-05-17] Search client-side: CrmCompanies API client (slice 0) não
// expõe params, e backend index não filtra por name. Filtragem em memória
// resolve pro escopo atual (até ~poucas centenas de empresas por account);
// se crescer, mover pra endpoint dedicado com query param.
const searchTerm = ref('');
const filteredCompanies = computed(() => {
  const term = searchTerm.value.trim().toLowerCase();
  if (!term) return companies.value;
  return companies.value.filter(company =>
    (company.name || '').toLowerCase().includes(term)
  );
});

const isEmpty = computed(
  () => !isLoading.value && companies.value.length === 0
);
const isEmptyAfterSearch = computed(
  () =>
    !isLoading.value &&
    companies.value.length > 0 &&
    filteredCompanies.value.length === 0
);

const fetchCompanies = () => store.dispatch('crmCompanies/get');

onMounted(fetchCompanies);

// [2026-05-17] Inline form em vez de modal: MVP slice 1 evita componente
// Dialog extra (Modal/Dialog do core puxa estilos+slots que inflariam
// LOC). Form toggles visibility via ref local; sem rota dedicada.
const isFormOpen = ref(false);
const formState = ref({ name: '', domain: '', industry: '' });

const openForm = () => {
  formState.value = { name: '', domain: '', industry: '' };
  isFormOpen.value = true;
};

const closeForm = () => {
  isFormOpen.value = false;
};

const submitForm = async () => {
  const name = formState.value.name.trim();
  if (!name) return;
  try {
    await store.dispatch('crmCompanies/create', {
      name,
      domain: formState.value.domain.trim() || null,
      industry: formState.value.industry.trim() || null,
    });
    closeForm();
  } catch (error) {
    useAlert(t('CRM_PIPELINE.COMPANIES.CREATE_FORM.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden p-6 gap-6 bg-n-background">
    <header class="flex items-start justify-between gap-4">
      <div class="flex flex-col gap-1 min-w-0">
        <router-link
          :to="{ name: 'crm_home', params: { accountId } }"
          class="no-underline text-n-brand text-xs font-medium"
        >
          {{ t('CRM_PIPELINE.KANBAN.BACK_TO_HOME') }}
        </router-link>
        <h1 class="text-xl font-semibold text-n-slate-12">
          {{ t('CRM_PIPELINE.COMPANIES.PAGE_HEADER') }}
        </h1>
      </div>
      <button
        type="button"
        class="px-3 py-1.5 text-sm rounded-md border border-n-strong text-n-slate-12 hover:bg-n-alpha-2 whitespace-nowrap"
        @click="openForm"
      >
        {{ t('CRM_PIPELINE.COMPANIES.NEW_COMPANY_BUTTON') }}
      </button>
    </header>

    <!-- [2026-05-17] Form inline acima da tabela: aparece apenas quando
         openForm() chamado. Tab order preservada com inputs em sequência.
         Wrapped em <form> + @submit.prevent pra capturar Enter (UX padrão
         de formulário) sem precisar mover foco até o botão Criar. -->
    <form
      v-if="isFormOpen"
      class="flex flex-col gap-3 p-4 rounded-lg border border-n-strong bg-n-solid-1"
      @submit.prevent="submitForm"
    >
      <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
        <label class="flex flex-col gap-1 text-sm text-n-slate-12">
          {{ t('CRM_PIPELINE.COMPANIES.CREATE_FORM.NAME_LABEL') }}
          <input
            v-model="formState.name"
            type="text"
            :placeholder="
              t('CRM_PIPELINE.COMPANIES.CREATE_FORM.NAME_PLACEHOLDER')
            "
            class="px-2 py-1.5 rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm text-n-slate-12">
          {{ t('CRM_PIPELINE.COMPANIES.CREATE_FORM.DOMAIN_LABEL') }}
          <input
            v-model="formState.domain"
            type="text"
            :placeholder="
              t('CRM_PIPELINE.COMPANIES.CREATE_FORM.DOMAIN_PLACEHOLDER')
            "
            class="px-2 py-1.5 rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm text-n-slate-12">
          {{ t('CRM_PIPELINE.COMPANIES.CREATE_FORM.INDUSTRY_LABEL') }}
          <input
            v-model="formState.industry"
            type="text"
            :placeholder="
              t('CRM_PIPELINE.COMPANIES.CREATE_FORM.INDUSTRY_PLACEHOLDER')
            "
            class="px-2 py-1.5 rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
          />
        </label>
      </div>
      <div class="flex justify-end gap-2">
        <button
          type="button"
          class="px-3 py-1.5 text-sm rounded-md text-n-slate-11 hover:bg-n-alpha-2"
          @click="closeForm"
        >
          {{ t('CRM_PIPELINE.COMPANIES.CREATE_FORM.CANCEL') }}
        </button>
        <button
          type="submit"
          :disabled="!formState.name.trim() || isCreating"
          class="px-3 py-1.5 text-sm rounded-md border border-n-strong bg-n-brand text-white hover:bg-n-brand/90 disabled:opacity-50"
        >
          {{ t('CRM_PIPELINE.COMPANIES.CREATE_FORM.SUBMIT') }}
        </button>
      </div>
    </form>

    <div class="flex flex-col gap-2">
      <input
        v-model="searchTerm"
        type="search"
        :placeholder="t('CRM_PIPELINE.COMPANIES.SEARCH_PLACEHOLDER')"
        class="px-3 py-2 text-sm rounded-md border border-n-strong bg-n-solid-1 text-n-slate-12 w-full max-w-md"
      />
    </div>

    <section
      v-if="isLoading"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <Spinner />
      <span class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.COMPANIES.LOADING') }}
      </span>
    </section>

    <section
      v-else-if="isEmpty"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.COMPANIES.EMPTY_STATE') }}
      </p>
    </section>

    <section
      v-else-if="isEmptyAfterSearch"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.COMPANIES.EMPTY_SEARCH') }}
      </p>
    </section>

    <section v-else class="flex-1 overflow-y-auto">
      <table class="w-full text-sm border-collapse">
        <thead class="text-left text-xs uppercase text-n-slate-11">
          <tr class="border-b border-n-strong">
            <th class="px-3 py-2 font-medium">
              {{ t('CRM_PIPELINE.COMPANIES.TABLE.NAME') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM_PIPELINE.COMPANIES.TABLE.DOMAIN') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM_PIPELINE.COMPANIES.TABLE.INDUSTRY') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <!-- [2026-05-17] router-link no <tr> via :to + custom tag não roda
               em <table>; usamos navegação via click + tabindex pra acessibilidade
               básica. Slice futura pode mover pra grid de cards. -->
          <router-link
            v-for="company in filteredCompanies"
            :key="company.id"
            v-slot="{ navigate }"
            :to="{
              name: 'crm_company_detail',
              params: { accountId, companyId: company.id },
            }"
            custom
          >
            <tr
              class="border-b border-n-weak hover:bg-n-alpha-2 cursor-pointer"
              tabindex="0"
              @click="navigate"
              @keyup.enter="navigate"
            >
              <td class="px-3 py-2 text-n-slate-12 font-medium">
                {{ company.name }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{
                  company.domain ||
                  t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_UNAVAILABLE')
                }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{
                  company.industry ||
                  t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_UNAVAILABLE')
                }}
              </td>
            </tr>
          </router-link>
        </tbody>
      </table>
    </section>
  </div>
</template>
