<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'shared/components/Spinner.vue';

const props = defineProps({
  opportunityId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const store = useStore();

// [2026-05-17] Number coercion no mesmo padrão de PipelineKanban /
// CompanyDetail — getters comparam com Number(), evita mismatch silencioso.
const opportunityIdNum = computed(() => Number(props.opportunityId));

const allActivities = useMapGetter('crmActivities/getCrmActivities');
const activitiesUiFlags = useMapGetter('crmActivities/getUIFlags');

// [2026-05-17] Filtro client-side mirror do CompanyDetail: o getter dedicado
// `getCrmActivitiesForOpportunity` existe mas o pai já dispara
// `crmActivities/get(opportunityId)` antes de montar este componente, então
// records carrega só atividades dessa opp. Filtrar de novo é defensivo
// (impede leak se o cache vier "sujo" de outra opp no mesmo flat array).
const activities = computed(() =>
  allActivities.value.filter(
    a => a.crm_opportunity_id === opportunityIdNum.value
  )
);

// [2026-05-17] Ordenação: open primeiro por due_at asc (mais próximo no topo),
// completed por baixo desc (mais recente primeiro). due_at vem como epoch
// seconds (jbuilder usa `&.to_i`), comparação numérica direta funciona.
const sortedActivities = computed(() => {
  const open = activities.value.filter(a => !a.completed_at);
  const completed = activities.value.filter(a => a.completed_at);
  open.sort((a, b) => (a.due_at || Infinity) - (b.due_at || Infinity));
  completed.sort((a, b) => (b.completed_at || 0) - (a.completed_at || 0));
  return [...open, ...completed];
});

const isLoading = computed(() => activitiesUiFlags.value.fetchingList);
const isCreating = computed(() => activitiesUiFlags.value.creatingItem);
const isCompleting = computed(() => activitiesUiFlags.value.completing);
const isDeleting = computed(() => activitiesUiFlags.value.deletingItem);

// [2026-05-17] Kind enum espelha backend Holding::Crm::Activity (call=0..task=4).
// Sem assignee picker: requer lookup de users — adiar pra próxima slice.
const KIND_OPTIONS = ['call', 'email', 'meeting', 'note', 'task'];
const kindLabel = kind =>
  t(`CRM_PIPELINE.ACTIVITIES.KIND_OPTIONS.${kind.toUpperCase()}`);

const showForm = ref(false);
const form = ref({
  kind: 'task',
  subject: '',
  due_at: '',
  description: '',
});

const resetForm = () => {
  form.value = { kind: 'task', subject: '', due_at: '', description: '' };
};

const openForm = () => {
  resetForm();
  showForm.value = true;
};

const cancelForm = () => {
  showForm.value = false;
  resetForm();
};

const submitForm = async () => {
  if (!form.value.subject.trim()) return;
  // [2026-05-17] `<input type="datetime-local">` retorna string
  // "YYYY-MM-DDTHH:MM" sem timezone. new Date() trata como local time;
  // toISOString() converte pra UTC, formato que Rails aceita direto.
  const payload = {
    opportunityId: opportunityIdNum.value,
    kind: form.value.kind,
    subject: form.value.subject.trim(),
    description: form.value.description.trim() || null,
    due_at: form.value.due_at
      ? new Date(form.value.due_at).toISOString()
      : null,
  };
  try {
    await store.dispatch('crmActivities/create', payload);
    showForm.value = false;
    resetForm();
  } catch (error) {
    useAlert(t('CRM_PIPELINE.ACTIVITIES.CREATE_ERROR'));
  }
};

const completeActivity = async activity => {
  if (activity.completed_at) return;
  try {
    await store.dispatch('crmActivities/complete', {
      opportunityId: opportunityIdNum.value,
      id: activity.id,
    });
  } catch (error) {
    useAlert(t('CRM_PIPELINE.ACTIVITIES.COMPLETE_ERROR'));
  }
};

const deleteActivity = async activity => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CRM_PIPELINE.ACTIVITIES.DELETE_CONFIRM'))) return;
  try {
    await store.dispatch('crmActivities/delete', {
      opportunityId: opportunityIdNum.value,
      id: activity.id,
    });
  } catch (error) {
    useAlert(t('CRM_PIPELINE.ACTIVITIES.DELETE_ERROR'));
  }
};

// [2026-05-17] Relative time inline — evita locale de date-fns + carrega
// tradução PT-BR via i18n strings ("Em 2h", "Vencido há 3d"). Granularidade
// minuto/hora/dia é suficiente pro funil. Backend manda epoch seconds.
const RELATIVE_UNITS = [
  { limit: 60, divisor: 1, suffix: 's' },
  { limit: 3600, divisor: 60, suffix: 'min' },
  { limit: 86400, divisor: 3600, suffix: 'h' },
  { limit: Infinity, divisor: 86400, suffix: 'd' },
];

const formatRelativeTime = seconds => {
  const abs = Math.abs(seconds);
  const unit = RELATIVE_UNITS.find(u => abs < u.limit);
  return `${Math.max(1, Math.floor(abs / unit.divisor))}${unit.suffix}`;
};

const relativeLabel = activity => {
  if (activity.completed_at) {
    const ago = Math.floor(Date.now() / 1000) - activity.completed_at;
    return t('CRM_PIPELINE.ACTIVITIES.DUE_RELATIVE.COMPLETED', {
      time: formatRelativeTime(ago),
    });
  }
  if (!activity.due_at) return '';
  const diff = activity.due_at - Math.floor(Date.now() / 1000);
  if (Math.abs(diff) < 60) {
    return t('CRM_PIPELINE.ACTIVITIES.DUE_RELATIVE.DUE_NOW');
  }
  if (diff < 0) {
    return t('CRM_PIPELINE.ACTIVITIES.DUE_RELATIVE.OVERDUE', {
      time: formatRelativeTime(diff),
    });
  }
  return t('CRM_PIPELINE.ACTIVITIES.DUE_RELATIVE.DUE_IN', {
    time: formatRelativeTime(diff),
  });
};

// [2026-05-17] Cor neutra por kind (sem rich graphics, só badge text):
// distingue visualmente sem virar carnaval; mantém aderência ao n-* tokens.
const KIND_BADGE_CLASS = {
  call: 'bg-n-alpha-2 text-n-slate-12',
  email: 'bg-n-alpha-2 text-n-slate-12',
  meeting: 'bg-n-alpha-2 text-n-slate-12',
  note: 'bg-n-alpha-2 text-n-slate-12',
  task: 'bg-n-alpha-2 text-n-slate-12',
};

const kindBadgeClass = kind =>
  KIND_BADGE_CLASS[kind] || 'bg-n-alpha-2 text-n-slate-12';
</script>

<template>
  <section
    class="flex flex-col gap-3 p-4 rounded-lg border border-n-strong bg-n-solid-1"
  >
    <header class="flex items-center justify-between gap-3">
      <h2 class="text-sm font-semibold text-n-slate-12">
        {{ t('CRM_PIPELINE.ACTIVITIES.SECTION_TITLE') }} ({{
          activities.length
        }})
      </h2>
      <button
        v-if="!showForm"
        type="button"
        class="px-3 py-1.5 text-xs font-medium rounded-md bg-n-brand text-white hover:opacity-90"
        @click="openForm"
      >
        {{ t('CRM_PIPELINE.ACTIVITIES.NEW_ACTIVITY_BUTTON') }}
      </button>
    </header>

    <form
      v-if="showForm"
      class="flex flex-col gap-3 p-3 rounded-md border border-n-weak bg-n-solid-2"
      @submit.prevent="submitForm"
    >
      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('CRM_PIPELINE.ACTIVITIES.KIND_LABEL') }}
          <select
            v-model="form.kind"
            class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-1 text-n-slate-12"
          >
            <option v-for="kind in KIND_OPTIONS" :key="kind" :value="kind">
              {{ kindLabel(kind) }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('CRM_PIPELINE.ACTIVITIES.DUE_AT_LABEL') }}
          <input
            v-model="form.due_at"
            type="datetime-local"
            class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-1 text-n-slate-12"
          />
        </label>
      </div>
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('CRM_PIPELINE.ACTIVITIES.SUBJECT_LABEL') }}
        <input
          v-model="form.subject"
          type="text"
          required
          class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-1 text-n-slate-12"
        />
      </label>
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('CRM_PIPELINE.ACTIVITIES.DESCRIPTION_LABEL') }}
        <textarea
          v-model="form.description"
          rows="2"
          class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-1 text-n-slate-12 resize-y"
        />
      </label>
      <div class="flex justify-end gap-2">
        <button
          type="button"
          class="px-3 py-1.5 text-xs rounded-md border border-n-strong text-n-slate-12"
          @click="cancelForm"
        >
          {{ t('CRM_PIPELINE.ACTIVITIES.CANCEL_BUTTON') }}
        </button>
        <button
          type="submit"
          :disabled="isCreating || !form.subject.trim()"
          class="px-3 py-1.5 text-xs font-medium rounded-md bg-n-brand text-white hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {{ t('CRM_PIPELINE.ACTIVITIES.CREATE_BUTTON') }}
        </button>
      </div>
    </form>

    <div
      v-if="isLoading"
      class="flex items-center justify-center py-6 gap-2 text-sm text-n-slate-11"
    >
      <Spinner />
      <span>{{ t('CRM_PIPELINE.ACTIVITIES.LOADING') }}</span>
    </div>

    <p
      v-else-if="sortedActivities.length === 0"
      class="text-sm text-n-slate-11 italic"
    >
      {{ t('CRM_PIPELINE.ACTIVITIES.EMPTY_STATE') }}
    </p>

    <ul v-else class="flex flex-col gap-2">
      <li
        v-for="activity in sortedActivities"
        :key="activity.id"
        class="flex items-start gap-3 p-3 rounded-md border border-n-weak bg-n-solid-2"
        :class="{ 'opacity-60': activity.completed_at }"
      >
        <input
          type="checkbox"
          class="mt-1 cursor-pointer disabled:cursor-not-allowed"
          :checked="!!activity.completed_at"
          :disabled="!!activity.completed_at || isCompleting"
          :aria-label="t('CRM_PIPELINE.ACTIVITIES.COMPLETE_BUTTON')"
          @change="completeActivity(activity)"
        />
        <div class="flex flex-col gap-1 min-w-0 flex-1">
          <div class="flex flex-wrap items-center gap-2">
            <span
              class="px-2 py-0.5 rounded-full text-xs font-medium"
              :class="kindBadgeClass(activity.kind)"
            >
              {{ kindLabel(activity.kind) }}
            </span>
            <span
              class="text-sm font-medium text-n-slate-12"
              :class="{ 'line-through': activity.completed_at }"
            >
              {{ activity.subject }}
            </span>
            <span
              v-if="relativeLabel(activity)"
              class="text-xs text-n-slate-11"
            >
              {{ relativeLabel(activity) }}
            </span>
          </div>
          <p
            v-if="activity.description"
            class="text-xs text-n-slate-11 line-clamp-3 whitespace-pre-wrap"
          >
            {{ activity.description }}
          </p>
        </div>
        <button
          type="button"
          :disabled="isDeleting"
          class="text-xs text-n-slate-11 hover:text-n-ruby-9 disabled:opacity-50"
          @click="deleteActivity(activity)"
        >
          {{ t('CRM_PIPELINE.ACTIVITIES.DELETE_BUTTON') }}
        </button>
      </li>
    </ul>
  </section>
</template>
