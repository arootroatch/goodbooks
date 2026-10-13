require "rails_helper"

RSpec.describe EstimatedPayment do
  let(:tax_year) { create(:tax_year, year: 2026) }
  let(:debit) { create(:transaction, posted_on: Date.new(2026, 6, 12), amount_cents: -450_000, payee: "IRS USATAXPYMT") }

  it "takes amount, date, and a default quarter from the linked debit" do
    payment = tax_year.estimated_payments.new
    payment.link(debit)
    payment.save!
    expect(payment).to have_attributes(amount_cents: 450_000, paid_on: Date.new(2026, 6, 12), quarter: 2, debit:)
  end

  it "defaults a January payment to Q4" do
    payment = tax_year.estimated_payments.create!(paid_on: Date.new(2027, 1, 10), amount: "1,000")
    expect(payment.quarter).to eq(4)
  end

  it "keeps a quarter chosen by hand" do
    expect(tax_year.estimated_payments.create!(paid_on: Date.new(2026, 4, 15), amount: "500", quarter: 2).quarter).to eq(2)
  end

  it "refuses money in" do
    payment = tax_year.estimated_payments.new
    payment.link(create(:transaction, amount_cents: 1_000))
    expect(payment).not_to be_valid
    expect(payment.errors[:debit]).to include("must be money paid out")
  end

  it "refuses a debit already recorded" do
    tax_year.estimated_payments.new.tap { _1.link(debit) }.save!
    second = tax_year.estimated_payments.new.tap { _1.link(debit) }
    expect(second).not_to be_valid
    expect(second.errors[:debit_id]).to include("is already recorded as a payment")
  end

  it "keeps the payment as a manual one when the debit is deleted" do
    payment = tax_year.estimated_payments.new.tap { _1.link(debit) }
    payment.save!
    debit.destroy!
    expect(payment.reload.debit_id).to be_nil
    expect(payment.amount_cents).to eq(450_000)
  end

  it "requires a positive amount and a date" do
    expect(tax_year.estimated_payments.new(paid_on: Date.new(2026, 4, 1), amount: "0")).not_to be_valid
    expect(tax_year.estimated_payments.new(amount: "10")).not_to be_valid
  end
end
