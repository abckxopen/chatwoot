require 'rails_helper'

RSpec.describe Holding::Crm::Company do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:opportunities).class_name('Holding::Crm::Opportunity').with_foreign_key(:crm_company_id) }
  end

  describe 'validations' do
    subject { build(:holding_crm_company) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:account_id) }

    describe 'domain format' do
      it { is_expected.to allow_value('abckx.com.br', 'inteligenciaavancada.com', 'sub.example.io').for(:domain) }
      # [2026-05-01] `http://no-protocol.com` saiu da lista — após
      # normalize_domain strippar o `http://` o que sobra é um domínio
      # válido. Para testar input estritamente inválido pós-normalize,
      # use formas sem TLD ou com chars inválidos.
      it { is_expected.not_to allow_value('not a domain', '123', '.com', 'no-tld').for(:domain) }

      it 'allow blank domain' do
        expect(build(:holding_crm_company, domain: nil)).to be_valid
      end
    end

    describe 'additional_attributes size cap' do
      let(:account) { create(:account) }

      it 'aceita additional_attributes pequeno' do
        c = build(:holding_crm_company, account: account, additional_attributes: { region: 'BR-RS', tier: 'gold' })
        expect(c).to be_valid
      end

      it 'rejeita additional_attributes > 16KB serializado' do
        big_value = 'a' * 20_000
        c = build(:holding_crm_company, account: account, additional_attributes: { bloat: big_value })
        expect(c).not_to be_valid
        expect(c.errors).to be_of_kind(:additional_attributes, :too_large)
      end
    end
  end

  describe '#normalize_domain' do
    let(:account) { create(:account) }

    it 'strip protocol https://' do
      c = create(:holding_crm_company, account: account, domain: 'https://abckx.com.br')
      expect(c.domain).to eq('abckx.com.br')
    end

    it 'strip protocol http:// e www.' do
      c = create(:holding_crm_company, account: account, domain: 'http://www.abckx.com.br')
      expect(c.domain).to eq('abckx.com.br')
    end

    it 'strip path após domínio' do
      c = create(:holding_crm_company, account: account, domain: 'abckx.com.br/sobre')
      expect(c.domain).to eq('abckx.com.br')
    end

    it 'lowercase' do
      c = create(:holding_crm_company, account: account, domain: 'AbCkX.COM.BR')
      expect(c.domain).to eq('abckx.com.br')
    end
  end

  describe 'event dispatch' do
    before { allow(Rails.configuration.dispatcher).to receive(:dispatch) }

    it 'dispara crm.company.created on create' do
      company = create(:holding_crm_company)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::COMPANY_CREATED, kind_of(Time), company: company
      )
    end

    it 'dispara crm.company.updated on update' do
      company = create(:holding_crm_company)
      company.update!(industry: 'finance')
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::COMPANY_UPDATED, kind_of(Time), company: company
      ).at_least(:once)
    end
  end
end
