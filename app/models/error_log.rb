# Rails.error subscriber: groups server errors from requests and jobs into ErrorEvents for the owner's Errors page.
# Stores no params, headers or cookies, and never raises.
class ErrorLog
  BACKTRACE_LINES = 30
  MESSAGE_LIMIT = 1_000

  def report(error, handled:, severity:, context:, source: nil)
    return unless severity == :error
    return if ActionDispatch::ExceptionWrapper.status_code_for_exception(error.class.name) < 500

    record(error, context)
  rescue StandardError => e
    Rails.logger.error("ErrorLog failed to record #{error.class}: #{e.class}: #{e.message}")
  end

  private

  def record(error, context)
    now = Time.current
    backtrace = Rails.backtrace_cleaner.clean(error.backtrace || [])
    event = ErrorEvent.find_or_initialize_by(fingerprint: fingerprint(error, backtrace))
    event.assign_attributes(error_class: error.class.name, message: error.message.to_s.truncate(MESSAGE_LIMIT, omission: ""),
                            backtrace: backtrace.first(BACKTRACE_LINES).join("\n"), source: source_for(context),
                            last_seen_at: now, last_user_id: Current.actor&.id, resolved_at: nil)
    event.first_seen_at ||= now
    event.occurrences = event.new_record? ? 1 : event.occurrences + 1
    event.save!
  end

  def fingerprint(error, backtrace)
    Digest::SHA256.hexdigest("#{error.class.name}|#{backtrace.find { _1.start_with?("app/") } || backtrace.first}")
  end

  def source_for(context)
    if (controller = context[:controller])
      "#{controller.class.name}##{controller.action_name}"
    elsif (job = context[:job])
      job.class.name
    end
  end
end
