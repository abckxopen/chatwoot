<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import Spinner from 'shared/components/Spinner.vue';
import ActivityList from '../components/ActivityList.vue';

const props = defineProps({
  opportunityId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const store = useStore();
const { accountId } = useAccount();

// [2026-05-17] Number coercion no mesmo padrão das outras pages CRM —
// previne mismatches string-vs-number nos getters.
const opportunityIdNum = computed(() => Number(props.opportunityId));

const getOpportunityFn = useMapGetter('crmOpportunities/getCrmOpportunity');
const getStagesForPipelineFn = useMapGetter(
  'crmStages/getCrmStagesForPipeline'
);
const getCompanyFn = useMapGetter('crmCompanies/getCrmCompany');

const opportunitiesUiFlags = useMapGetter('crmOpportunities/getUIFlags');

const opportunity = computed(() =>
  getOpportunityFn.value(opportunityIdNum.value)
);
const stages = computed(() =>
  opportunity.value
    ? getStagesForPipelineFn.value(opportunity.value.crm_pipeline_id)
    : []
);
const company = computed(() => {
  if (!opportunity.value?.crm_company_id) return null;
  return getCompanyFn.value(opportunity.value.crm_company_id);
});

// [2026-05-17] hasMounted gate igual ao PipelineKanban/CompanyDetail — evita
// flash de "Oportunidade não encontrada" antes do show() resolver.
const hasMounted = ref(false);

// [2026-05-17] formatCurrency declarada antes de QUALQUER computed/método
// que use — slice 3 quebrou lint (no-use-before-define) por declarar abaixo.
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

const formattedValue = computed(() => {
  if (!opportunity.value) return '';
  const opp = opportunity.value;
  if (opp.value === null || opp.value === undefined) {
    return t('CRM_PIPELINE.KANBAN.CARD_VALUE_PLACEHOLDER');
  }
  return formatCurrency(Number(opp.value), opp.currency || 'BRL');
});

const formattedCloseDate = computed(() => {
  if (!opportunity.value?.expected_close_date) {
    return t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_UNAVAILABLE');
  }
  try {
    return new Intl.DateTimeFormat('pt-BR', {
      dateStyle: 'medium',
    }).format(new Date(opportunity.value.expected_close_date));
  } catch {
    return opportunity.value.expected_close_date;
  }
});

const currentStageName = computed(() => {
  if (!opportunity.value) return '';
  const stage = stages.value.find(s => s.id === opportunity.value.crm_stage_id);
  return stage?.name || t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_UNAVAILABLE');
});

const pipelineName = computed(
  () =>
    opportunity.value?.pipeline?.name ||
    t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_UNAVAILABLE')
);

const statusLabel = computed(() => {
  const status = opportunity.value?.status || 'open';
  return t(`CRM_PIPELINE.OPPORTUNITY.STATUS.${status.toUpperCase()}`);
});

const statusBadgeClass = computed(() => {
  const status = opportunity.value?.status || 'open';
  if (status === 'won') return 'bg-n-teal-9 text-white';
  if (status === 'lost') return 'bg-n-ruby-9 text-white';
  return 'bg-n-alpha-2 text-n-slate-12';
});

onMounted(async () => {
  try {
    await store.dispatch('crmOpportunities/show', opportunityIdNum.value);
  } catch (error) {
    // Engole — guard `opportunityMissing` cuida do estado terminal.
  }
  // [2026-05-17] Carregar stages/companies em background pra alimentar o
  // dropdown de move-to-stage e o link de empresa. Reusa cache do Kanban
  // (mesmo store), barato em deep-link e idempotente entre rotas.
  if (opportunity.value?.crm_pipeline_id) {
    await store.dispatch('crmStages/get', opportunity.value.crm_pipeline_id);
  }
  // Fetch companies só se ainda não estiver carregado — evita roundtrip
  // redundante quando usuário veio do CompanyDetail.
  if (opportunity.value?.crm_company_id && !company.value) {
    await store.dispatch('crmCompanies/get');
  }
  await store.dispatch('crmActivities/get', opportunityIdNum.value);
  hasMounted.value = true;
});

const isLoading = computed(() => opportunitiesUiFlags.value.fetchingItem);
const isUpdating = computed(() => opportunitiesUiFlags.value.updatingItem);
const isDiscarding = computed(() => opportunitiesUiFlags.value.discarding);
const isMoving = computed(() => opportunitiesUiFlags.value.movingToStage);

const isReady = computed(() => hasMounted.value && !isLoading.value);
const opportunityMissing = computed(() => isReady.value && !opportunity.value);

// Edit form state
const isEditing = ref(false);
const editForm = reactive({
  name: '',
  value: '',
  currency: 'BRL',
  expected_close_date: '',
  probability: '',
});

const startEdit = () => {
  if (!opportunity.value) return;
  const opp = opportunity.value;
  editForm.name = opp.name || '';
  editForm.value = opp.value ?? '';
  editForm.currency = opp.currency || 'BRL';
  // [2026-05-17] expected_close_date vem como ISO date (jbuilder usa &.iso8601);
  // input type="date" precisa "YYYY-MM-DD" — split funciona pois ISO date pode
  // ou não ter time (Date#iso8601 sem args é só data).
  editForm.expected_close_date = opp.expected_close_date
    ? String(opp.expected_close_date).slice(0, 10)
    : '';
  editForm.probability = opp.probability ?? '';
  isEditing.value = true;
};

const cancelEdit = () => {
  isEditing.value = false;
};

const submitEdit = async () => {
  if (!editForm.name.trim()) return;
  const payload = {
    id: opportunityIdNum.value,
    name: editForm.name.trim(),
    value: editForm.value === '' ? null : Number(editForm.value),
    currency: editForm.currency,
    expected_close_date: editForm.expected_close_date || null,
    probability:
      editForm.probability === '' ? null : Number(editForm.probability),
  };
  try {
    await store.dispatch('crmOpportunities/update', payload);
    isEditing.value = false;
  } catch (error) {
    useAlert(t('CRM_PIPELINE.OPPORTUNITY.UPDATE_ERROR'));
  }
};

// Stage move
const moveTargetStageId = ref('');

const moveToStage = async () => {
  if (!moveTargetStageId.value) return;
  const targetId = Number(moveTargetStageId.value);
  if (targetId === opportunity.value?.crm_stage_id) return;
  try {
    await store.dispatch('crmOpportunities/moveToStage', {
      id: opportunityIdNum.value,
      stageId: targetId,
    });
    moveTargetStageId.value = '';
  } catch (error) {
    useAlert(t('CRM_PIPELINE.OPPORTUNITY.MOVE_ERROR'));
  }
};

// Win/Lose/Discard
const lostReason = ref('');
const showLoseForm = ref(false);

const markWon = async () => {
  try {
    await store.dispatch('crmOpportunities/update', {
      id: opportunityIdNum.value,
      status: 'won',
    });
  } catch (error) {
    useAlert(t('CRM_PIPELINE.OPPORTUNITY.UPDATE_ERROR'));
  }
};

const markLost = async () => {
  try {
    await store.dispatch('crmOpportunities/update', {
      id: opportunityIdNum.value,
      status: 'lost',
      lost_reason: lostReason.value.trim() || null,
    });
    showLoseForm.value = false;
    lostReason.value = '';
  } catch (error) {
    useAlert(t('CRM_PIPELINE.OPPORTUNITY.UPDATE_ERROR'));
  }
};

const discard = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CRM_PIPELINE.OPPORTUNITY.DISCARD_CONFIRM'))) return;
  try {
    await store.dispatch('crmOpportunities/discard', opportunityIdNum.value);
    // [2026-05-17] Após discard o record é removido do store local; UI vai
    // entrar em "opportunityMissing" no próximo tick. Não navegamos
    // automaticamente — usuário escolhe próximo passo via back link no header.
  } catch (error) {
    useAlert(t('CRM_PIPELINE.OPPORTUNITY.DISCARD_ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden bg-n-background">
    <header
      class="flex items-center justify-between gap-4 px-6 py-4 border-b border-n-strong"
    >
      <div class="flex flex-col gap-1 min-w-0">
        <router-link
          :to="{ name: 'crm_home', params: { accountId } }"
          class="no-underline text-n-brand text-xs font-medium"
        >
          {{ t('CRM_PIPELINE.OPPORTUNITY.BACK_TO_HOME') }}
        </router-link>
        <div class="flex items-center gap-2 min-w-0">
          <h1 class="text-xl font-semibold text-n-slate-12 truncate">
            {{
              opportunity
                ? opportunity.name
                : t('CRM_PIPELINE.OPPORTUNITY.LOADING')
            }}
          </h1>
          <span
            v-if="opportunity"
            class="px-2 py-0.5 text-xs font-medium rounded-full"
            :class="statusBadgeClass"
          >
            {{ statusLabel }}
          </span>
        </div>
      </div>
    </header>

    <section
      v-if="isLoading"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <Spinner />
      <span class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.OPPORTUNITY.LOADING') }}
      </span>
    </section>

    <section
      v-else-if="opportunityMissing"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.OPPORTUNITY.NOT_FOUND') }}
      </p>
      <router-link
        :to="{ name: 'crm_home', params: { accountId } }"
        class="no-underline text-n-brand text-sm font-medium"
      >
        {{ t('CRM_PIPELINE.OPPORTUNITY.BACK_TO_HOME') }}
      </router-link>
    </section>

    <div
      v-else-if="opportunity"
      class="flex flex-col gap-6 p-6 overflow-y-auto flex-1"
    >
      <!-- Info card / Edit form -->
      <section
        class="flex flex-col gap-3 p-4 rounded-lg border border-n-strong bg-n-solid-1"
      >
        <header class="flex items-center justify-between gap-3">
          <h2 class="text-sm font-semibold text-n-slate-12">
            {{ t('CRM_PIPELINE.OPPORTUNITY.INFO_SECTION') }}
          </h2>
          <button
            v-if="!isEditing"
            type="button"
            class="px-3 py-1.5 text-xs rounded-md border border-n-strong text-n-slate-12 hover:bg-n-alpha-2"
            @click="startEdit"
          >
            {{ t('CRM_PIPELINE.OPPORTUNITY.EDIT_BUTTON') }}
          </button>
        </header>

        <form
          v-if="isEditing"
          class="grid grid-cols-1 md:grid-cols-2 gap-3"
          @submit.prevent="submitEdit"
        >
          <label
            class="flex flex-col gap-1 text-xs text-n-slate-11 md:col-span-2"
          >
            {{ t('CRM_PIPELINE.OPPORTUNITY.NAME_LABEL') }}
            <input
              v-model="editForm.name"
              type="text"
              required
              class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            {{ t('CRM_PIPELINE.OPPORTUNITY.VALUE_LABEL') }}
            <input
              v-model="editForm.value"
              type="number"
              step="0.01"
              min="0"
              class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            {{ t('CRM_PIPELINE.OPPORTUNITY.CURRENCY_LABEL') }}
            <input
              v-model="editForm.currency"
              type="text"
              maxlength="3"
              class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12 uppercase"
            />
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            {{ t('CRM_PIPELINE.OPPORTUNITY.CLOSE_DATE_LABEL') }}
            <input
              v-model="editForm.expected_close_date"
              type="date"
              class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            {{ t('CRM_PIPELINE.OPPORTUNITY.PROBABILITY_LABEL') }}
            <input
              v-model="editForm.probability"
              type="number"
              min="0"
              max="100"
              step="1"
              class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
            />
          </label>
          <div class="flex justify-end gap-2 md:col-span-2">
            <button
              type="button"
              class="px-3 py-1.5 text-xs rounded-md border border-n-strong text-n-slate-12"
              @click="cancelEdit"
            >
              {{ t('CRM_PIPELINE.OPPORTUNITY.CANCEL_BUTTON') }}
            </button>
            <button
              type="submit"
              :disabled="isUpdating || !editForm.name.trim()"
              class="px-3 py-1.5 text-xs font-medium rounded-md bg-n-brand text-white hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {{ t('CRM_PIPELINE.OPPORTUNITY.SAVE_BUTTON') }}
            </button>
          </div>
        </form>

        <dl v-else class="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs uppercase text-n-slate-11">
              {{ t('CRM_PIPELINE.OPPORTUNITY.NAME_LABEL') }}
            </dt>
            <dd class="text-n-slate-12">{{ opportunity.name }}</dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs uppercase text-n-slate-11">
              {{ t('CRM_PIPELINE.OPPORTUNITY.VALUE_LABEL') }}
            </dt>
            <dd class="text-n-slate-12">{{ formattedValue }}</dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs uppercase text-n-slate-11">
              {{ t('CRM_PIPELINE.OPPORTUNITY.PIPELINE_LABEL') }}
            </dt>
            <dd class="text-n-slate-12">{{ pipelineName }}</dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs uppercase text-n-slate-11">
              {{ t('CRM_PIPELINE.OPPORTUNITY.STAGE_LABEL') }}
            </dt>
            <dd class="text-n-slate-12">{{ currentStageName }}</dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs uppercase text-n-slate-11">
              {{ t('CRM_PIPELINE.OPPORTUNITY.COMPANY_LABEL') }}
            </dt>
            <dd class="text-n-slate-12">
              <router-link
                v-if="opportunity.crm_company_id"
                :to="{
                  name: 'crm_company_detail',
                  params: {
                    accountId,
                    companyId: opportunity.crm_company_id,
                  },
                }"
                class="no-underline text-n-brand"
              >
                {{
                  company?.name ||
                  opportunity.company?.name ||
                  `#${opportunity.crm_company_id}`
                }}
              </router-link>
              <span v-else class="text-n-slate-11">
                {{ t('CRM_PIPELINE.OPPORTUNITY.NO_COMPANY') }}
              </span>
            </dd>
          </div>
          <!-- [2026-05-17] Contact lookup precisa do store de contacts core.
               Slice 2 mostra só o id como placeholder (sem fetch extra de
               contacts pra evitar carregar lista inteira só pra um nome).
               TODO future slice: usar contact API single show ou embedded
               serializer no opportunity payload. -->
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs uppercase text-n-slate-11">
              {{ t('CRM_PIPELINE.OPPORTUNITY.CONTACT_LABEL') }}
            </dt>
            <dd class="text-n-slate-12">
              <template v-if="opportunity.contact_id">
                #{{ opportunity.contact_id }}
              </template>
              <span v-else class="text-n-slate-11">
                {{ t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_UNAVAILABLE') }}
              </span>
            </dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs uppercase text-n-slate-11">
              {{ t('CRM_PIPELINE.OPPORTUNITY.CLOSE_DATE_LABEL') }}
            </dt>
            <dd class="text-n-slate-12">{{ formattedCloseDate }}</dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs uppercase text-n-slate-11">
              {{ t('CRM_PIPELINE.OPPORTUNITY.PROBABILITY_LABEL') }}
            </dt>
            <dd class="text-n-slate-12">
              <template
                v-if="
                  opportunity.probability !== null &&
                  opportunity.probability !== undefined
                "
              >
                {{ opportunity.probability }}%
              </template>
              <span v-else class="text-n-slate-11">
                {{ t('CRM_PIPELINE.COMPANIES.DETAIL.INFO_UNAVAILABLE') }}
              </span>
            </dd>
          </div>
        </dl>
      </section>

      <!-- Actions card: move stage + win/lose/discard -->
      <section
        v-if="!isEditing"
        class="flex flex-wrap items-end gap-3 p-4 rounded-lg border border-n-strong bg-n-solid-1"
      >
        <label
          class="flex flex-col gap-1 text-xs text-n-slate-11 min-w-[200px]"
        >
          {{ t('CRM_PIPELINE.OPPORTUNITY.MOVE_STAGE') }}
          <div class="flex gap-2">
            <select
              v-model="moveTargetStageId"
              :disabled="stages.length === 0 || isMoving"
              class="flex-1 px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
            >
              <option value="" disabled>
                {{ t('CRM_PIPELINE.OPPORTUNITY.STAGE_LABEL') }}
              </option>
              <option
                v-for="stage in stages"
                :key="stage.id"
                :value="stage.id"
                :disabled="stage.id === opportunity.crm_stage_id"
              >
                {{ stage.name }}
              </option>
            </select>
            <button
              type="button"
              :disabled="!moveTargetStageId || isMoving"
              class="px-3 py-1.5 text-xs font-medium rounded-md border border-n-strong text-n-slate-12 disabled:opacity-50 disabled:cursor-not-allowed"
              @click="moveToStage"
            >
              {{ t('CRM_PIPELINE.OPPORTUNITY.MOVE_STAGE') }}
            </button>
          </div>
        </label>

        <div class="flex flex-wrap gap-2 ml-auto">
          <button
            type="button"
            :disabled="isUpdating || opportunity.status === 'won'"
            class="px-3 py-1.5 text-xs font-medium rounded-md bg-n-teal-9 text-white hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"
            @click="markWon"
          >
            {{ t('CRM_PIPELINE.OPPORTUNITY.WIN_BUTTON') }}
          </button>
          <button
            type="button"
            :disabled="isUpdating || opportunity.status === 'lost'"
            class="px-3 py-1.5 text-xs font-medium rounded-md bg-n-ruby-9 text-white hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"
            @click="showLoseForm = !showLoseForm"
          >
            {{ t('CRM_PIPELINE.OPPORTUNITY.LOSE_BUTTON') }}
          </button>
          <button
            type="button"
            :disabled="isDiscarding"
            class="px-3 py-1.5 text-xs font-medium rounded-md border border-n-strong text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50 disabled:cursor-not-allowed"
            @click="discard"
          >
            {{ t('CRM_PIPELINE.OPPORTUNITY.DISCARD_BUTTON') }}
          </button>
        </div>

        <form
          v-if="showLoseForm"
          class="flex w-full gap-2 items-end"
          @submit.prevent="markLost"
        >
          <label class="flex-1 flex flex-col gap-1 text-xs text-n-slate-11">
            {{ t('CRM_PIPELINE.OPPORTUNITY.LOSE_BUTTON') }}
            <input
              v-model="lostReason"
              type="text"
              class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
            />
          </label>
          <button
            type="submit"
            :disabled="isUpdating"
            class="px-3 py-1.5 text-xs font-medium rounded-md bg-n-ruby-9 text-white hover:opacity-90 disabled:opacity-50"
          >
            {{ t('CRM_PIPELINE.OPPORTUNITY.LOSE_BUTTON') }}
          </button>
        </form>
      </section>

      <ActivityList :opportunity-id="opportunityIdNum" />
    </div>
  </div>
</template>
