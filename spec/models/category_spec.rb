require "rails_helper"

RSpec.describe Category do
  describe "gross receipts" do
    let(:business) { create(:business) }
    let!(:sales) { create(:category, :income, business: business, name: "Sales") }
    let!(:archived) { create(:category, :income, business: business, name: "Old", archived_at: Time.current) }
    let!(:other_income) { create(:category, business: business, name: "Interest", kind: "income", schedule_c_line: "6") }
    let!(:expense) { create(:category, business: business, name: "Supplies") }

    it "is true only for active income on line 1" do
      expect(sales).to be_gross_receipts
      expect(archived).not_to be_gross_receipts
      expect(other_income).not_to be_gross_receipts
      expect(expense).not_to be_gross_receipts
    end

    it "scopes to the same categories" do
      expect(business.categories.gross_receipts).to contain_exactly(sales)
    end
  end

  it "can't change kind while deposits in it are linked to invoices" do
    payment = create(:invoice_payment)
    category = payment.deposit.category
    category.assign_attributes(kind: "expense", schedule_c_line: "18")
    expect(category).not_to be_valid
    expect(category.errors[:kind]).to include("can't change while deposits in this category are linked to invoices")
  end

  it "allows changing kind when no deposits are linked" do
    category = create(:category, :income)
    category.assign_attributes(kind: "expense", schedule_c_line: "18")
    expect(category).to be_valid
  end

  it "requires an income line for income categories" do
    expect(build(:category, kind: "income", schedule_c_line: "18")).not_to be_valid
    expect(build(:category, kind: "income", schedule_c_line: "1")).to be_valid
  end

  it "requires an expense line for expense categories" do
    expect(build(:category, kind: "expense", schedule_c_line: "1")).not_to be_valid
  end

  it "does not allow line 30 (home office comes from sub-project 6)" do
    expect(build(:category, schedule_c_line: "30")).not_to be_valid
  end

  it "keeps deductible_bps between 0 and 10000" do
    expect(build(:category, deductible_bps: 10_001)).not_to be_valid
    expect(build(:category, deductible_bps: -1)).not_to be_valid
  end

  describe "#deductible_percent" do
    it "reads bps as a percent string" do
      expect(build(:category, deductible_bps: 5000).deductible_percent).to eq("50")
      expect(build(:category, deductible_bps: 3333).deductible_percent).to eq("33.33")
    end

    it "writes a percent string as bps" do
      category = build(:category, deductible_percent: "33.33")
      expect(category.deductible_bps).to eq(3333)
    end

    it "accepts valid numeric forms" do
      expect(build(:category, deductible_percent: "50").deductible_bps).to eq(5000)
      expect(build(:category, deductible_percent: "33.33").deductible_bps).to eq(3333)
      expect(build(:category, deductible_percent: "100").deductible_bps).to eq(10_000)
    end

    it "rejects rational form" do
      category = build(:category, deductible_percent: "1/2")
      expect(category).not_to be_valid
      expect(category.errors[:deductible_percent]).to include("is not a number")
    end

    it "rejects scientific notation" do
      category = build(:category, deductible_percent: "1e2")
      expect(category).not_to be_valid
      expect(category.errors[:deductible_percent]).to include("is not a number")
    end

    it "rejects underscore separators" do
      category = build(:category, deductible_percent: "1_0")
      expect(category).not_to be_valid
      expect(category.errors[:deductible_percent]).to include("is not a number")
    end

    it "rejects empty string" do
      category = build(:category, deductible_percent: "")
      expect(category).not_to be_valid
      expect(category.errors[:deductible_percent]).to include("is not a number")
    end

    it "flags garbage" do
      category = build(:category, deductible_percent: "half")
      expect(category).not_to be_valid
      expect(category.errors[:deductible_percent]).to include("is not a number")
    end
  end

  it "has a unique name per business" do
    existing = create(:category)
    expect(build(:category, business: existing.business, name: existing.name)).not_to be_valid
  end

  describe "personal categories" do
    let(:book) { create(:business, :personal) }

    it "has no Schedule C line" do
      expect(build(:category, business: book)).to be_valid
      expect(build(:category, business: book, schedule_c_line: "18")).not_to be_valid
    end

    it "can be not tithable (income) or a tithe payment (expense)" do
      expect(create(:category, :income, business: book, tithable: false)).not_to be_tithable
      expect(create(:category, business: book, tithe: true)).to be_tithe
    end

    it "normalizes flags that don't apply to the kind" do
      expense = create(:category, business: book, tithable: false)
      expect(expense).to be_tithable
      income = create(:category, :income, business: book, tithe: true)
      expect(income).not_to be_tithe
    end
  end

  it "rejects tithe flags on business categories" do
    expect(build(:category, tithe: true)).not_to be_valid
    expect(build(:category, :income, tithable: false)).not_to be_valid
  end

  it "applies the personal template to a personal book" do
    book = create(:business, :personal)
    CategoryTemplate.apply_to(book)
    expect(book.categories.find_by!(name: "Tithe")).to be_tithe
    expect(book.categories.find_by!(name: "Refunds and reimbursements")).not_to be_tithable
    expect(book.categories.where.not(schedule_c_line: nil)).to be_empty
  end

  describe "sales tax treatment" do
    let(:business) { create(:business) }

    it "defaults income on line 1 to taxable and other income to not a sale" do
      expect(create(:category, :income, business: business).sales_tax_treatment).to eq("taxable")
      other = create(:category, business: business, kind: "income", schedule_c_line: "6")
      expect(other.sales_tax_treatment).to eq("not_a_sale")
    end

    it "treats a blank treatment as the default" do
      expect(create(:category, :income, business: business, sales_tax_treatment: "").sales_tax_treatment).to eq("taxable")
    end

    it "keeps an explicit treatment and rejects unknown ones" do
      exempt = create(:category, :income, business: business, sales_tax_treatment: "exempt")
      expect(exempt.sales_tax_treatment).to eq("exempt")
      expect(exempt).not_to be_taxable
      expect(exempt).to be_sale
      expect(build(:category, :income, business: business, sales_tax_treatment: "wholesale")).not_to be_valid
    end

    it "clears the treatment on expense and personal categories" do
      expect(create(:category, business: business, sales_tax_treatment: "taxable").sales_tax_treatment).to be_nil
      book = create(:business, :personal)
      expect(create(:category, :income, business: book).sales_tax_treatment).to be_nil
    end

    it "clears the treatment when an income category becomes an expense" do
      category = create(:category, :income, business: business)
      category.update!(kind: "expense", schedule_c_line: "18")
      expect(category.sales_tax_treatment).to be_nil
    end
  end

  describe "sales tax remittance kind" do
    it "has no Schedule C line and belongs only to business books" do
      remittance = create(:category, kind: "sales_tax_remittance", schedule_c_line: "18")
      expect(remittance.schedule_c_line).to be_nil
      expect(remittance).to be_sales_tax_remittance
      expect(remittance).not_to be_income

      book = create(:business, :personal)
      personal = build(:category, business: book, kind: "sales_tax_remittance")
      expect(personal).not_to be_valid
      expect(personal.errors[:kind]).to include("can't be a sales tax remittance on the personal book")
    end

    it "allows one active remittance category per business" do
      first = create(:category, kind: "sales_tax_remittance", name: "Sales tax remittance")
      second = build(:category, business: first.business, kind: "sales_tax_remittance", name: "TN remittance")
      expect(second).not_to be_valid
      expect(second.errors[:kind]).to include("already has a sales tax remittance category")
      first.update!(archived_at: Time.current)
      expect(second).to be_valid
    end
  end

  describe "processor fees flag" do
    let(:business) { create(:business) }

    it "is allowed on one business expense category" do
      create(:category, business: business, name: "Merchant fees", schedule_c_line: "10", processor_fees: true)
      second = build(:category, business: business, name: "Stripe fees", schedule_c_line: "10", processor_fees: true)
      expect(second).not_to be_valid
      expect(second.errors[:processor_fees]).to include("is already set on another category")
    end

    it "is rejected on income and on the personal book" do
      expect(build(:category, :income, business: business, processor_fees: true)).not_to be_valid
      book = create(:business, :personal)
      expect(build(:category, business: book, processor_fees: true)).not_to be_valid
    end
  end
end
