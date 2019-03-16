require './src/auth'
require './src/users'
require './src/threads'

module Router
  def self.route(req)
    # TODO check method
    sessid = req.cookies['sessid'] # TODO validate sessid cookie
    session = Auth.get_session_from_sessid(sessid)

    query = Rack::Utils.parse_query(req.path, '/').keys
    case query[0]
    when nil
      return index(session)
    when 'login'
      return session.nil? ? Auth.login(req) : index(session, true)
    when 'logout'
      return Auth.logout(req)
    when 'user'
      # TODO validate username (query[1])
      return query[1].nil? ? not_found : Users.get_user(query[1], session)
    when 'submit'
      return session.nil? ? index(session, true) : Threads.submit(req, session)
    when 'thread'
      return query[1].nil? ? not_found : Threads.thread(query[1], session)
    else
      return not_found
    end
  end

  def self.index(session = nil, redirect = false, _headers = {})
    threads = Threads.get_threads # retrieve index page threads

    headers = {}
    status = 200
    if redirect
      headers['Location'] = '/'
      status = 302
    end

    headers.merge!(_headers)

    return View.finalize('index', status, {
      session: session,
      threads: threads
    }, headers)
  end

  def self.not_found
    body = ['404 Not found']
    return Rack::Response.new(body, 200, {"Content-Type" => "text/plain"})
  end
end