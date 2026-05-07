# [2026-05-07] Concern compartilhado pelos controllers CRM da holding
# (Pipelines, Stages, Companies, Opportunities, Activities). Extraído na
# slice 3 quando o 3º caller (Companies) ia replicar a lógica — gatilho
# da regra-de-3 pra DRY sem premature abstraction.
#
# `holding_crm_enabled` é coluna boolean dedicada (não feature_flags upstream)
# pra evitar limite de 63 features e não vazar config em custom_attributes
# (ver migration AddHoldingCrmEnabledToAccounts).
#
# Tenancy scope NÃO está aqui — cada controller tem o próprio model alvo
# (Pipeline, Stage via pipeline, Company, Opportunity, Activity via
# opportunity). Centralizar adicionaria nesting/case statements que
# ofuscariam o controller. Cada `fetch_*` continua local.
module HoldingCrmConcern
  extend ActiveSupport::Concern

  included do
    before_action :ensure_feature_enabled
  end

  private

  def ensure_feature_enabled
    return if Current.account.holding_crm_enabled?

    render json: { error: I18n.t('errors.crm.feature_disabled') }, status: :forbidden
  end

  # [2026-05-07] per_page com clamp 1..100 — evita client pedir page=1, per=999999
  # e sobrecarregar DB. Default 25 alinhado com convenção Chatwoot.
  def per_page
    (params[:per_page] || 25).to_i.clamp(1, 100)
  end

  def page_param
    page = params[:page].to_i
    page.positive? ? page : 1
  end
end
