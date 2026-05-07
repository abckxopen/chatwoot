# [2026-05-07] Policy Pundit pra CRM Opportunity. DIVERGE de Pipeline/Stage/Company:
# Opportunities são dados de trabalho — agentes criam e operam SUAS opps.
# Admin tem tudo. Agent owns update/move/discard se for o assignee. Destroy
# é admin-only (perda definitiva — discard preserva histórico).
class Holding::Crm::OpportunityPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    @account_user.administrator? || assigned_to_user?
  end

  def move_to_stage?
    update?
  end

  def discard?
    update?
  end

  def destroy?
    @account_user.administrator?
  end

  private

  def assigned_to_user?
    @record.assignee_id == @account_user.user_id
  end
end
