# [2026-05-07] Activities operacionais — qualquer agente CRUD/complete na sua
# conta. Tenancy via controller (nested @opportunity.activities). Destroy é
# admin-only por parity com Opportunity: hard-delete sem trace + risco de
# perder histórico do funil.
class Holding::Crm::ActivityPolicy < ApplicationPolicy
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
    true
  end

  def complete?
    true
  end

  def destroy?
    @account_user.administrator?
  end
end
