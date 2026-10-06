class CsvImportsController < ApplicationController
  include BusinessScoped

  before_action :require_editor!
  before_action :set_account
  before_action :set_import, only: %i[show commit destroy]

  def new
    @import = @account.csv_imports.new
  end

  def create
    file = params.dig(:csv_import, :file)
    @import = @account.csv_imports.new
    if file.is_a?(ActionDispatch::Http::UploadedFile)
      @import.file = file
    else
      @import.errors.add(:file, "must be a file upload")
      return render :new, status: :unprocessable_content
    end

    if @import.save
      redirect_to @account.mapped? ? import_path : edit_business_account_csv_import_mapping_path(@business, @account, @import)
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    return redirect_to edit_business_account_csv_import_mapping_path(@business, @account, @import) unless @account.mapped?

    @preview = @import.preview if @import.previewed?
    @transcoded = @import.transcoded? if @preview
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
  rescue ActiveRecord::RecordNotUnique
    redirect_to import_path, alert: "Some rows were already imported. Refresh and try again."
  end

  def destroy
    discarded = @import.with_lock { @import.update!(status: "discarded") if @import.previewed? }
    return redirect_to(import_path, alert: "This import was already #{@import.status}.", status: :see_other) unless discarded

    @import.file.purge
    redirect_to business_accounts_path(@business), notice: "Import discarded.", status: :see_other
  end

  private

  def set_account
    @account = @business.accounts.active.csv.find(params[:account_id])
  end

  def set_import
    @import = @account.csv_imports.find(params[:id])
  end

  def import_path = business_account_csv_import_path(@business, @account, @import)
end
