# [2026-05-17] Controller read-only para relatórios do CRM da holding (slice 3
# da Phase 4 — fecha Phase 4). Três endpoints aggregation-only:
#
#   GET pipeline_summary   — count + valor por stage de um pipeline
#   GET agent_performance  — assignment / won / lost / win-rate por agente
#   GET forecast           — projeção mensal (value × probability) de opps abertas
#
# Defesa em camadas mesma dos outros 5 crm_* controllers (ver
# CrmPipelinesController header pra detalhe):
# 1. Gate por conta via HoldingCrmConcern → 403 se holding_crm_enabled=false
# 2. Tenancy scope EXPLÍCITO em toda query (Current.account.id)
# 3. Sem Pundit authorize — relatórios são leitura pública dentro do account
#    (admin + agent), igual a Pipeline#index. Adicionar policy mais granular
#    (filtro por assignee no agent_performance pra esconder par-de-agente)
#    fica pra Phase 5 se virar requisito comercial.
#
# Implementação MVP:
# - Queries via ActiveRecord (group/sum/count). Tudo cabe em SQL simples;
#   mover pra materialized view + refresh job só faz sentido quando a base
#   passar de ~100k opps — overhead de manutenção da view não compensa
#   antes disso. Se chegar lá, criar `crm_pipeline_summary_mv` + cron
#   `refresh materialized view concurrently` 5min e trocar a fonte aqui.
# - Soma de `value` sem conversão de currency (apenas BRL no MVP da holding;
#   ALLOWED_CURRENCIES do Opportunity inclui USD/EUR/GBP mas vila ainda
#   opera só BRL). Mix de currencies geraria erro de leitura ("R$ 145.000"
#   somando USD); quando holding aceitar multi-currency real, agregar
#   convertendo no servidor via Open Exchange Rates ou similar. UI por ora
#   exibe o número cru — não anota currency no axis.
# - `probability` nil = 50 (default neutro), espelhando default do schema
#   migration (`default: 0` foi mantido pra valores legados; em opps novas
#   o controller força preencher). Forecast sem este fallback excluiria opps
#   antigas — pior que assumir 50%.
class Api::V1::Accounts::CrmReportsController < Api::V1::Accounts::BaseController
  include HoldingCrmConcern

  # GET /api/v1/accounts/:account_id/crm_reports/pipeline_summary?pipeline_id=N
  def pipeline_summary
    pipeline = find_pipeline
    return render_pipeline_not_found unless pipeline

    # [2026-05-17] N+1 evitado: 2 queries totais (count + sum agrupados por
    # stage) em vez de 2N. Sem isto seria 1 count + 1 sum por stage —
    # barato hoje, perigoso quando pipeline tiver 20+ stages. Rails group+sum
    # / group+count retornam hashes {stage_id => valor}; merge no map abaixo.
    base = opportunities_scope.where(crm_pipeline_id: pipeline.id, status: :open)
    counts = base.group(:crm_stage_id).count
    sums = base.group(:crm_stage_id).sum(:value)

    stages = pipeline.stages.order(:position, :id).map do |stage|
      {
        stage_id: stage.id,
        stage_name: stage.name,
        position: stage.position,
        opportunities_count: counts.fetch(stage.id, 0),
        total_value: format_decimal(sums.fetch(stage.id, 0))
      }
    end

    render json: {
      pipeline_id: pipeline.id,
      pipeline_name: pipeline.name,
      stages: stages
    }
  end

  # GET /api/v1/accounts/:account_id/crm_reports/agent_performance?from=&to=
  def agent_performance
    from = parse_date(params[:from]) || 30.days.ago.to_date
    to = parse_date(params[:to]) || Date.current
    range = from.beginning_of_day..to.end_of_day

    # [2026-05-17] account.users segue o has_many em Account upstream
    # (account_users → user). Inclui admin + agent + roles custom — qualquer
    # User com membership no account aparece, mesmo que nunca tenha pego opp
    # (linha com zeros). Filtrar quem não tem opp no período economizaria
    # rows mas perderia "agente sem performance no período" — esse é o
    # próprio sinal que o relatório serve pra mostrar.
    agents = Current.account.users.order(:id).map do |user|
      build_agent_row(user, range)
    end

    render json: {
      from: from.to_s,
      to: to.to_s,
      agents: agents
    }
  end

  # GET /api/v1/accounts/:account_id/crm_reports/forecast?pipeline_id=N&until=YYYY-MM-DD
  def forecast
    pipeline = find_pipeline
    return render_pipeline_not_found unless pipeline

    until_date = parse_date(params[:until]) || Date.current.end_of_quarter
    payload = forecast_payload(pipeline, until_date)

    render json: { pipeline_id: pipeline.id, until: until_date.to_s, **payload }
  end

  private

  def opportunities_scope
    @opportunities_scope ||= Holding::Crm::Opportunity.where(account_id: Current.account.id)
  end

  def find_pipeline
    Holding::Crm::Pipeline.where(account_id: Current.account.id).find_by(id: params[:pipeline_id])
  end

  def render_pipeline_not_found
    render json: { error: 'pipeline_not_found' }, status: :not_found
  end

  def build_agent_row(user, range)
    user_opps = opportunities_scope.where(assignee_id: user.id)
    assigned = user_opps.where(created_at: range).count

    won_opps = user_opps.where(status: :won, won_at: range)
    won_count = won_opps.count
    won_value = won_opps.sum(:value)

    # [2026-05-17] lost usa `lost_at` (auto-set no callback do model em
    # status → lost), não `updated_at`. updated_at varia com qualquer edit
    # subsequente (mudar lost_reason após perder), inflando o range
    # arbitrariamente. lost_at é fixado uma vez quando a opp vira lost,
    # alinhando com won_at e dando paridade semântica.
    lost_count = user_opps.where(status: :lost, lost_at: range).count

    decided = won_count + lost_count
    win_rate = decided.zero? ? 0.0 : (won_count.to_f / decided).round(3)

    {
      user_id: user.id,
      user_name: user.name,
      opportunities_assigned: assigned,
      opportunities_won: won_count,
      won_value: format_decimal(won_value),
      opportunities_lost: lost_count,
      win_rate: win_rate
    }
  end

  # [2026-05-17] Extraído do #forecast pra ficar abaixo do limite AbcSize
  # do rubocop. Pull + group + map + sum num só lugar isolado.
  def forecast_payload(pipeline, until_date)
    # IGNORA opps sem expected_close_date — sem data não dá pra projetar em mês.
    rows = opportunities_scope
           .where(crm_pipeline_id: pipeline.id, status: :open)
           .where.not(expected_close_date: nil)
           .where('expected_close_date <= ?', until_date)
           .pluck(:expected_close_date, :value, :probability)

    monthly = rows
              .group_by { |close_date, _, _| close_date.strftime('%Y-%m') }
              .map { |month, group| build_forecast_row(month, group) }
              .sort_by { |row| row[:month] }

    total = monthly.sum { |row| row[:projected_value].to_f }
    { monthly_projection: monthly, total_projected: format_decimal(total) }
  end

  def build_forecast_row(month, rows)
    projected = rows.sum do |_close_date, value, probability|
      base_value = value || 0
      # probability nil ou 0 — ambos tratados como 50 (default neutro).
      # Ver header do controller pra justificativa.
      prob = probability&.positive? ? probability : 50
      base_value * (prob.to_f / 100)
    end
    {
      month: month,
      projected_value: format_decimal(projected),
      opportunities_count: rows.length
    }
  end

  def parse_date(str)
    return nil if str.blank?

    Date.parse(str.to_s)
  rescue ArgumentError
    nil
  end

  # [2026-05-17] Decimal formatado como string com 2 casas — payload JSON
  # com BigDecimal vira "0.45e3" em alguns serializers (Oj/render json
  # padrão), e Float perde precisão em soma. Sprintf "%.2f" garante shape
  # "450.00" estável pra frontend `Number(value)` parsear e helpers de
  # currency renderizar sem hack.
  def format_decimal(value)
    format('%.2f', value || 0)
  end
end
