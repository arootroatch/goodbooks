class ClientsController < ApplicationController
  include BusinessScoped
  include Archiving
  include BusinessKindOnly

  PERMITTED = %i[name email notes].freeze

  before_action :require_editor!, except: :index
  before_action :set_client, only: %i[edit update archive unarchive]

  def index
    @show_archived = params[:archived] == "1"
    @clients = @business.clients.order(:archived_at, :name)
    @clients = @clients.active unless @show_archived
  end

  def new
    @client = @business.clients.new
  end

  def create
    @client = @business.clients.new(params.expect(client: PERMITTED))
    if @client.save
      redirect_to business_clients_path(@business), notice: "Client added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @client.update(params.expect(client: PERMITTED))
      redirect_to business_clients_path(@business), notice: "Client updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def archivable = @client

  def set_client
    @client = @business.clients.find(params[:id])
  end
end
