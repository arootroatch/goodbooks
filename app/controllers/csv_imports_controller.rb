class CsvImportsController < ApplicationController
  include BusinessScoped

  before_action :require_editor!
  before_action :set_account
  before_action :set_import, only: %i[show commit destroy]

  def new
    @import = @account.csv_imports.new
  end

  def create
    @import = @account.csv_imports.new(file: params.dig(:csv_import, :file))
    if @import.save
      redirect_to @account.mapped? ? import_path : edit_business_account_csv_import_mapping_path(@business, @account, @import)
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    return redirect_to edit_business_account_csv_import_mapping_path(@business, @account, @import) unless @account.mapped?

    @preview = @import.preview
  rescue CsvImport::Parser::FileError => e
    @file_error = e.message
  end

  def commit
    @import.commit!
    redirect_to business_transactions_path(@business, account_id: @account.id),
      notice: "Imported #{@import.new_count} new transactions (#{@import.duplicate_count} duplicates skipped, " \
              "#{@import.error_count} rows with errors)."
  rescue CsvImport::NotPreviewed, CsvImport::Parser::FileError => e
    redirect_to import_path, alert: e.message
  end

  def destroy
    @import.update!(status: "discarded")
    @import.file.purge
    redirect_to business_accounts_path(@business), notice: "Import discarded.", status: :see_other
  end

  private

  def set_account
    @account = @business.accounts.csv.find(params[:account_id])
  end

  def set_import
    @import = @account.csv_imports.find(params[:id])
  end

  def import_path = business_account_csv_import_path(@business, @account, @import)
end
