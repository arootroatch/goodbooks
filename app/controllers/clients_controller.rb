class ClientsController < ApplicationController
  include BusinessScoped

  PERMITTED = %i[name email notes].freeze

  before_action :require_editor!, except: :index
  before_action :set_client, only: %i[edit update]

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
    attrs = params.expect(client: [ *PERMITTED, :archived ])
    archived = attrs.delete(:archived)
    @client.assign_attributes(attrs)
    @client.archived_at = archived == "1" ? (@client.archived_at || Time.current) : nil unless archived.nil?
    if @client.save
      redirect_to business_clients_path(@business), notice: "Client updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_client
    @client = @business.clients.find(params[:id])
  end
end
