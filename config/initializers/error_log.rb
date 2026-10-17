Rails.application.config.after_initialize { Rails.error.subscribe(ErrorLog.new) }
