// [2026-05-17] Helpers compartilhados entre páginas/components do CRM.
// Extraído após rule-of-three: formatCurrency aparecia em PipelineKanban,
// CompanyDetail e OpportunityDetail. Mover pra cá evita drift silencioso
// (ex.: alguém ajustar locale/fallback num só lugar).

// pt-BR fixo: o produto é Holding-only e o spec não cita i18n de número.
// Intl rejeita ISO inválido — fallback "CCC 0.00" mantém o valor legível
// em vez de quebrar a UI inteira por currency exótica.
export const formatCurrency = (value, currency) => {
  try {
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency,
    }).format(value);
  } catch {
    return `${currency} ${Number(value).toFixed(2)}`;
  }
};

// Mesmo wrapper repetido em Kanban + CompanyDetail + (computed inline em
// OpportunityDetail). Recebe `t` por argumento pra não acoplar o helper ao
// useI18n() — chamadores já têm `t` em escopo do componente.
export const formatOpportunityValue = (opp, t) => {
  if (opp.value === null || opp.value === undefined) {
    return t('CRM_PIPELINE.KANBAN.CARD_VALUE_PLACEHOLDER');
  }
  return formatCurrency(Number(opp.value), opp.currency || 'BRL');
};
