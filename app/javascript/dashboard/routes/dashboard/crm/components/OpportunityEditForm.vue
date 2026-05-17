<script setup>
import { reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  opportunity: { type: Object, required: true },
  isSubmitting: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'cancel']);

const { t } = useI18n();

// [2026-05-17] Form state local — extraído de OpportunityDetail pra isolar
// edit affordance. Parent controla isEditing (v-if) e dispara dispatch ao
// receber `save`. Mantemos reactive (não ref) pra v-model direto em cada
// campo sem .value boilerplate.
const form = reactive({
  name: '',
  value: '',
  currency: 'BRL',
  expected_close_date: '',
  probability: '',
});

const seedFromOpportunity = opp => {
  form.name = opp.name || '';
  form.value = opp.value ?? '';
  form.currency = opp.currency || 'BRL';
  // [2026-05-17] expected_close_date vem como ISO date (jbuilder usa &.iso8601);
  // input type="date" precisa "YYYY-MM-DD" — slice funciona pois Date#iso8601
  // sem args é só data (sem time).
  form.expected_close_date = opp.expected_close_date
    ? String(opp.expected_close_date).slice(0, 10)
    : '';
  form.probability = opp.probability ?? '';
};

// Seed inicial + re-seed se a opp mudar enquanto o form estiver montado
// (raro, mas mantém consistência com store updates externos).
seedFromOpportunity(props.opportunity);
watch(
  () => props.opportunity,
  opp => {
    if (opp) seedFromOpportunity(opp);
  }
);

// [2026-05-17] Currency input em CAPS: normaliza no blur (ISO 4217 é maiúsculo).
// Não usamos transformer reativo pra não brigar com o cursor enquanto o
// usuário digita.
const normalizeCurrency = () => {
  form.currency = (form.currency || '').toUpperCase();
};

const submit = () => {
  if (!form.name.trim()) return;
  emit('save', {
    name: form.name.trim(),
    value: form.value === '' ? null : Number(form.value),
    currency: (form.currency || 'BRL').toUpperCase(),
    expected_close_date: form.expected_close_date || null,
    probability: form.probability === '' ? null : Number(form.probability),
  });
};
</script>

<template>
  <form class="grid grid-cols-1 md:grid-cols-2 gap-3" @submit.prevent="submit">
    <label class="flex flex-col gap-1 text-xs text-n-slate-11 md:col-span-2">
      {{ t('CRM_PIPELINE.OPPORTUNITY.NAME_LABEL') }}
      <input
        v-model="form.name"
        type="text"
        required
        class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
      />
    </label>
    <label class="flex flex-col gap-1 text-xs text-n-slate-11">
      {{ t('CRM_PIPELINE.OPPORTUNITY.VALUE_LABEL') }}
      <input
        v-model="form.value"
        type="number"
        step="0.01"
        min="0"
        class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
      />
    </label>
    <label class="flex flex-col gap-1 text-xs text-n-slate-11">
      {{ t('CRM_PIPELINE.OPPORTUNITY.CURRENCY_LABEL') }}
      <input
        v-model="form.currency"
        type="text"
        maxlength="3"
        class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12 uppercase"
        @blur="normalizeCurrency"
      />
    </label>
    <label class="flex flex-col gap-1 text-xs text-n-slate-11">
      {{ t('CRM_PIPELINE.OPPORTUNITY.CLOSE_DATE_LABEL') }}
      <input
        v-model="form.expected_close_date"
        type="date"
        class="px-2 py-1.5 text-sm rounded border border-n-strong bg-n-solid-2 text-n-slate-12"
      />
    </label>
    <label class="flex flex-col gap-1 text-xs text-n-slate-11">
      {{ t('CRM_PIPELINE.OPPORTUNITY.PROBABILITY_LABEL') }}
      <input
        v-model="form.probability"
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
        @click="emit('cancel')"
      >
        {{ t('CRM_PIPELINE.OPPORTUNITY.CANCEL_BUTTON') }}
      </button>
      <button
        type="submit"
        :disabled="isSubmitting || !form.name.trim()"
        class="px-3 py-1.5 text-xs font-medium rounded-md bg-n-brand text-white hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {{ t('CRM_PIPELINE.OPPORTUNITY.SAVE_BUTTON') }}
      </button>
    </div>
  </form>
</template>
