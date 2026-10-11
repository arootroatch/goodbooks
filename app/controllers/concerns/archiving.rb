# Archive and Unarchive row buttons. Including controllers load the record in a before_action and define #archivable.
module Archiving
  def archive = set_archived(Time.current, "archived")
  def unarchive = set_archived(nil, "unarchived")

  private

  def set_archived(archived_at, verb)
    record = archivable
    if record.update(archived_at:)
      redirect_back_or_to polymorphic_path([ @business, record.class ]), notice: "#{record.model_name.human} #{verb}."
    else
      redirect_back_or_to polymorphic_path([ @business, record.class ]), alert: record.errors.full_messages.to_sentence
    end
  end
end
