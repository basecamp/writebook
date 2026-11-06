# Thruster passes the client address in X-Forwarded-For, never in Forwarded, so
# a Forwarded header comes from the client. RemoteIp would trust it or, when it
# disagrees with X-Forwarded-For, raise IpSpoofAttackError and answer with a 500.
class DropForwardedHeader
  def initialize(app)
    @app = app
  end

  def call(env)
    env.delete("HTTP_FORWARDED")
    @app.call(env)
  end
end

Rails.application.config.middleware.insert_before ActionDispatch::RemoteIp, DropForwardedHeader
