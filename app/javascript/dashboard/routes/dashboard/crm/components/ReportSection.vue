<script setup>
import Spinner from 'shared/components/Spinner.vue';

// [2026-05-17] Wrapper das 3 sections de CrmReports.vue. Cada section tem
// o MESMO contrato visual (header com título + ações à direita) + os MESMOS
// 3 estados mutuamente exclusivos (loading → error → empty → default).
// Extrair eliminou ~14 LOC duplicadas × 3 sections.
//
// Precedência dos estados: loading > error > empty > default. Mantida igual
// à versão inline anterior (v-if/v-else-if encadeado). Mudar quebra a UX
// (ex.: erro ficaria escondido por "empty" enquanto refetch carrega).
//
// `actions` slot serve o filtro+refresh específico de cada section (refresh-only
// no summary; date pickers + refresh no agent_performance e forecast). Não
// movido pra prop pra não acoplar o wrapper a forma de input.
defineProps({
  title: { type: String, required: true },
  isLoading: { type: Boolean, default: false },
  hasError: { type: Boolean, default: false },
  isEmpty: { type: Boolean, default: false },
  errorMessage: { type: String, default: '' },
  emptyMessage: { type: String, default: '' },
});
</script>

<template>
  <section
    class="flex flex-col gap-3 p-4 rounded-lg border border-n-strong bg-n-solid-1"
  >
    <header class="flex flex-wrap items-end justify-between gap-3">
      <h2 class="text-base font-semibold text-n-slate-12">{{ title }}</h2>
      <div class="flex flex-wrap items-end gap-2">
        <slot name="actions" />
      </div>
    </header>

    <div v-if="isLoading" class="flex items-center justify-center py-8">
      <Spinner />
    </div>
    <p
      v-else-if="hasError"
      class="text-sm text-n-slate-11 italic py-6 text-center"
    >
      {{ errorMessage }}
    </p>
    <p
      v-else-if="isEmpty"
      class="text-sm text-n-slate-11 italic py-6 text-center"
    >
      {{ emptyMessage }}
    </p>
    <slot v-else />
  </section>
</template>
