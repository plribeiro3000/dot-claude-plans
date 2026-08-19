# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CalendarAudit, :unit do
  let(:admin_identifiers_attributes) { [{ value: '1', company_id: company.id }] }
  let(:admin_role) { FactoryBot.create(:role, :admin, company_id: company.id) }
  let(:admin_seat) { FactoryBot.create(:seat, :admin, role_id: admin_role.id) }
  let(:calendar) { FactoryBot.create(:calendar, company_id: company.id, owner_id: admin.id) }
  let(:calendar_payment_type) { FactoryBot.create(:calendar_payment_type, calendar_id: calendar.id, payment_type_id: payment_type.id) }
  let(:constant_rule) { FactoryBot.build(:rule, :indicator) }
  let(:country) { FactoryBot.create(:country) }
  let(:group) { FactoryBot.create(:group, company_id: company.id, owner_id: admin.id) }
  let(:incentive) { FactoryBot.build(:incentive, :indicator, company_id: company.id, owner_id: admin.id, group_id: group.id) }
  let(:indicator_rule) { FactoryBot.build(:rule, :indicator, value: 'vendas') }
  let(:indicator_variable) { FactoryBot.create(:variable, :indicator, :number, company_id: company.id, key: 'vendas', owner_id: admin.id) }
  let(:output_plan_variable) { FactoryBot.create(:plan_variable, plan_id: sales_plan.id, variable_id: output_variable.id) }
  let(:output_variable) { FactoryBot.create(:variable, :output, :number, company_id: company.id, key: 'premio', owner_id: admin.id) }
  let(:payment_type) { FactoryBot.create(:payment_type, company_id: company.id, owner_id: admin.id) }
  let(:state) { FactoryBot.create(:state, country_id: country.id) }

  let(:admin) do
    FactoryBot.create(
      :user,
      :admin,
      company_id: company.id,
      identifiers_attributes: admin_identifiers_attributes,
      seat: admin_seat,
      state_id: state.id
    )
  end

  let(:company) do
    FactoryBot.create(
      :company,
      :call_center,
      countries: [country],
      manager_legal_module: false,
      retention_jurisdiction_country: country
    )
  end

  let(:audit) do
    FactoryBot.build(:calendar_audit, calendar_id: calendar.id, company_id: company.id, owner_id: admin.id)
  end

  let(:sales_plan) do
    FactoryBot.build(
      :plan,
      :sale,
      calendar_id: calendar.id,
      company_id: company.id,
      group_id: group.id,
      owner_id: admin.id,
      status: :final,
      incentivations_attributes: [{ incentive_id: incentive.id, payment_type_id: payment_type.id }]
    )
  end

  it { is_expected.to belong_to(:calendar).optional }
  it { is_expected.to belong_to(:commission).optional }
  it { is_expected.to belong_to(:company).optional }
  it { is_expected.to belong_to(:owner).class_name(User).optional }
  it { is_expected.to belong_to(:period).optional }
  it { is_expected.to belong_to(:plan).optional }
  it { is_expected.to have_many(:downloads).class_name(AuditDownload).inverse_of(:downloadable).dependent(:destroy) }
  it { is_expected.to have_many(:rows).class_name(CalendarAudit::Row).inverse_of(:calendar_audit).dependent(:destroy) }
  it { is_expected.to have_one(:attachment).class_name(AuditAttachment).inverse_of(:attachable).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:calendar_id) }

  it do
    expect(subject).to validate_inclusion_of(:type)
      .in_array(%w[CalendarAudit CommissionIndicatorAudit GroupAudit MonthlyUsageAudit PlanGoalAudit PlanStatementAudit ResponsibleAudit
                   StatementAudit UserAudit UserIdentifierAudit VariableAudit])
  end

  it do
    expect(subject).to enumerize(:status)
      .in(initial: 0, processing: 1, final: 2)
      .with_default(:initial)
      .with_scope(true)
  end

  describe '#variable_presence' do
    context 'when the final plan carries an output variable alongside an integration-fed one' do
      before do
        calendar_payment_type
        indicator_variable
        incentive.rules = [indicator_rule]
        incentive.save
        sales_plan.save
        output_plan_variable
        audit.valid?
      end

      it 'counts the integration-fed variable as expected' do
        expect(audit.errors.details[:calendar_id]).to be_empty
      end
    end

    context 'when the final plan carries an output variable alone' do
      before do
        calendar_payment_type
        incentive.rules = [constant_rule]
        incentive.save
        sales_plan.save
        output_plan_variable
        audit.valid?
      end

      it 'reports no expected variables' do
        expect(audit.errors.details[:calendar_id]).to eq([{ error: :missing_variables }])
      end
    end
  end
end
