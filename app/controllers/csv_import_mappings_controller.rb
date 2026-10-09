class CsvImportMappingsController < ApplicationController
  include BusinessScoped

  PERMITTED = %i[skip_rows date_column date_format payee_column memo_column amount_column debit_column credit_column invert_sign].freeze

  before_action :require_editor!
  before_action :set_import
  before_action :require_previewed

  def edit
    @mapping = @account.mapping
    @mapping.skip_rows = params[:skip_rows].to_i if params[:skip_rows].present?
    load_headers
  end

  def update
    @mapping = CsvImport::Mapping.new(params.expect(csv_import_mapping: PERMITTED))
    if @mapping.valid?
      ApplicationRecord.transaction do
        @account.update!(csv_mapping: @mapping.to_h)
        @import.update!(mapping: @mapping.to_h)
      end
      redirect_to business_account_csv_import_path(@business, @account, @import)
    else
      load_headers
      render :edit, status: :unprocessable_content
    end
  end

  private

  def require_previewed
    redirect_to business_account_csv_import_path(@business, @account, @import) unless @import.previewed?
  end

  def set_import
    @account = @business.accounts.active.csv_importable.find(params[:account_id])
    @import = @account.csv_imports.find(params[:csv_import_id])
  end

  def load_headers
    @headers = CsvImport::Parser.headers(@import.content, skip_rows: @mapping.skip_rows.to_i)
  rescue CsvImport::Parser::FileError => e
    @headers = []
    @file_error = e.message
  end
end
