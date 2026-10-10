module AppHost
  # SECRET_KEY_BASE_DUMMY is set only while the Docker image precompiles assets.
  def self.fetch!(env = ENV)
    return "localhost" if env["SECRET_KEY_BASE_DUMMY"].present?

    env["APP_HOST"].presence or raise "APP_HOST is blank. Set it in docker-compose.yml (see README)."
  end
end
