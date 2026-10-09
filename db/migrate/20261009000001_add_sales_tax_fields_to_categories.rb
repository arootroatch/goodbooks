class AddSalesTaxFieldsToCategories < ActiveRecord::Migration[8.1]
  class MigrationBusiness < ActiveRecord::Base
    self.table_name = "businesses"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  def up
    add_column :categories, :sales_tax_treatment, :string
    add_column :categories, :processor_fees, :boolean, null: false, default: false
    add_index :categories, :business_id, unique: true, where: "processor_fees", name: "index_categories_one_processor_fees_per_business"
    MigrationCategory.reset_column_information

    business_ids = MigrationBusiness.where(kind: "business").pluck(:id)
    income = MigrationCategory.where(business_id: business_ids, kind: "income")
    income.where(schedule_c_line: "1").update_all(sales_tax_treatment: "taxable")
    income.where(sales_tax_treatment: nil).update_all(sales_tax_treatment: "not_a_sale")

    business_ids.each do |business_id|
      scope = MigrationCategory.where(business_id: business_id, kind: "expense", archived_at: nil)
      existing = scope.find_by(name: "Merchant fees")
      if existing
        existing.update_columns(processor_fees: true)
      else
        name = MigrationCategory.exists?(business_id: business_id, name: "Merchant fees") ? "Merchant fees (processor)" : "Merchant fees"
        MigrationCategory.create!(business_id: business_id, name: name, kind: "expense", schedule_c_line: "10",
                                  deductible_bps: 10_000, processor_fees: true)
      end
    end
  end

  def down
    remove_index :categories, name: "index_categories_one_processor_fees_per_business"
    remove_column :categories, :processor_fees
    remove_column :categories, :sales_tax_treatment
  end
end
