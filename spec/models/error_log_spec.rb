require "rails_helper"

RSpec.describe ErrorLog do
  def raised(error_class = RuntimeError, message = "boom")
    raise error_class, message
  rescue error_class => e
    e
  end

  def report(error, context: {}) = described_class.new.report(error, handled: false, severity: :error, context:)

  it "records an unhandled error with its source and actor" do
    controller = InvoicesController.new.tap { _1.action_name = "create" }
    user = create(:user)
    Current.set(audit_actor: user) { report(raised, context: { controller: }) }
    expect(ErrorEvent.last).to have_attributes(error_class: "RuntimeError", message: "boom", source: "InvoicesController#create",
                                               occurrences: 1, last_user_id: user.id)
  end

  it "groups repeats and reopens a resolved error" do
    error = raised
    report(error)
    ErrorEvent.last.update!(resolved_at: Time.current)
    report(error)
    expect(ErrorEvent.count).to eq(1)
    expect(ErrorEvent.last).to have_attributes(occurrences: 2, resolved_at: nil)
  end

  it "truncates long messages" do
    report(raised(RuntimeError, "x" * 5_000))
    expect(ErrorEvent.last.message.length).to eq(1_000)
  end

  it "skips 4xx exceptions and warnings" do
    report(raised(ActiveRecord::RecordNotFound))
    described_class.new.report(raised, handled: true, severity: :warning, context: {})
    expect(ErrorEvent.count).to eq(0)
  end

  it "never raises, even when saving fails" do
    allow(ErrorEvent).to receive(:find_or_initialize_by).and_raise(ActiveRecord::StatementInvalid, "db gone")
    expect(Rails.logger).to receive(:error).with(/ErrorLog failed/)
    expect { report(raised) }.not_to raise_error
  end

  it "is subscribed to Rails.error" do
    expect { Rails.error.report(raised, handled: false, severity: :error) }.to change(ErrorEvent, :count).by(1)
  end
end
