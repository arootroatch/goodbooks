module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed[:session_id] = { value: session.id, httponly: true, same_site: :lax, expires: 30.days }
      end
    end

    PENDING_TTL = 10.minutes

    def begin_two_factor(user)
      user.generate_otp_secret! unless user.otp_enabled?
      return_to = session[:return_to_after_authenticating]
      reset_session
      session[:return_to_after_authenticating] = return_to if return_to
      session[:pending_user_id] = user.id
      session[:pending_at] = Time.current.to_i
      redirect_to user.otp_enabled? ? new_two_factor_path : new_two_factor_setup_path
    end

    def pending_user
      return if session[:pending_user_id].blank?
      return if session[:pending_at].to_i < PENDING_TTL.ago.to_i

      User.find_by(id: session[:pending_user_id])
    end

    def complete_two_factor(user)
      session.delete(:pending_user_id)
      session.delete(:pending_at)
      start_new_session_for(user)
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
