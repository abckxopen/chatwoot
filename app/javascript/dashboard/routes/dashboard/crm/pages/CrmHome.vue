<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import Spinner from 'shared/components/Spinner.vue';

const { t } = useI18n();
const store = useStore();
// [2026-05-17] accountId vem de useAccount() (lê route.params.accountId);
// slice 3 precisa dele pra montar router-link pra crm_pipeline_kanban.
const { accountId } = useAccount();

// [2026-05-17] Module registrado em store/index.js como `crmPipelines`.
// Action upstream-style é simplesmente `get` (não `getCrmPipelines`).
// Slice 3 reusa este getter pra montar a sidebar de pipelines no Kanban.
const pipelines = useMapGetter('crmPipelines/getCrmPipelines');
const uiFlags = useMapGetter('crmPipelines/getUIFlags');

const isLoading = computed(() => uiFlags.value.fetchingList);
const isEmpty = computed(() => pipelines.value.length === 0);

const fetchPipelines = () => store.dispatch('crmPipelines/get');

onMounted(fetchPipelines);
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden p-6 gap-6 bg-n-background">
    <header class="flex flex-col gap-1">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ t('CRM_PIPELINE.PAGE_HEADER') }}
      </h1>
      <p class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.PAGE_SUBHEADER') }}
      </p>
    </header>

    <section
      v-if="isLoading"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <Spinner />
      <span class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.LOADING') }}
      </span>
    </section>

    <section
      v-else-if="isEmpty"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('CRM_PIPELINE.EMPTY_STATE') }}
      </p>
      <!-- [2026-05-17] Retry no empty state cobre tanto "lista vazia legítima"
           quanto "falha no fetch" — action `crmPipelines/get` engole exception
           e mantém records=[], então não há flag dedicada de erro pra dispatchar. -->
      <button
        type="button"
        class="px-3 py-1.5 text-sm rounded-md border border-n-strong text-n-slate-12 hover:bg-n-alpha-2"
        @click="fetchPipelines"
      >
        {{ t('CRM_PIPELINE.RETRY') }}
      </button>
    </section>

    <section
      v-else
      class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4 overflow-y-auto"
    >
      <article
        v-for="pipeline in pipelines"
        :key="pipeline.id"
        class="flex flex-col gap-3 p-4 rounded-lg border border-n-strong bg-n-solid-1"
      >
        <header class="flex flex-col gap-1">
          <h2 class="text-base font-semibold text-n-slate-12 truncate">
            {{ pipeline.name }}
          </h2>
          <p
            v-if="pipeline.description"
            class="text-sm text-n-slate-11 line-clamp-2"
          >
            {{ pipeline.description }}
          </p>
        </header>
        <footer class="flex justify-end">
          <router-link
            :to="{
              name: 'crm_pipeline_kanban',
              params: { accountId, pipelineId: pipeline.id },
            }"
            class="no-underline text-n-brand text-sm font-medium"
          >
            {{ t('CRM_PIPELINE.OPEN_KANBAN') }}
          </router-link>
        </footer>
      </article>
    </section>
  </div>
</template>
