class InboxesController < ApplicationController
  include BusinessScoped

  def show
    head :ok
  end
end
